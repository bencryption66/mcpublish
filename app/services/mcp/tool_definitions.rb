module Mcp
  module ToolDefinitions
    ALL = [
      {
        name: "publish_artifact",
        description: "Publish a new self-contained HTML artifact and get back a public URL.",
        inputSchema: {
          type: "object",
          properties: {
            html: { type: "string", description: "Self-contained HTML content to publish." }
          },
          required: ["html"]
        }
      },
      {
        name: "update_artifact",
        description: "Overwrite the content of a previously published artifact, keeping its URL.",
        inputSchema: {
          type: "object",
          properties: {
            slug: { type: "string", description: "The slug of the artifact to update." },
            html: { type: "string", description: "New HTML content." }
          },
          required: %w[slug html]
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
          required: ["slug"]
        }
      }
    ].freeze
  end
end
