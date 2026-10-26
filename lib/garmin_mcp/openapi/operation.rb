# frozen_string_literal: true

module GarminMcp
  module OpenAPI
    Operation = Data.define(:http_method, :path, :tags, :summary, :description, :parameters, :response_types) do
      # Stable identity used by overrides; Garmin's spec has no operationIds.
      def key = "#{http_method.upcase} #{path}"

      def parameter(name) = parameters.find { |param| param.name == name }
    end
  end
end
