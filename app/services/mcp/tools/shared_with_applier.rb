module Mcp
  module Tools
    module SharedWithApplier
      module_function

      # Format-validates every email without touching the DB — callers use
      # this to fail fast, before any other write, on a caller-supplied list.
      def validate!(emails)
        emails.each do |raw_email|
          unless valid_email?(raw_email)
            raise ToolDispatcher::ToolError, "Invalid email in shared_with: #{raw_email}"
          end
        end
      end

      # Replaces the artifact's full ArtifactShare set with one row per
      # email — this is how a share is revoked: resend the list without
      # that person. Re-validates (cheap, and keeps this method safe to call
      # on its own) before touching the DB, and the whole replacement is
      # transactional so a bad entry never leaves a partially-applied list.
      def apply(artifact:, emails:)
        validate!(emails)

        ActiveRecord::Base.transaction do
          artifact.artifact_shares.destroy_all

          emails.each do |raw_email|
            email = raw_email.to_s.strip.downcase
            share = artifact.artifact_shares.find_or_initialize_by(email: email)
            share.user = User.find_by(email: email)
            share.save!
          end
        end
      end

      def valid_email?(raw_email)
        raw_email.to_s.strip.downcase.match?(URI::MailTo::EMAIL_REGEXP)
      end
    end
  end
end
