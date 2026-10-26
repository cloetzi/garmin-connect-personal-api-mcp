# frozen_string_literal: true

require_relative "../test_helper"

class DiffTest < Minitest::Test
  def document = @document ||= JSON.parse(File.read(GarminMcp::Application::SPEC_PATH))

  def changed
    copy = JSON.parse(JSON.generate(document))
    yield copy
    GarminMcp::OpenAPI::Diff.new(document, copy)
  end

  def test_identical_specs
    diff = GarminMcp::OpenAPI::Diff.new(document, document)

    assert_empty diff
    assert_equal "No changes.", diff.to_s
  end

  def test_reports_operation_and_parameter_changes
    diff = changed do |copy|
      copy["paths"]["/new-service/thing"] = { "get" => { "description" => "New thing." } }
      copy["paths"].delete("/biometric-service/heartRateZones/v2")
      sleep = copy["paths"]["/sleep-service/sleep/dailySleep"]["get"]
      sleep["parameters"].first["required"] = true
      sleep["parameters"] << { "name" => "detail", "in" => "query", "schema" => { "type" => "boolean" } }
    end

    assert_includes diff.lines, "+ operation GET /new-service/thing: New thing."
    assert_includes diff.lines, "- operation GET /biometric-service/heartRateZones/v2"
    assert_includes diff.lines, "~ operation GET /sleep-service/sleep/dailySleep"
    assert_includes diff.lines, "    ~ parameter date required: false -> true"
    assert_includes diff.lines, "    + parameter detail (query, boolean): "
  end

  def test_reports_schema_changes
    diff = changed { |copy| copy["components"]["schemas"]["DailySleepDTO"]["properties"]["dreamCount"] = { "type" => "integer" } }

    assert_includes diff.lines, "~ schema DailySleepDTO: added dreamCount"
  end
end
