# Altair — the batteries-included web framework for Crystal.
#
# This file adds the `password_auth` macro to `Altair::Record::Model`.
# One line declares password authentication over a string digest column:
# typed `password` / `password_confirmation` accessors, validation (length
# on assignment, presence on create, optional confirmation), hashing into
# the column through `Altair::Auth::PasswordHasher` in a before-save
# callback, and an instance `authenticate_password(candidate)` for login.
module Altair
  module Record
    class Model
      # Declares password authentication backed by the given string
      # digest column:
      #
      # ```
      # class User < Altair::Record::Model
      #   table :users
      #   password_auth # column :password_digest, min 8
      #   # password_auth min_length: 10    # custom floor
      # end
      #
      # user = User.new(email: "a@b.c")
      # user.password = "correct horse"
      # user.save
      # user.authenticate_password("correct horse") # => true
      # ```
      #
      # The plain password never lands on the model: assigning `password`
      # stages it, and a before-save callback hashes it into the digest
      # column. Validation reports length and confirmation problems as
      # ordinary record errors, so controllers render them like any other.
      macro password_auth(attribute = :password_digest, min_length = 8)
        {% attr_name = attribute.id.stringify %}
        {% found_type = nil %}
        {% for _table, cols in Altair::Record::Schema::META %}
          {% for col_name, col in cols %}
            {% if col_name.id.stringify == attr_name %}
              {% found_type = col[:type] %}
            {% end %}
          {% end %}
        {% end %}
        {% unless found_type %}
          {% raise "password_auth: no `#{attr_name.id}` column found in db/schema.cr — add it to the migration and re-run db:migrate" %}
        {% end %}
        {% unless found_type == :string %}
          {% raise "password_auth: `#{attr_name.id}` must be a :string column, got :#{found_type.id}" %}
        {% end %}

        @__altair_pending_password : String?
        @__altair_password_confirmation : String?
        @__altair_confirmation_given : Bool = false

        # The staged plain password, cleared once hashed. Never persisted.
        def password : String?
          @__altair_pending_password
        end

        # Stages the plain password; hashing happens in before_save.
        def password=(value : String?) : Nil
          @__altair_pending_password = value
        end

        # The confirmation value staged alongside `password=`.
        def password_confirmation : String?
          @__altair_password_confirmation
        end

        # Stages the confirmation checked against `password`.
        def password_confirmation=(value : String?) : Nil
          @__altair_password_confirmation = value
          @__altair_confirmation_given = true
        end

        # Whether `candidate` matches the stored digest. An empty candidate
        # or a missing digest is simply not authenticated — malformed stored
        # digests behave like a wrong password, never a crash.
        def authenticate_password(candidate : String) : Bool
          return false if candidate.empty?
          stored = {{ attribute.id }}
          return false unless stored
          Altair::Auth::PasswordHasher.verify(candidate, stored.not_nil!)
        end

        # Whether the stored digest was hashed at an older iteration count,
        # so a successful login may rehash (`self.password = ...; save`).
        def password_digest_stale? : Bool
          stored = {{ attribute.id }}
          stored ? Altair::Auth::PasswordHasher.stale?(stored.not_nil!) : false
        end

        # Internal validation hook; public because callback and validation
        # procs cannot dispatch to private methods.
        def __validate_altair_password : Nil
          pending = @__altair_pending_password
          if pending
            if pending.size < {{ min_length }}
              errors.add(:password, "is too short (minimum is {{ min_length }} characters)")
            end
            if @__altair_confirmation_given && pending != @__altair_password_confirmation
              errors.add(:password_confirmation, "doesn't match password")
            end
          elsif @id.nil? && {{ attribute.id }}.nil?
            errors.add(:password, "can't be blank")
          end
        end

        # Internal hashing hook; public for the same proc-dispatch reason.
        def __hash_altair_password : Nil
          if pending = @__altair_pending_password
            self.{{ attribute.id }} = Altair::Auth::PasswordHasher.hash(pending)
            @__altair_pending_password = nil
          end
        end

        validate :__validate_altair_password
        before_save :__hash_altair_password
      end
    end
  end
end
