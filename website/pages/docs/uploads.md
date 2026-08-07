# Uploads

`multipart/form-data` bodies are parsed into the parameter bag: scalar
fields become params, and files arrive as `Altair::HTTP::UploadedFile`
objects read through `params.upload`. The uploaded bytes are buffered in
memory at parse time, so a file outlives the request that delivered it.

## The form

A file field needs the form to carry `enctype="multipart/form-data"`. The
form builder passes extra attributes through to the `<form>` tag, so set it
directly (raw HTML works just as well):

```ecr
<% form_for("/posts", enctype: "multipart/form-data") do |f| %>
  <%= f.label("title", "Title") %>
  <%= f.text_field("title") %>
  <label for="image">Image</label>
  <input type="file" name="image" id="image">
  <%= f.submit("Create") %>
<% end %>
```

## Reading the upload

In the action, scalar fields land in `params` as usual; the file arrives
under the field name:

```crystal
def create : Nil
  post = Post.create(title: params["title"]?)

  if file = params.upload("image")
    file.name               # => "image" — the form field name
    file.original_filename  # => "portrait.png" — client-provided
    file.content_type       # => "image/png" — client-claimed media type
    file.size               # => Int64 — bytes, measured from the buffer
    file.content            # => String — the raw bytes
  end

  redirect_to posts_path
end
```

`params.upload("image")` returns `UploadedFile?` — `nil` when no file was
uploaded under that name, so a plain `if` guard is all you need.

## Saving the file

`UploadedFile#save` writes the bytes to a path and returns the path it
wrote to:

```crystal
def create : Nil
  if file = params.upload("avatar")
    dest = file.save(Path.new("public/uploads/#{file.original_filename}"))
    # "public/uploads/portrait.png" — served by the Static middleware
  end
end
```

`#read` returns the bytes as a String, safe to write verbatim or wrap in a
response:

```crystal
render text: file.read, content_type: "application/octet-stream"
```

> Prefer a filename you control over the client's `original_filename` when
> saving — the client-supplied value is untrusted input. A random name plus
> a kept mapping is the safe pattern for public directories.

## Multiple files

`params.uploads` returns every uploaded file keyed by form field name —
iterate its values to process them all:

```crystal
params.uploads.each_value do |file|
  file.save(Path.new("public/uploads/#{SecureRandom.uuid}"))
end
```

## Body limits

`config.max_body_size` (default 2 MB) applies while the body is read before
parsing; a request that exceeds it answers **413 Payload Too Large**. Raise
it for large uploads:

```crystal
config.max_body_size = 100.megabytes
```

See [Configuration](/docs/configuration.html) for per-environment tuning.
