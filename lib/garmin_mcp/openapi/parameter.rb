# frozen_string_literal: true

module GarminMcp
  module OpenAPI
    Parameter = Data.define(:name, :location, :required, :description, :schema)
  end
end
