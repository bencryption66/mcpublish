module Mcp
  module ToolDefinitions
    VISIBILITY_PROPERTIES = {
      visibility: {
        type: "string",
        enum: %w[private organisation shared public],
        description: "Who can view this artifact. Defaults to private."
      },
      organization: {
        type: "string",
        description: "Organization slug — required when visibility is organisation. Must be an organization you belong to."
      },
      shared_with: {
        type: "array",
        items: { type: "string" },
        description: "Email addresses to share with — used when visibility is shared. Replaces the full share list."
      }
    }.freeze

    ALL = [
      {
        name: "publish_artifact",
        description: "Publish a new self-contained HTML artifact and get back a public URL.",
        inputSchema: {
          type: "object",
          properties: {
            html: { type: "string", description: "Self-contained HTML content to publish." }
          }.merge(VISIBILITY_PROPERTIES),
          required: [ "html" ]
        }
      },
      {
        name: "update_artifact",
        description: "Update a previously published artifact's content and/or visibility, keeping its URL.",
        inputSchema: {
          type: "object",
          properties: {
            slug: { type: "string", description: "The slug of the artifact to update." },
            html: { type: "string", description: "New HTML content. Omit to change only visibility." }
          }.merge(VISIBILITY_PROPERTIES),
          required: [ "slug" ]
        }
      },
      {
        name: "list_artifacts",
        description: "List all artifacts published with this API key.",
        inputSchema: { type: "object", properties: {} }
      },
      {
        name: "delete_artifact",
        description: "Delete a previously published artifact.",
        inputSchema: {
          type: "object",
          properties: {
            slug: { type: "string", description: "The slug of the artifact to delete." }
          },
          required: [ "slug" ]
        }
      }
    ].freeze
  end
end
