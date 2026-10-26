# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("cli" => "CLI", "openapi" => "OpenAPI")
loader.setup

module GarminMcp
  class Error < StandardError; end
end
