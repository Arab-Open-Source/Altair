module Altair
  module Record
    class Model
      macro has_one_attached(name)
        # Returns the file attached under this association name.
        def {{ name.id }} : Altair::Storage::Attachment?
          Altair::Storage::Attachments.find(self, {{ name.id.stringify }})
        end

        # Stores an uploaded file against this persisted record.
        def attach_{{ name.id }}(upload : Altair::HTTP::UploadedFile) : Altair::Storage::Attachment
          Altair::Storage::Attachments.attach(self, {{ name.id.stringify }}, upload)
        end

        # Removes the attached file and its persisted metadata.
        def purge_{{ name.id }} : Bool
          Altair::Storage::Attachments.purge(self, {{ name.id.stringify }})
        end
      end
    end
  end
end
