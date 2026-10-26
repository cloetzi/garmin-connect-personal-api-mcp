# frozen_string_literal: true

require_relative "../test_helper"

class GarminClientTest < Minitest::Test
  def build(fake, max_body_bytes: 1024 * 1024, max_retries: 2, api_key: FakeGarmin::API_KEY, clock: -> { Time.now.to_f })
    http = GarminMcp::Garmin::HttpClient.new(
      base_url: fake.url, timeout: 5, max_concurrency: 4, max_body_bytes:, logger: null_logger, max_retries:, base_delay: 0
    )
    tokens = GarminMcp::Garmin::TokenProvider.new(http:, api_key:, logger: null_logger, clock:)
    [GarminMcp::Garmin::Client.new(http:, tokens:), tokens, http]
  end

  def test_exchanges_key_once_and_reuses_token
    with_fake_garmin do |fake|
      fake.json("/x", { "ok" => true })
      client, = build(fake)

      3.times { assert_equal '{"ok":true}', client.get("/x").body }
      assert_equal 1, fake.requests_to(FakeGarmin::TOKEN_PATH).size
      assert_match(/\ABearer e30\./, fake.requests_to("/x").first.headers["authorization"])
    end
  end

  def test_concurrent_calls_share_one_exchange
    with_fake_garmin do |fake|
      fake.json("/x", {})
      client, = build(fake)

      Array.new(5) { Async { client.get("/x") } }.each(&:wait)

      assert_equal 1, fake.requests_to(FakeGarmin::TOKEN_PATH).size
    end
  end

  def test_refreshes_token_once_after_unauthorized
    with_fake_garmin do |fake|
      calls = 0
      fake.route("GET", "/x") { (calls += 1) == 1 ? [401, {}, ""] : [200, { "content-type" => "application/json" }, "{}"] }
      client, = build(fake)

      assert_equal 200, client.get("/x").status
      assert_equal 2, fake.requests_to(FakeGarmin::TOKEN_PATH).size
      refute_equal(*fake.requests_to("/x").map { |request| request.headers["authorization"] })
    end
  end

  def test_rejected_key_raises_authentication_error
    with_fake_garmin do |fake|
      client, = build(fake, api_key: "wrong")

      error = assert_raises(GarminMcp::Garmin::AuthenticationError) { client.get("/x") }
      refute_includes error.message, "wrong"
    end
  end

  def test_token_close_to_expiry_is_renewed
    with_fake_garmin do |fake|
      fake.route("POST", FakeGarmin::TOKEN_PATH) { [200, {}, FakeGarmin.jwt(exp: Time.now.to_i + 600)] }
      fake.json("/x", {})
      now = Time.now.to_f
      client, = build(fake, clock: -> { now })

      client.get("/x")
      now += 290
      client.get("/x")

      assert_equal 1, fake.requests_to(FakeGarmin::TOKEN_PATH).size
      now += 20
      client.get("/x")

      assert_equal 2, fake.requests_to(FakeGarmin::TOKEN_PATH).size, "a 10 minute token is renewed after half its lifetime"
    end
  end

  def test_retries_transient_failures_honoring_retry_after
    with_fake_garmin do |fake|
      calls = 0
      fake.route("GET", "/x") { (calls += 1) < 3 ? [429, { "retry-after" => "0" }, ""] : [200, {}, "{}"] }
      client, = build(fake)

      assert_equal 200, client.get("/x").status
      assert_equal 3, calls
    end
  end

  def test_gives_up_after_max_retries
    with_fake_garmin do |fake|
      fake.route("GET", "/x") { [503, {}, ""] }
      client, = build(fake, max_retries: 1)

      assert_equal 503, client.get("/x").status
      assert_equal 2, fake.requests_to("/x").size
    end
  end

  def test_does_not_wait_for_long_retry_after
    with_fake_garmin do |fake|
      fake.route("GET", "/x") { [429, { "retry-after" => "3600" }, ""] }
      client, = build(fake)

      assert_equal 429, client.get("/x").status
      assert_equal 1, fake.requests_to("/x").size
    end
  end

  def test_caps_response_size
    with_fake_garmin do |fake|
      fake.route("GET", "/x") { [200, {}, "a" * 2048] }
      client, = build(fake, max_body_bytes: 1024)

      assert_raises(GarminMcp::Garmin::Error) { client.get("/x") }
    end
  end

  def test_unreachable_host_raises_transport_error
    Sync do
      port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
      fake = Struct.new(:url).new("http://127.0.0.1:#{port}")
      client, = build(fake, max_retries: 1)

      assert_raises(GarminMcp::Garmin::TransportError) { client.get("/x") }
    end
  end

  def test_sends_user_agent
    with_fake_garmin do |fake|
      fake.json("/x", {})
      client, = build(fake)
      client.get("/x")

      assert_equal "garmin-connect-personal-api-mcp/#{GarminMcp::VERSION}", fake.requests_to("/x").first.headers["user-agent"]
    end
  end
end
