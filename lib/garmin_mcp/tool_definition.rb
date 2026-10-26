# frozen_string_literal: true

require "date"
require "erb"
require "uri"

module GarminMcp
  # One MCP tool derived from one OpenAPI operation plus its overrides. Knows how to turn validated
  # tool arguments into a Garmin request; knows nothing about HTTP or MCP.
  class ToolDefinition
    class InvalidArguments < GarminMcp::Error; end

    Param = Data.define(:name, :location, :required, :description, :schema, :default, :send_default, :hidden)
    Request = Data.define(:path, :query) do
      def to_s = query.empty? ? path : "#{path}?#{query}"
    end

    # Inclusive range between two date parameters, named by start and end; max_days is nil when Garmin states no limit.
    DateRange = Data.define(:start, :end, :max_days)

    DATE_PATTERN = "^\\d{4}-\\d{2}-\\d{2}$"
    SCHEMA_KEYS = %w[type format enum items minimum maximum].freeze

    attr_reader :name, :title, :description, :operation, :params, :date_range

    def initialize(name:, title:, description:, operation:, params:, enabled:, date_range: nil)
      @name = name
      @title = title
      @description = description
      @operation = operation
      @params = params.freeze
      @enabled = enabled
      @date_range = date_range
      freeze
    end

    def enabled? = @enabled

    # The OpenAPI tag, e.g. "sleep-service"; usable as a group name in tool filters.
    def service = operation.tags.first

    def binary? = operation.response_types.any? && operation.response_types.none? { |type| type.include?("json") }

    def input_schema
      visible = params.reject(&:hidden)
      {
        type: "object",
        properties: visible.to_h { |param| [param.name, property_schema(param)] },
        required: visible.select(&:required).map(&:name),
        additionalProperties: false
      }
    end

    def build_request(arguments)
      values = argument_values(arguments)
      check_date_range!(parse_dates(values))

      path = operation.path.gsub(/\{([^}]+)\}/) do
        name = Regexp.last_match(1)
        ERB::Util.url_encode(values.fetch(name) { raise InvalidArguments, "#{name} is required" }.to_s)
      end
      query = params.select { |param| param.location == "query" && values.key?(param.name) }.map { |param| [param.name, values[param.name]] }
      Request.new(path:, query: URI.encode_www_form(query))
    end

    private

    # Argument values by parameter name, with override defaults filled in and hidden parameters forced to them.
    def argument_values(arguments)
      params.each_with_object({}) do |param, result|
        value = param.hidden ? nil : arguments[param.name.to_sym]
        value = param.default if value.nil? && param.send_default
        result[param.name] = value unless value.nil?
      end
    end

    def property_schema(param)
      schema = param.schema.slice(*SCHEMA_KEYS)
      schema["pattern"] = DATE_PATTERN if schema["format"] == "date"
      schema["description"] = param.description if param.description
      schema["default"] = param.default unless param.default.nil?
      schema
    end

    def parse_dates(values)
      params.select { |param| param.schema["format"] == "date" && values.key?(param.name) }.to_h do |param|
        [param.name, Date.strptime(values[param.name].to_s, "%Y-%m-%d")]
      rescue Date::Error
        raise InvalidArguments, "#{param.name} must be a valid calendar date in YYYY-MM-DD format"
      end
    end

    def check_date_range!(dates)
      first, last = date_range && dates.values_at(date_range.start, date_range.end)
      return unless first && last

      raise InvalidArguments, "#{date_range.start} must not be after #{date_range.end}" if first > last

      max_days = date_range.max_days
      return unless max_days && (last - first).to_i + 1 > max_days

      raise InvalidArguments, "the date range may span at most #{max_days} days; split the request into smaller ranges"
    end
  end
end
