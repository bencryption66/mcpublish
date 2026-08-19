module Mcp
  class ToolDispatcher
    class ToolError < StandardError; end

    def self.call(tool_name:, arguments:, api_key:)
      tool_class = tool_classes[tool_name]
      raise ToolError, "Unknown tool: #{tool_name}" unless tool_class

      tool_class.new(api_key: api_key, arguments: arguments).call
    end

    def self.tool_classes
      {
        "publish_artifact" => Mcp::Tools::PublishArtifact,
        "update_artifact" => Mcp::Tools::UpdateArtifact,
        "list_artifacts" => Mcp::Tools::ListArtifacts,
        "delete_artifact" => Mcp::Tools::DeleteArtifact
      }
    end
  end
end
