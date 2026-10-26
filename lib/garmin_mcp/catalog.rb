# frozen_string_literal: true

module GarminMcp
  # Builds the tool definitions from the spec and its overrides, and applies the operator's tool filters.
  class Catalog
    class Error < GarminMcp::Error; end

    # Date parameter names that pair into a range when the rest of the name matches,
    # e.g. startDate/endDate, fromDate/toDate, fromDate/untilDate.
    RANGE_START = /\A(?:start|from)(?<rest>.*)\z/
    RANGE_END = /\A(?:end|to|until)(?<rest>.*)\z/

    attr_reader :spec, :overrides, :tools

    def initialize(spec, overrides)
      @spec = spec
      @overrides = overrides
      @tools = spec.operations.map { |operation| build(operation) }.freeze
      duplicates = tools.group_by(&:name).select { |_name, group| group.size > 1 }.keys
      raise Error, "duplicate tool names: #{duplicates.join(", ")}" if duplicates.any?
    end

    def instructions = overrides.instructions

    # include: explicit tool or service names (overrides `enabled: false`); nil means all enabled tools.
    # exclude: tool or service names removed afterwards.
    def select(include: nil, exclude: [])
      unknown = (Array(include) + exclude).reject { |name| tools.any? { |tool| matches?(tool, [name]) } }
      raise Error, "unknown tool or service names: #{unknown.join(", ")}" if unknown.any?

      selected = include ? tools.select { |tool| matches?(tool, include) } : tools.select(&:enabled?)
      selected.reject { |tool| matches?(tool, exclude) }
    end

    # Reviewable description of every tool; `bin/garmin-mcp tools` prints it and test/fixtures/tools.json snapshots it.
    def manifest
      tools.map do |tool|
        {
          name: tool.name, title: tool.title, enabled: tool.enabled?, service: tool.service, operation: tool.operation.key,
          description: tool.description, inputSchema: tool.input_schema
        }
      end
    end

    # Fallback for operations without a curated name; the test suite requires curated names for all of them.
    def self.derived_name(operation)
      words = operation.path.gsub(/\{[^}]+\}/, "").scan(/[A-Za-z0-9]+/).map { |word| word.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase }
      [operation.http_method, *words].join("_")[0, 64]
    end

    # The start and end parameter names of the operation's date range, or nil unless exactly one pair matches.
    def self.inferred_range(operation)
      dates = operation.parameters.select { |param| param.schema["format"] == "date" }.map(&:name)
      pairs = dates.product(dates).select do |start, finish|
        (rest = RANGE_START.match(start)&.[](:rest)) && RANGE_END.match(finish)&.[](:rest) == rest
      end
      pairs.first if pairs.one?
    end

    private

    def matches?(tool, names) = names.include?(tool.name) || names.include?(tool.service)

    def build(operation)
      entry = overrides.for(operation)
      param_overrides = entry.fetch("parameters", {})
      date_range = date_range(operation, entry.fetch("date_range", {}))
      ToolDefinition.new(
        name: entry.fetch("name") { self.class.derived_name(operation) },
        title: entry["title"] || operation.summary,
        description: description(operation, entry, date_range),
        operation:,
        params: operation.parameters.map { |param| build_param(operation, param, param_overrides.fetch(param.name, {})) },
        enabled: entry.fetch("enabled", true),
        date_range:
      )
    end

    # Inferred from the spec unless the override names the pair; `false` opts out of range checks.
    def date_range(operation, setting)
      return if setting == false

      start, finish = setting.key?("start") ? setting.values_at("start", "end") : self.class.inferred_range(operation)
      unless start
        raise Error, "#{operation.key}: date_range needs start and end, no date parameter pair was inferred" if setting.any?

        return
      end
      [start, finish].each do |name|
        raise Error, "#{operation.key}: date_range parameter #{name} is not a date" unless operation.parameter(name).schema["format"] == "date"
      end
      ToolDefinition::DateRange.new(start:, end: finish, max_days: setting["max_days"])
    end

    def description(operation, entry, date_range)
      text = entry["description"] || operation.description || operation.summary || "Calls #{operation.key}."
      text = "#{text.strip} #{entry["description_append"].strip}" if entry["description_append"]
      text = "#{text} Maximum range: #{date_range.max_days} days, inclusive." if date_range&.max_days
      text
    end

    def build_param(operation, param, entry)
      required = param.location == "path" || entry.fetch("required", param.required)
      if entry["hidden"] && required && !entry.key?("default")
        raise Error, "#{operation.key}: hidden parameter #{param.name} is required but has no default"
      end

      ToolDefinition::Param.new(
        name: param.name,
        location: param.location,
        required:,
        description: entry["description"] || param.description,
        schema: param.schema,
        default: entry.fetch("default", param.schema["default"]),
        send_default: entry.key?("default"),
        hidden: entry.fetch("hidden", false)
      )
    end
  end
end
