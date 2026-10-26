# frozen_string_literal: true

require "json"
require "time"

module GarminMcp
  # Minimal structured logger writing to stderr (stdout belongs to the stdio transport).
  # Callers pass fields, never secrets: the API key, Garmin tokens and MCP tokens are never logged.
  class Logger
    LEVELS = { "debug" => 0, "info" => 1, "warn" => 2, "error" => 3 }.freeze

    def initialize(io: $stderr, level: "info", format: "text")
      @io = io
      @level = LEVELS.fetch(level)
      @format = format
      @mutex = Mutex.new
    end

    LEVELS.each_key do |name|
      define_method(name) { |message, **fields| log(name, message, fields) }
    end

    private

    def log(level, message, fields)
      return if LEVELS.fetch(level) < @level

      line = @format == "json" ? json_line(level, message, fields) : text_line(level, message, fields)
      @mutex.synchronize { @io.puts(line) }
    end

    def json_line(level, message, fields)
      JSON.generate({ time: Time.now.utc.iso8601(3), level:, msg: message, **fields })
    end

    def text_line(level, message, fields)
      pairs = fields.map { |key, value| "#{key}=#{value.is_a?(String) && value.match?(/\s|"/) ? value.inspect : value}" }
      [Time.now.utc.iso8601(3), level.upcase.ljust(5), message, *pairs].join(" ")
    end
  end
end
