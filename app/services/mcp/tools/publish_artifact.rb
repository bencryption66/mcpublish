module Mcp
  module Tools
    class PublishArtifact
      MAX_BYTES = 5.megabytes
      MAX_SLUG_ATTEMPTS = 3

      def initialize(api_key:, arguments:)
        @api_key = api_key
        @html = arguments["html"]
      end

      def call
        raise ToolDispatcher::ToolError, "Missing required argument: html" if @html.blank?
        if @html.bytesize > MAX_BYTES
          raise ToolDispatcher::ToolError, "Artifact exceeds maximum size of #{MAX_BYTES} bytes"
        end

        artifact = create_artifact_with_retry

        begin
          ArtifactStorage.put(storage_key: artifact.storage_key, content: @html)
        rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => e
          artifact.destroy!
          raise ToolDispatcher::ToolError, "Storage error, please retry: #{e.message}"
        end

        { content: [ { type: "text", text: artifact.url } ], slug: artifact.slug, url: artifact.url }
      end

      private

      # SlugGenerator checks Artifact.exists? before the caller inserts, so two
      # concurrent publishes can both pass that check for the same slug before
      # either commits — the DB's unique index then rejects the loser. Retry
      # with a freshly-generated slug rather than surfacing a raw DB error.
      def create_artifact_with_retry
        attempts = 0
        begin
          attempts += 1
          artifact = Artifact.new(
            api_key: @api_key,
            storage_key: "artifacts/#{SecureRandom.uuid}",
            byte_size: @html.bytesize
          )
          artifact.save!
          artifact
        rescue ActiveRecord::RecordNotUnique
          raise if attempts >= MAX_SLUG_ATTEMPTS
          retry
        rescue ActiveRecord::RecordInvalid => e
          raise unless e.record.errors.of_kind?(:slug, :taken)
          raise if attempts >= MAX_SLUG_ATTEMPTS
          retry
        end
      end
    end
  end
end
