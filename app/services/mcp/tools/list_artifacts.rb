module Mcp
  module Tools
    class ListArtifacts
      def initialize(api_key:, arguments:)
        @api_key = api_key
      end

      def call
        artifacts = @api_key.artifacts.order(created_at: :desc).map do |artifact|
          {
            slug: artifact.slug,
            url: artifact.url,
            byte_size: artifact.byte_size,
            created_at: artifact.created_at.iso8601,
            updated_at: artifact.updated_at.iso8601
          }
        end

        { content: [ { type: "text", text: "#{artifacts.size} artifact(s)" } ], artifacts: artifacts }
      end
    end
  end
end
