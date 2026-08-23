module Altair
  module Storage
    struct Attachment
      getter file : File

      def initialize(@file : File)
      end

      def url : String
        Altair.storage.url(file.key)
      end
    end

    module Attachments
      extend self

      def attach(record : Altair::Record::Model, name : String, upload : Altair::HTTP::UploadedFile) : Attachment
        pk = record.__pk || raise Altair::Error.new("save the record before attaching #{name}")
        ensure_table
        stored = Altair.storage.upload(upload)
        conn = Altair::Record.connection
        ph = conn.adapter.method(:placeholder)
        conn.exec(
          "DELETE FROM altair_attachments WHERE record_type = #{ph.call(0)} AND record_id = #{ph.call(1)} AND name = #{ph.call(2)}",
          record.class.name, pk.to_s, name
        )
        conn.exec(
          "INSERT INTO altair_attachments (record_type, record_id, name, key, filename, content_type) " \
          "VALUES (#{ph.call(0)}, #{ph.call(1)}, #{ph.call(2)}, #{ph.call(3)}, #{ph.call(4)}, #{ph.call(5)})",
          record.class.name, pk.to_s, name, stored.key, stored.filename, stored.content_type
        )
        Attachment.new(stored)
      end

      def find(record : Altair::Record::Model, name : String) : Attachment?
        pk = record.__pk
        return unless pk
        ensure_table
        conn = Altair::Record.connection
        ph = conn.adapter.method(:placeholder)
        conn.query_one?(
          "SELECT key, filename, content_type FROM altair_attachments " \
          "WHERE record_type = #{ph.call(0)} AND record_id = #{ph.call(1)} AND name = #{ph.call(2)}",
          record.class.name, pk.to_s, name
        ) do |rs|
          Attachment.new(File.new(rs.read(String), rs.read(String), rs.read(String?)))
        end
      end

      def purge(record : Altair::Record::Model, name : String) : Bool
        attachment = find(record, name)
        return false unless attachment
        conn = Altair::Record.connection
        ph = conn.adapter.method(:placeholder)
        conn.exec(
          "DELETE FROM altair_attachments WHERE record_type = #{ph.call(0)} AND record_id = #{ph.call(1)} AND name = #{ph.call(2)}",
          record.class.name, record.__pk.not_nil!.to_s, name
        )
        Altair.storage.delete(attachment.file.key)
      end

      private def ensure_table : Nil
        conn = Altair::Record.connection
        conn.exec(
          "CREATE TABLE IF NOT EXISTS altair_attachments (" \
          "record_type TEXT NOT NULL, record_id TEXT NOT NULL, name TEXT NOT NULL, " \
          "key TEXT NOT NULL, filename TEXT NOT NULL, content_type TEXT, " \
          "PRIMARY KEY (record_type, record_id, name))"
        )
      end
    end
  end
end
