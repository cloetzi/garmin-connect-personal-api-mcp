# frozen_string_literal: true

require_relative "spec"

module GarminMcp
  module OpenAPI
    # Human-readable summary of what changed between two versions of the spec, focused on what
    # affects tools: operations, their descriptions and parameters, and response schemas.
    class Diff
      def initialize(old_document, new_document)
        @old = Spec.new(old_document)
        @new = Spec.new(new_document)
      end

      def empty? = lines.empty?

      def to_s = empty? ? "No changes." : lines.join("\n")

      def lines
        @lines ||= [*operation_lines, *schema_lines]
      end

      private

      def operation_lines
        keyed_diff(@old.operations.to_h { |op| [op.key, op] }, @new.operations.to_h { |op| [op.key, op] }) do |sign, key, old_op, new_op|
          case sign
          when "+" then ["+ operation #{key}: #{new_op.description || new_op.summary}"]
          when "-" then ["- operation #{key}"]
          else
            changes = operation_changes(old_op, new_op)
            changes.empty? ? [] : ["~ operation #{key}", *changes.map { |change| "    #{change}" }]
          end
        end
      end

      def operation_changes(old_op, new_op)
        changes = field_changes(old_op, new_op, %i[summary description tags response_types], "")
        params = [old_op, new_op].map { |op| op.parameters.to_h { |param| [param.name, param] } }
        changes += keyed_diff(*params) do |sign, name, old_param, new_param|
          case sign
          when "+" then ["+ parameter #{describe(new_param)}"]
          when "-" then ["- parameter #{name}"]
          else field_changes(old_param, new_param, %i[location required schema description], "~ parameter #{name} ")
          end
        end
        changes << "responses changed" if responses(@old, old_op) != responses(@new, new_op)
        changes
      end

      def schema_lines
        old_schemas = @old.document.dig("components", "schemas") || {}
        new_schemas = @new.document.dig("components", "schemas") || {}
        keyed_diff(old_schemas, new_schemas) do |sign, name, old_schema, new_schema|
          next ["#{sign} schema #{name}"] unless sign == "~"

          old_schema == new_schema ? [] : ["~ schema #{name}: #{schema_change(old_schema, new_schema)}"]
        end
      end

      # Yields "+", "-" or "~" with the key and both values, and concatenates the returned lines.
      def keyed_diff(old_items, new_items)
        added = (new_items.keys - old_items.keys).flat_map { |key| yield("+", key, nil, new_items[key]) }
        removed = (old_items.keys - new_items.keys).flat_map { |key| yield("-", key, old_items[key], nil) }
        kept = (old_items.keys & new_items.keys).flat_map { |key| yield("~", key, old_items[key], new_items[key]) }
        added + removed + kept
      end

      def field_changes(old_item, new_item, fields, prefix)
        fields.filter_map do |field|
          before = old_item.public_send(field)
          after = new_item.public_send(field)
          "#{prefix}#{field}: #{before.inspect} -> #{after.inspect}" unless before == after
        end
      end

      def responses(spec, operation) = spec.document.dig("paths", operation.path, operation.http_method, "responses")

      def schema_change(old_schema, new_schema)
        old_props = (old_schema["properties"] || {}).keys
        new_props = (new_schema["properties"] || {}).keys
        parts = []
        parts << "added #{(new_props - old_props).join(", ")}" if (new_props - old_props).any?
        parts << "removed #{(old_props - new_props).join(", ")}" if (old_props - new_props).any?
        parts << "property details changed" if parts.empty?
        parts.join("; ")
      end

      def describe(param) = "#{param.name} (#{param.location}, #{param.schema["type"]}#{", required" if param.required}): #{param.description}"
    end
  end
end
