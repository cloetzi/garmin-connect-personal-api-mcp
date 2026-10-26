# frozen_string_literal: true

require "minitest/autorun"
require "stringio"
require_relative "../lib/garmin_mcp"
require_relative "support/fake_garmin"

Warning[:experimental] = false

module TestHelpers
  ROOT = File.expand_path("..", __dir__)
  AUTH_TOKEN = "t" * 40

  def null_logger = GarminMcp::Logger.new(io: StringIO.new, level: "error")

  def spec = @spec ||= GarminMcp::OpenAPI::Spec.load(GarminMcp::Application::SPEC_PATH)

  def catalog = @catalog ||= GarminMcp::Application.catalog

  def tool(name) = catalog.tools.find { |definition| definition.name == name } || flunk("no tool #{name}")

  # Runs the block inside a reactor with a fake Garmin API, which is stopped afterwards.
  def with_fake_garmin
    Sync do |task|
      fake = FakeGarmin.new.start(task)
      yield fake
    ensure
      fake&.stop
    end
  end

  def env(fake = nil, **overrides)
    {
      "GARMIN_PERSONAL_API_KEY" => FakeGarmin::API_KEY,
      "GARMIN_PERSONAL_API_BASE_URL" => fake&.url,
      "GARMIN_MCP_AUTH_TOKEN" => AUTH_TOKEN
    }.merge(overrides.transform_keys(&:to_s)).compact
  end

  def write_tempfile(name, content)
    path = File.join(Dir.mktmpdir, name)
    File.write(path, content)
    path
  end
end

Minitest::Test.include(TestHelpers)
