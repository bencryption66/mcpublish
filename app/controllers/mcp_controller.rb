class McpController < ApplicationController
  include ApiKeyAuthentication

  PROTOCOL_VERSION = "2025-06-18".freeze

  def create
    case params[:method]
    when "initialize"
      render json: success_response(initialize_result)
    when "tools/list"
      render json: success_response(tools_list_result)
    when "tools/call"
      handle_tools_call
    else
      render json: error_response(-32601, "Method not found: #{params[:method]}")
    end
  end

  private

  def initialize_result
    {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: { tools: {} },
      serverInfo: { name: "mcpublish", version: "0.1.0" }
    }
  end

  def tools_list_result
    { tools: Mcp::ToolDefinitions::ALL }
  end

  def handle_tools_call
    render json: error_response(-32601, "tools/call not yet implemented")
  end

  def success_response(result)
    { jsonrpc: "2.0", id: params[:id], result: result }
  end

  def error_response(code, message)
    { jsonrpc: "2.0", id: params[:id], error: { code: code, message: message } }
  end
end
