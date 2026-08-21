module Mcp
  module Tools
    module SharedWithApplier
      module_function

      # Replaces the artifact's full ArtifactShare set with one row per
      # email — this is how a share is revoked: resend the list without
      # that person.
      def apply(artifact:, emails:)
        ActiveRecord::Base.transaction do
          artifact.artifact_shares.destroy_all

          emails.each do |raw_email|
            email = raw_email.to_s.strip.downcase
            unless email.match?(URI::MailTo::EMAIL_REGEXP)
              raise ToolDispatcher::ToolError, "Invalid email in shared_with: #{raw_email}"
            end

            share = artifact.artifact_shares.find_or_initialize_by(email: email)
            share.user = User.find_by(email: email)
            share.save!
          end
        end
      end
    end
  end
end
