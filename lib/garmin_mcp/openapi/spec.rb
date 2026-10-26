# frozen_string_literal: true

require "json"

module GarminMcp
  module OpenAPI
    Parameter = Data.define(:name, :location, :required, :description, :schema)

    Operation = Data.define(:http_method, :path, :tags, :summary, :description, :parameters, :response_types) do
      # Stable identity used by overrides; Garmin's spec has no operationIds.
      def key = "#{http_method.upcase} #{path}"

      def parameter(name) = parameters.find { |param| param.name == name }
    end

    # Read-only view of the vendored OpenAPI document, reduced to what tool generation needs.
    class Spec
      HTTP_METHODS = %w[get put post patch delete].freeze

      attr_reader :document, :operations

      def self.load(path) = new(JSON.parse(File.read(path)))

      def initialize(document)
        @document = document
        @operations = build_operations.freeze
      end

      def server_url = document.dig("servers", 0, "url")

      def operation(key) = operations.find { |op| op.key == key }

      private

      def build_operations
        document.fetch("paths").flat_map do |path, item|
          shared = Array(item["parameters"])
          item.slice(*HTTP_METHODS).map do |method, op|
            Operation.new(
              http_method: method,
              path:,
              tags: Array(op["tags"]),
              summary: op["summary"],
              description: op["description"],
              parameters: merge_parameters(shared, Array(op["parameters"])),
              response_types: response_types(op)
            )
          end
        end
      end

      def merge_parameters(shared, own)
        (shared + own).map { |param| resolve(param) }.reverse.uniq { |param| [param["name"], param["in"]] }.reverse.map do |param|
          Parameter.new(
            name: param.fetch("name"),
            location: param.fetch("in"),
            required: param["in"] == "path" || param["required"] == true,
            description: param["description"],
            schema: resolve(param["schema"] || {})
          )
        end
      end

      def response_types(operation)
        operation.fetch("responses", {}).select { |status, _| status.start_with?("2") || status == "default" }
                 .flat_map { |_status, response| resolve(response).fetch("content", {}).keys }.uniq
      end

      def resolve(node)
        return node unless node.is_a?(Hash) && node.key?("$ref")

        ref = node["$ref"]
        raise ArgumentError, "unsupported $ref #{ref}" unless ref.start_with?("#/")

        resolve(document.dig(*ref.delete_prefix("#/").split("/")) || raise(ArgumentError, "unresolvable $ref #{ref}"))
      end
    end
  end
end
