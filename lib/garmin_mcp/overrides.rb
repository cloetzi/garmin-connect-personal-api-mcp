# frozen_string_literal: true

require "json_schemer"
require "yaml"

module GarminMcp
  # Curated refinements of the OpenAPI spec (tool names, better descriptions, required flags, range limits).
  # A user-supplied file is merged on top of the bundled one. Both are validated strictly: unknown keys
  # and entries that no longer match the spec are errors, so drift is caught instead of silently ignored.
  class Overrides
    class Error < GarminMcp::Error; end

    SCHEMA = {
      "type" => "object",
      "additionalProperties" => false,
      "properties" => {
        "instructions" => { "type" => "string" },
        "operations" => {
          "type" => "object",
          "propertyNames" => { "pattern" => "\\A(GET|PUT|POST|PATCH|DELETE) /" },
          "additionalProperties" => {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => {
              "name" => { "type" => "string", "pattern" => "\\A[a-z][a-z0-9_]{0,63}\\z" },
              "title" => { "type" => "string" },
              "description" => { "type" => "string" },
              "description_append" => { "type" => "string" },
              "enabled" => { "type" => "boolean" },
              "parameters" => {
                "type" => "object",
                "additionalProperties" => {
                  "type" => "object",
                  "additionalProperties" => false,
                  "properties" => {
                    "description" => { "type" => "string" },
                    "required" => { "type" => "boolean" },
                    "default" => {},
                    "hidden" => { "type" => "boolean" }
                  }
                }
              },
              "date_range" => {
                "type" => "object",
                "additionalProperties" => false,
                "required" => %w[start end],
                "properties" => {
                  "start" => { "type" => "string" },
                  "end" => { "type" => "string" },
                  "max_days" => { "type" => "integer", "minimum" => 1 }
                }
              }
            }
          }
        }
      }
    }.freeze

    BUNDLED_PATH = File.expand_path("../../data/overrides.yml", __dir__)

    attr_reader :instructions, :operations

    def self.load(spec, paths)
      documents = paths.map { |path| [path, parse(path)] }
      new(spec, documents)
    end

    def self.parse(path)
      YAML.safe_load_file(path, permitted_classes: [], aliases: false) || {}
    rescue Psych::Exception, SystemCallError => e
      raise Error, "cannot read overrides #{path}: #{e.message}"
    end

    def initialize(spec, documents)
      @instructions = nil
      @operations = {}
      documents.each do |source, document|
        validate!(spec, source, document)
        @instructions = document["instructions"] if document.key?("instructions")
        document.fetch("operations", {}).each { |key, entry| merge_operation(key, entry) }
      end
      @operations.freeze
    end

    def for(operation) = operations.fetch(operation.key, {})

    private

    def merge_operation(key, entry)
      merged = operations.fetch(key, {}).merge(entry.except("parameters"))
      parameters = operations.dig(key, "parameters").to_h.merge(entry.fetch("parameters", {})) do |_name, old, new|
        old.merge(new)
      end
      merged["parameters"] = parameters unless parameters.empty?
      operations[key] = merged
    end

    def validate!(spec, source, document)
      errors = JSONSchemer.schema(SCHEMA).validate(document).map { |error| error["error"] }
      raise Error, "invalid overrides #{source}:\n  #{errors.join("\n  ")}" if errors.any?

      document.fetch("operations", {}).each do |key, entry|
        operation = spec.operation(key) or raise Error, "#{source}: #{key} is not an operation in the OpenAPI spec"
        names = entry.fetch("parameters", {}).keys + entry.fetch("date_range", {}).values_at("start", "end").compact
        names.each do |name|
          raise Error, "#{source}: #{key} has no parameter #{name}" unless operation.parameter(name)
        end
      end
    end
  end
end
