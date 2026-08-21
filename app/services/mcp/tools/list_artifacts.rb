module Mcp
  module Tools
    class ListArtifacts
      def initialize(user:, arguments:)
        @user = user
      end

      def call
        artifacts = @user.artifacts.order(created_at: :desc).map do |artifact|
          {
            slug: artifact.slug,
            url: artifact.url,
            byte_size: artifact.byte_size,
            visibility: artifact.visibility,
            organization: artifact.organization&.slug,
            shared_with: artifact.artifact_shares.pluck(:email),
            created_at: artifact.created_at.iso8601,
            updated_at: artifact.updated_at.iso8601
          }
        end

        { content: [ { type: "text", text: "#{artifacts.size} artifact(s)" } ], artifacts: artifacts }
      end
    end
  end
end
