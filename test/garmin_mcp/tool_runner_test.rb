# frozen_string_literal: true

require_relative "../test_helper"
require "mcp"

class ToolRunnerTest < Minitest::Test
  FailingClient = Data.define(:error) do
    def get(*, **) = raise(error)
  end

  def run_tool(error)
    @log = StringIO.new
    runner = GarminMcp::ToolRunner.new(client: FailingClient.new(error), logger: GarminMcp::Logger.new(io: @log), max_response_bytes: 1000)
    runner.call(tool("get_daily_sleep"), { date: "2026-10-24" })
  end

  def test_transport_errors_are_tool_errors
    response = run_tool(GarminMcp::Garmin::TransportError.new("Could not reach Garmin at example.test (Errno::EHOSTUNREACH)."))

    assert_predicate response, :error?
    assert_match(/Could not reach Garmin/, response.content.dig(0, :text))
    assert_match(/tool_call tool=get_daily_sleep duration_ms=\d+ error=TransportError/, @log.string)
  end

  def test_unexpected_errors_are_tool_errors_without_their_message
    response = run_tool(NoMethodError.new("undefined method for {\"sleepTimeSeconds\" => 27000}"))

    assert_predicate response, :error?
    assert_match(/failed unexpectedly .*\(NoMethodError\)/, response.content.dig(0, :text))
    assert_match(/tool_call tool=get_daily_sleep .* error=NoMethodError/, @log.string)
    assert_match(/ERROR tool_exception tool=get_daily_sleep error=NoMethodError/, @log.string)
    refute_includes @log.string + response.content.dig(0, :text), "sleepTimeSeconds"
  end

  def test_cancellation_reaches_the_sdk
    assert_raises(MCP::CancelledError) { run_tool(MCP::CancelledError.new) }
  end
end
