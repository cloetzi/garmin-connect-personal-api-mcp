# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("cli" => "CLI", "openapi" => "OpenAPI")
loader.setup

module GarminMcp
  # Base of every error this gem raises. The CLI reports one that reaches it as a message, without a backtrace.
  class Error < StandardError; end
end
