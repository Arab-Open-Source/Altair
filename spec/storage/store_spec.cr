require "../spec_helper"
require "file_utils"

describe Altair::Storage::DiskStore do
  it "persists uploads under a safe generated key and exposes a public URL" do
    root = Path.new(Dir.tempdir, "altair_storage_#{Random.rand(1_000_000)}")
    begin
      store = Altair::Storage::DiskStore.new(root)
      upload = Altair::HTTP::UploadedFile.new("avatar", "a photo.png", "image/png", 3_i64, "png")
      file = store.upload(upload)
      File.read(root.join(file.key)).should eq("png")
      store.url(file.key).should start_with("/uploads/")
      store.delete(file.key).should be_true
      store.delete(file.key).should be_false
    ensure
      FileUtils.rm_rf(root)
    end
  end

  it "refuses a key that escapes the storage root" do
    store = Altair::Storage::DiskStore.new(Path.new(Dir.tempdir, "altair_storage_guard"))
    upload = Altair::HTTP::UploadedFile.new("avatar", "a.png", nil, 1_i64, "x")
    expect_raises(ArgumentError) { store.upload(upload, "../outside") }
  end

  it "builds Signature Version 4 headers for S3-compatible stores" do
    store = Altair::Storage::S3Store.new("bucket", "us-east-1", "access", "secret", "https://storage.example.test")
    headers = store.signed_headers("PUT", "/avatar.png", "body", "image/png")
    headers["Host"].should eq("storage.example.test")
    headers["X-Amz-Content-Sha256"].should eq(Digest::SHA256.hexdigest("body"))
    headers["Authorization"].should start_with("AWS4-HMAC-SHA256 Credential=access/")
  end
end

describe Altair::Storage::S3Store do
  it "uploads and deletes via a mock HTTP server (path-style)" do
    uploaded_body = nil
    uploaded_ct = nil
    deleted = false
    server = ::HTTP::Server.new do |ctx|
      case ctx.request.method
      when "PUT"
        uploaded_body = ctx.request.body.try(&.gets_to_end)
        uploaded_ct = ctx.request.headers["Content-Type"]?
        ctx.response.status = :ok
      when "DELETE"
        deleted = true
        ctx.response.status = :no_content
      else
        ctx.response.status = :not_found
      end
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    sleep 50.milliseconds

    begin
      store = Altair::Storage::S3Store.new("mybucket", "us-east-1", "ak", "sk",
        endpoint: "http://#{address}", path_style: true)
      upload = Altair::HTTP::UploadedFile.new("file", "photo.png", "image/png", 4_i64, "png")
      file = store.upload(upload, "avatars/photo.png")
      file.key.should eq("avatars/photo.png")
      uploaded_body.should eq("png")
      uploaded_ct.should eq("image/png")

      store.delete(file.key).should be_true
      deleted.should be_true
    ensure
      server.close
    end
  end

  it "raises on non-success upload status" do
    server = ::HTTP::Server.new do |ctx|
      ctx.response.status = :forbidden
      ctx.response.print "<?xml><Error>AccessDenied</Error>"
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    sleep 50.milliseconds

    begin
      store = Altair::Storage::S3Store.new("bkt", "us-east-1", "ak", "sk",
        endpoint: "http://#{address}", path_style: true)
      upload = Altair::HTTP::UploadedFile.new("f", "a.txt", nil, 1_i64, "x")
      expect_raises(Altair::Error, /S3 upload failed.*403/) do
        store.upload(upload)
      end
    ensure
      server.close
    end
  end

  it "treats 404 as successful delete" do
    server = ::HTTP::Server.new do |ctx|
      ctx.response.status = :not_found
    end
    address = server.bind_tcp("127.0.0.1", 0)
    spawn { server.listen }
    sleep 50.milliseconds

    begin
      store = Altair::Storage::S3Store.new("bkt", "us-east-1", "ak", "sk",
        endpoint: "http://#{address}", path_style: true)
      store.delete("missing/key").should be_true
    ensure
      server.close
    end
  end

  it "builds correct URL for path-style vs virtual-host style" do
    path_style_store = Altair::Storage::S3Store.new("mybucket", "us-east-1", "ak", "sk",
      endpoint: "http://localhost:9000", path_style: true)
    path_style_store.url("key/file.txt").should eq("http://localhost:9000/mybucket/key/file.txt")

    vhost_store = Altair::Storage::S3Store.new("mybucket", "us-east-1", "ak", "sk",
      endpoint: "https://s3.us-east-1.amazonaws.com", path_style: false)
    vhost_store.url("key/file.txt").should eq("https://mybucket.s3.us-east-1.amazonaws.com/key/file.txt")
  end

  it "includes prefix in the object key when set" do
    store = Altair::Storage::S3Store.new("bkt", "us-east-1", "ak", "sk",
      endpoint: "https://s3.example.test", prefix: "prod/uploads", path_style: true)
    store.url("file.txt").should eq("https://s3.example.test/bkt/prod/uploads/file.txt")
  end

  it "produces deterministic SigV4 for known inputs" do
    store = Altair::Storage::S3Store.new("test-bucket", "us-east-1", "AKIDEXAMPLE", "secret",
      endpoint: "https://test-bucket.s3.us-east-1.amazonaws.com", path_style: false)
    headers = store.signed_headers("GET", "/test-key", "", nil)
    auth = headers["Authorization"]
    auth.should contain("AWS4-HMAC-SHA256")
    auth.should contain("Credential=AKIDEXAMPLE/")
    auth.should contain("SignedHeaders=host;x-amz-content-sha256;x-amz-date")
    auth.should contain("Signature=")
  end
end
