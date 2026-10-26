# frozen_string_literal: true

require_relative "../test_helper"
require "rack/mock"

# Exercises the full stack below Falcon: Rack app, SDK transport, tools, Garmin client.
class HttpAppTest < Minitest::Test
  def app(fake, logger: null_logger, **values)
    @application = GarminMcp::Application.new(GarminMcp::Config.from_env(env(fake, **values)), logger:)
    Rack::MockRequest.new(@application.rack_app)
  end

  def teardown = @application&.close

  def rpc(app, method, params = nil, token: TestHelpers::AUTH_TOKEN, host: "localhost:8080", **headers)
    body = JSON.generate({ jsonrpc: "2.0", id: 1, method:, params: }.compact)
    headers = { "CONTENT_TYPE" => "application/json", "HTTP_ACCEPT" => "application/json, text/event-stream",
                "HTTP_MCP_PROTOCOL_VERSION" => "2025-11-25", "HTTP_HOST" => host, **headers.transform_keys(&:to_s) }.compact
    headers["HTTP_AUTHORIZATION"] = "Bearer #{token}" if token
    app.post("/mcp", input: body, **headers)
  end

  def result(response) = JSON.parse(response.body).fetch("result")

  def test_healthz_is_public
    with_fake_garmin do |fake|
      response = app(fake).get("/healthz")

      assert_equal 200, response.status
      assert_equal "ok", JSON.parse(response.body)["status"]
    end
  end

  def test_requires_bearer_token
    with_fake_garmin do |fake|
      app = app(fake)

      assert_equal 401, rpc(app, "tools/list", token: nil).status
      assert_equal 401, rpc(app, "tools/list", token: "x" * 40).status
      assert_match(/\ABearer/, rpc(app, "tools/list", token: nil).headers["www-authenticate"])
      assert_equal 200, rpc(app, "tools/list").status
    end
  end

  def test_auth_can_be_disabled
    with_fake_garmin do |fake|
      app = app(fake, GARMIN_MCP_AUTH_TOKEN: nil, GARMIN_MCP_AUTH_DISABLED: "true")

      assert_equal 200, rpc(app, "tools/list", token: nil).status
    end
  end

  def test_rejects_unknown_hosts_and_origins
    with_fake_garmin do |fake|
      app = app(fake, GARMIN_MCP_ALLOWED_HOSTS: "mcp.lan")

      assert_equal 403, rpc(app, "tools/list", host: "evil.example").status
      assert_equal 200, rpc(app, "tools/list", host: "mcp.lan:8080").status
      assert_equal 200, rpc(app, "tools/list", host: "[::1]:8080").status
      assert_equal 403, rpc(app, "tools/list", HTTP_ORIGIN: "https://evil.example").status
      assert_equal 200, rpc(app, "tools/list", HTTP_ORIGIN: "http://localhost:8080").status
      assert_equal 200, rpc(app, "tools/list", host: nil).status
    end
  end

  def test_wildcard_hosts_still_reject_foreign_origins
    with_fake_garmin do |fake|
      app = app(fake, GARMIN_MCP_ALLOWED_HOSTS: "*", GARMIN_MCP_ALLOWED_ORIGINS: "https://app.example",
                      GARMIN_MCP_AUTH_TOKEN: nil, GARMIN_MCP_AUTH_DISABLED: "true")

      assert_equal 200, rpc(app, "tools/list", token: nil, host: "mcp.example").status
      assert_equal 403, rpc(app, "tools/list", token: nil, host: "mcp.example", HTTP_ORIGIN: "https://evil.example").status
      assert_equal 200, rpc(app, "tools/list", token: nil, host: "mcp.example", HTTP_ORIGIN: "https://app.example").status
    end
  end

  def test_rejections_are_logged_with_a_hint
    with_fake_garmin do |fake|
      io = StringIO.new
      app = app(fake, logger: GarminMcp::Logger.new(io:, level: "warn"))

      assert_equal "host not allowed", JSON.parse(rpc(app, "tools/list", host: "evil.example").body)["error"]
      assert_equal "origin not allowed", JSON.parse(rpc(app, "tools/list", HTTP_ORIGIN: "https://evil.example").body)["error"]
      assert_match(/host_rejected host=evil.example hint="add the host to GARMIN_MCP_ALLOWED_HOSTS"/, io.string)
      assert_match(%r{origin_rejected origin=https://evil.example hint="add the origin to GARMIN_MCP_ALLOWED_ORIGINS"}, io.string)
      refute_includes io.string, TestHelpers::AUTH_TOKEN
    end
  end

  def test_health_checks_are_logged_only_at_debug
    with_fake_garmin do |fake|
      io = StringIO.new
      app = app(fake, logger: GarminMcp::Logger.new(io:, level: "info"))
      app.get("/healthz")
      app.get("/missing")

      refute_includes io.string, "path=/healthz"
      assert_includes io.string, "path=/missing"
    end
  end

  def test_initialize_advertises_tools_and_instructions
    with_fake_garmin do |fake|
      init = result(rpc(app(fake), "initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "test", version: "1" } }))

      assert_equal({ "tools" => {} }, init["capabilities"])
      assert_match(/Read-only access/, init["instructions"])
    end
  end

  def test_tools_list_honors_filters
    with_fake_garmin do |fake|
      tools = result(rpc(app(fake, GARMIN_MCP_TOOLS: "sleep-service"), "tools/list"))["tools"]

      assert_equal %w[get_daily_sleep get_daily_sleep_summaries], tools.map { |tool| tool["name"] }.sort
      assert(tools.all? { |tool| tool.dig("annotations", "readOnlyHint") })
    end
  end

  def test_tool_call_returns_compact_json
    with_fake_garmin do |fake|
      fake.json("/sleep-service/sleep/dailySleep", { "sleepTimeSeconds" => 27_000, "napTimeSeconds" => nil, "scores" => [{ "a" => nil }] })
      response = result(rpc(app(fake), "tools/call", { name: "get_daily_sleep", arguments: { date: "2026-10-24" } }))

      refute response["isError"]
      assert_equal '{"sleepTimeSeconds":27000,"scores":[{}]}', response.dig("content", 0, "text")
      assert_equal ["/sleep-service/sleep/dailySleep?date=2026-10-24"], fake.requests_to("/sleep-service/sleep/dailySleep").map(&:path)
    end
  end

  def test_tool_errors_are_reported_to_the_model
    with_fake_garmin do |fake|
      fake.route("GET", "/sleep-service/sleep/dailySleep") { [500, {}, "boom"] }
      app = app(fake)

      missing = result(rpc(app, "tools/call", { name: "get_daily_sleep", arguments: {} }))

      assert missing["isError"]
      assert_match(/date/, missing.dig("content", 0, "text"))

      unknown_argument = result(rpc(app, "tools/call", { name: "get_daily_sleep", arguments: { date: "2026-10-24", extra: 1 } }))

      assert unknown_argument["isError"]

      upstream = result(rpc(app, "tools/call", { name: "get_daily_sleep", arguments: { date: "2026-10-24" } }))

      assert upstream["isError"]
      assert_match(/HTTP 500/, upstream.dig("content", 0, "text"))
    end
  end

  def test_large_responses_are_truncated
    with_fake_garmin do |fake|
      fake.json("/userprofile-service/userprofile/settings", { "blob" => "x" * 5_000 })
      text = result(rpc(app(fake, GARMIN_MCP_MAX_RESPONSE_BYTES: "1000"), "tools/call", { name: "get_user_profile_settings", arguments: {} }))
             .dig("content", 0, "text")

      assert_operator text.bytesize, :<, 1_300
      assert_match(/\[Truncated: the response is \d+ bytes and the limit is 1000/, text)
    end
  end

  def test_empty_responses
    with_fake_garmin do |fake|
      fake.route("GET", "/hrv-service/hrv/2026-10-24") { [204, {}, ""] }
      text = result(rpc(app(fake), "tools/call", { name: "get_daily_hrv", arguments: { calendarDate: "2026-10-24" } })).dig("content", 0, "text")

      assert_match(/no data/, text)
    end
  end

  def test_binary_download_when_enabled
    with_fake_garmin do |fake|
      fake.route("GET", "/download-service/files/activity/42") { [200, { "content-type" => "application/x-zip-compressed" }, "PK\x03\x04"] }
      app = app(fake, GARMIN_MCP_TOOLS: "download_activity")
      content = result(rpc(app, "tools/call", { name: "download_activity", arguments: { activityId: 42 } })).dig("content", 0)

      assert_equal "resource", content["type"]
      assert_equal "PK\x03\x04", content.dig("resource", "blob").unpack1("m")
    end
  end

  def test_binary_download_must_fit_the_response_limit
    with_fake_garmin do |fake|
      { 1 => 750, 2 => 751 }.each do |id, size|
        zip = "PK".ljust(size, "a")
        fake.route("GET", "/download-service/files/activity/#{id}") { [200, { "content-type" => "application/x-zip-compressed" }, zip] }
      end
      app = app(fake, GARMIN_MCP_TOOLS: "download_activity", GARMIN_MCP_MAX_RESPONSE_BYTES: "1000")

      fits = result(rpc(app, "tools/call", { name: "download_activity", arguments: { activityId: 1 } }))

      assert_operator fits.dig("content", 0, "resource", "blob").bytesize, :<=, 1000

      too_large = result(rpc(app, "tools/call", { name: "download_activity", arguments: { activityId: 2 } }))

      assert too_large["isError"]
      assert_match(/larger than 750 bytes.*GARMIN_MCP_MAX_RESPONSE_BYTES/, too_large.dig("content", 0, "text"))
      refute_includes too_large.dig("content", 0, "text"), "PK"
    end
  end

  def test_oversized_json_responses_ask_to_narrow_the_request
    with_fake_garmin do |fake|
      fake.json("/userprofile-service/userprofile/settings", { "blob" => "x" * 5_000 })
      app = app(fake, GARMIN_MCP_MAX_DOWNLOAD_BYTES: "1024")
      outcome = result(rpc(app, "tools/call", { name: "get_user_profile_settings", arguments: {} }))

      assert outcome["isError"]
      assert_match(/larger than 1024 bytes.*shorter date range/, outcome.dig("content", 0, "text"))
    end
  end
end
