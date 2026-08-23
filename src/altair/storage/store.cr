# Altair — file storage.
#
require "digest/sha256"
require "openssl/hmac"

module Altair
  module Storage
    # Metadata for a stored upload.
    struct File
      getter key : String
      getter filename : String
      getter content_type : String?

      def initialize(@key : String, @filename : String, @content_type : String?)
      end
    end

    # The backend contract for uploaded files.
    abstract class Store
      # Persists an uploaded file under a generated or supplied key.
      abstract def upload(upload : Altair::HTTP::UploadedFile, key : String? = nil) : File

      # Deletes a stored key, returning whether a file existed.
      abstract def delete(key : String) : Bool

      # The application-visible URL for a stored key.
      abstract def url(key : String) : String
    end

    # Stores uploads beneath `public/uploads`, where the static middleware
    # can serve them without a separate controller.
    class DiskStore < Store
      getter root : Path
      getter public_prefix : String

      def initialize(@root : Path, @public_prefix : String = "/uploads")
      end

      def upload(upload : Altair::HTTP::UploadedFile, key : String? = nil) : File
        filename = upload.original_filename || "upload"
        stored_key = key || "#{Random::Secure.hex(16)}/#{safe_filename(filename)}"
        path = path_for(stored_key)
        Dir.mkdir_p(path.parent.to_s)
        ::File.write(path, upload.content)
        File.new(stored_key, filename, upload.content_type)
      end

      def delete(key : String) : Bool
        path = path_for(key)
        return false unless ::File.exists?(path)
        ::File.delete(path)
        true
      end

      def url(key : String) : String
        "#{public_prefix}/#{key.split('/').map { |part| URI.encode_path(part) }.join("/")}"
      end

      private def path_for(key : String) : Path
        raise ArgumentError.new("storage key must not escape its root") if key.split('/').any? { |part| part.empty? || part == "." || part == ".." }
        root.join(key)
      end

      private def safe_filename(filename : String) : String
        filename.gsub(/[^A-Za-z0-9._-]/, "_")
      end
    end

    # Uploads to an S3-compatible endpoint using AWS Signature Version 4.
    # Supports both virtual-host-style (bucket.s3.region.amazonaws.com) and
    # path-style (s3.region.amazonaws.com/bucket) endpoints via the
    # `path_style:` parameter. MinIO and DigitalOcean Spaces use path-style.
    class S3Store < Store
      getter bucket : String
      getter region : String
      getter endpoint : URI
      getter? path_style : Bool

      def initialize(@bucket : String, @region : String, @access_key_id : String,
                     @secret_access_key : String, endpoint : String? = nil,
                     @prefix : String = "", path_style : Bool? = nil,
                     @timeout : Time::Span = 30.seconds)
        @endpoint = URI.parse(endpoint || "https://#{bucket}.s3.#{region}.amazonaws.com")
        @path_style = path_style.nil? ? !@endpoint.host.not_nil!.includes?(@bucket) : path_style
      end

      def upload(upload : Altair::HTTP::UploadedFile, key : String? = nil) : File
        filename = upload.original_filename || "upload"
        stored_key = key || "#{Random::Secure.hex(16)}/#{safe_filename(filename)}"
        path = request_path(stored_key)
        headers = signed_headers("PUT", path, upload.content, upload.content_type || "application/octet-stream")
        response = execute("PUT", path, headers, upload.content)
        unless response.success?
          raise Altair::Error.new("S3 upload failed: #{response.status_code} #{response.body[0, 200]}")
        end
        File.new(stored_key, filename, upload.content_type)
      end

      def delete(key : String) : Bool
        path = request_path(key)
        response = execute("DELETE", path, signed_headers("DELETE", path, "", nil))
        response.success? || response.status_code == 404
      rescue ex : IO::Error | Socket::Addrinfo::Error
        raise Altair::Error.new("S3 network failure: #{ex.message}")
      end

      def url(key : String) : String
        if path_style?
          "#{endpoint}/#{bucket}/#{object_key(key)}"
        else
          "#{endpoint.scheme}://#{bucket}.#{endpoint.host}#{endpoint.port ? ":#{endpoint.port}" : ""}/#{object_key(key)}"
        end
      end

      private def execute(method : String, path : String, headers : ::HTTP::Headers, body : String? = nil) : ::HTTP::Client::Response
        client = ::HTTP::Client.new(@endpoint)
        client.connect_timeout = @timeout
        client.read_timeout = @timeout
        begin
          case method
          when "PUT"    then client.put(path, headers: headers, body: body)
          when "DELETE" then client.delete(path, headers: headers)
          else               raise ArgumentError.new("Unsupported S3 method: #{method}")
          end
        rescue ex : IO::Error | Socket::Addrinfo::Error
          raise Altair::Error.new("S3 network failure: #{ex.message}")
        ensure
          client.close
        end
      end

      def signed_headers(method : String, path : String, body : String, content_type : String?) : ::HTTP::Headers
        now = Time.utc
        stamp = now.to_s("%Y%m%dT%H%M%SZ")
        date = now.to_s("%Y%m%d")
        payload_hash = Digest::SHA256.hexdigest(body)
        host_header = if path_style?
                        endpoint.host.not_nil!
                      else
                        endpoint.host.not_nil!
                      end
        headers = ::HTTP::Headers{"Host" => host_header, "X-Amz-Date" => stamp, "X-Amz-Content-Sha256" => payload_hash}
        headers["Content-Type"] = content_type if content_type
        signed = headers.map { |name, _| name.downcase }.sort!
        canonical_headers = signed.map { |name| "#{name}:#{headers[name]}\n" }.join
        canonical_request = "#{method}\n#{path}\n\n#{canonical_headers}\n#{signed.join(";")}\n#{payload_hash}"
        scope = "#{date}/#{region}/s3/aws4_request"
        string_to_sign = "AWS4-HMAC-SHA256\n#{stamp}\n#{scope}\n#{Digest::SHA256.hexdigest(canonical_request)}"
        signing_key = hmac_chain(date)
        signature = OpenSSL::HMAC.hexdigest(OpenSSL::Algorithm::SHA256, signing_key, string_to_sign)
        headers["Authorization"] = "AWS4-HMAC-SHA256 Credential=#{@access_key_id}/#{scope}, SignedHeaders=#{signed.join(";")}, Signature=#{signature}"
        headers
      end

      private def request_path(key : String) : String
        object = object_key(key)
        path_style? ? "/#{bucket}/#{object}" : "/#{object}"
      end

      private def object_key(key : String) : String
        [@prefix, key].reject(&.empty?).join('/').split('/').map { |part| URI.encode_path(part) }.join('/')
      end

      private def safe_filename(filename : String) : String
        filename.gsub(/[^A-Za-z0-9._-]/, "_")
      end

      private def hmac_chain(date : String) : String
        key = hmac("AWS4#{@secret_access_key}", date)
        key = hmac(key, region)
        key = hmac(key, "s3")
        hmac(key, "aws4_request")
      end

      private def hmac(key : String, value : String) : String
        String.new(OpenSSL::HMAC.digest(OpenSSL::Algorithm::SHA256, key, value))
      end
    end
  end

  # Returns the current application's configured storage backend.
  def self.storage : Altair::Storage::Store
    application_instance.try(&.config.storage) || raise Altair::ConfigurationError.new("No application instance")
  end
end
