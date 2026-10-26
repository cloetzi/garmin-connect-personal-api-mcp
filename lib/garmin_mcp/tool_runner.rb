# frozen_string_literal: true

require "json"
require "mcp"

module GarminMcp
  # Executes a tool call: builds the Garmin request, performs it, and shapes the result for an assistant
  # (compact JSON without nulls, capped in size). Garmin failures become tool errors the model can read,
  # never protocol errors.
  #
  # max_response_bytes bounds every result. JSON is truncated to it; a binary file cannot be cut, so it
  # is sent whole as a base64 blob (4 bytes per 3) if that fits, and otherwise its download is aborted.
  class ToolRunner
    ERROR_EXCERPT_BYTES = 300

    def initialize(client:, logger:, max_response_bytes:, strip_nulls: true)
      @client = client
      @logger = logger
      @max_response_bytes = max_response_bytes
      @max_file_bytes = max_response_bytes / 4 * 3
      @strip_nulls = strip_nulls
    end

    # Wraps a definition into an MCP::Tool class whose calls are served by this runner.
    def mcp_tool(definition)
      runner = self
      MCP::Tool.define(
        name: definition.name,
        title: definition.title,
        description: definition.description,
        input_schema: definition.input_schema,
        annotations: { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: true, title: definition.title }
      ) { |**arguments| runner.call(definition, arguments.except(:server_context)) }
    end

    def call(definition, arguments)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      request = definition.build_request(arguments)
      response = @client.get(request.to_s, **fetch_options(definition))
      log(definition, started, status: response.status)
      format(definition, request, response)
    rescue ToolDefinition::InvalidArguments => e
      error(e.message)
    rescue Garmin::Error => e
      log(definition, started, error: e.class.name.split("::").last)
      error(e.is_a?(Garmin::ResponseTooLarge) ? too_large(definition, e.limit) : e.message)
    rescue MCP::CancelledError
      raise
    rescue StandardError => e
      unexpected(definition, started, e)
    end

    private

    def fetch_options(definition)
      return { accept: "application/json" } unless definition.binary?

      { accept: definition.operation.response_types.join(", "), max_body_bytes: @max_file_bytes }
    end

    def format(definition, request, response)
      return failure(response) unless response.success?
      return text("Garmin returned no data for this request.") if response.body.empty?
      return binary(request, response) if definition.binary? && !response.json?

      data = JSON.parse(response.body)
      data = compact(data) if @strip_nulls
      text(truncate(JSON.generate(data)))
    rescue JSON::ParserError
      error("Garmin returned a response that is not valid JSON (content type #{response.content_type.inspect}).")
    end

    def failure(response)
      message = case response.status
                when 401 then "Garmin refused this request (HTTP 401) although the API key is valid and its access token is " \
                              "recent, so this data is not available to the key or account (for example, a permission or consent " \
                              "is missing in Garmin Connect). Retrying will not help; other tools may still work."
                when 403 then "Garmin denied access to this data (HTTP 403); the key or account is not permitted to read it."
                when 404 then "Garmin found no data for this request (HTTP 404)."
                when 429 then "Garmin is rate limiting requests (HTTP 429). Wait before retrying."
                when 400..499 then "Garmin rejected the request (HTTP #{response.status})."
                else "Garmin failed to answer the request (HTTP #{response.status}). Retrying later may help."
                end
      excerpt = response.body.to_s.scrub.byteslice(0, ERROR_EXCERPT_BYTES).to_s.scrub.strip
      error(excerpt.empty? ? message : "#{message} Response: #{excerpt}")
    end

    # The HTTP client refused bodies over @max_file_bytes, so the blob fits @max_response_bytes.
    def binary(request, response)
      blob = [response.body].pack("m0")
      mime_type = response.content_type.to_s.split(";").first
      MCP::Tool::Response.new([{ type: "resource", resource: { uri: "garmin:#{request.path}", mimeType: mime_type, blob: } }])
    end

    def too_large(definition, limit)
      if definition.binary?
        "The file is larger than #{limit} bytes, the most this server returns in one tool result, so it was not downloaded. " \
          "The server operator can raise the limit with GARMIN_MCP_MAX_RESPONSE_BYTES."
      else
        "Garmin's response is larger than #{limit} bytes, the most this server reads. Request a shorter date range or fewer results."
      end
    end

    def truncate(json)
      return json if json.bytesize <= @max_response_bytes

      "#{json.byteslice(0, @max_response_bytes).scrub("")}\n\n[Truncated: the response is #{json.bytesize} bytes and the limit is " \
        "#{@max_response_bytes}. Request a shorter date range or fewer results.]"
    end

    def compact(value)
      case value
      when Hash then value.each_with_object({}) { |(key, item), result| result[key] = compact(item) unless item.nil? }
      when Array then value.map { |item| compact(item) }
      else value
      end
    end

    # A bug rather than a Garmin failure. Only the class is logged: the message could quote Garmin's response.
    def unexpected(definition, started, exception)
      log(definition, started, error: exception.class.name)
      @logger.error("tool_exception", tool: definition.name, error: exception.class.name)
      error("The server failed unexpectedly while handling this request (#{exception.class.name}). " \
            "This is a bug in the MCP server, not a Garmin problem.")
    end

    def text(content) = MCP::Tool::Response.new([{ type: "text", text: content }])

    def error(message) = MCP::Tool::Response.new([{ type: "text", text: message }], error: true)

    def log(definition, started, **fields)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      @logger.info("tool_call", tool: definition.name, duration_ms:, **fields)
    end
  end
end
