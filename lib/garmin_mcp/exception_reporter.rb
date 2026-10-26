# frozen_string_literal: true

require "json"

module GarminMcp
  # The MCP SDK's exception_reporter, called for exceptions the server caught outside a tool's own handling
  # (ToolRunner rescues those): invalid requests, failing protocol handlers, notifications that could not be sent.
  #
  # Neither the exception message nor the SDK's context is logged: messages can quote request arguments or Garmin
  # responses, and the context carries the whole JSON-RPC request. Only the class, the JSON-RPC method, the tool
  # name, the SDK's notification label and the first file:line in lib/ are, each shaped like an identifier.
  class ExceptionReporter
    ROOT = File.expand_path("../..", __dir__)
    LIB = File.join(ROOT, "lib", "")
    IDENTIFIER = %r{\A[\w./-]{1,64}\z}

    def initialize(logger)
      @logger = logger
    end

    def call(exception, context)
      @logger.error("unhandled_exception", error: exception.class.name, **fields(exception, context))
    end

    private

    def fields(exception, context)
      context = {} unless context.is_a?(Hash)
      request = parse(context[:request])
      method = identifier(value(request, :method))
      tool = identifier(value(value(request, :params), :name)) if method == "tools/call"
      { method:, tool:, notification: identifier(context[:notification]), location: location(exception) }.compact
    rescue StandardError
      {} # A reporter that raises would hide the exception it reports.
    end

    # The SDK passes the request as received: a Hash (string or symbol keys) or the raw JSON text.
    def parse(request)
      request = JSON.parse(request) if request.is_a?(String)
      request if request.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    def value(hash, key) = hash.is_a?(Hash) ? hash[key] || hash[key.to_s] : nil

    def identifier(value) = value.is_a?(String) && value.match?(IDENTIFIER) ? value : nil

    # A code position set by Ruby, never data; the most useful lead once the message is dropped.
    def location(exception)
      frame = exception.backtrace_locations&.find { |location| location.absolute_path&.start_with?(LIB) }
      "#{frame.absolute_path.delete_prefix(ROOT).delete_prefix("/")}:#{frame.lineno}" if frame
    end
  end
end
