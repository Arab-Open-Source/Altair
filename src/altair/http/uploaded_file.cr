# Altair — the batteries-included web framework for Crystal.
#
# This file defines `Altair::HTTP::UploadedFile`, the representation of a
# file uploaded through a `multipart/form-data` request. Controllers read
# uploads from the parameter bag (`params.upload("avatar")`) and receive
# this object, which carries the client-provided name and content type plus
# the raw bytes of the uploaded content.
module Altair
  module HTTP
    # A file that reached the application through a `multipart/form-data`
    # body. The uploaded bytes are buffered in memory at parse time, so the
    # file outlive the request that delivered it.
    class UploadedFile
      # The form field name the file was uploaded under, e.g. `"avatar"`.
      getter name : String

      # The filename the client attached to the upload, e.g. `"portrait.png"`.
      getter original_filename : String?

      # The media type the client claimed for the upload, e.g. `"image/png"`.
      getter content_type : String?

      # The size of the uploaded content in bytes, measured from the buffered
      # bytes rather than the client's declared `Content-Length`.
      getter size : Int64

      # The raw uploaded bytes, read eagerly when the part is parsed.
      getter content : String

      # The form field name the file was uploaded under. Mirrors the stdlib
      # `HTTP::FormData::Part#name` so handlers can read both interchangeably.
      def initialize(@name : String, @original_filename : String?, @content_type : String?,
                     @size : Int64, @content : String)
      end

      # The content as a `String`, decoded as bytes — safe to `File.write`
      # verbatim or to wrap in an `HTTP::Server::Response`.
      def read : String
        @content
      end

      # Saves the uploaded bytes to `path`, returning the path it wrote to.
      def save(path : Path) : Path
        File.write(path, @content)
        path
      end
    end
  end
end
