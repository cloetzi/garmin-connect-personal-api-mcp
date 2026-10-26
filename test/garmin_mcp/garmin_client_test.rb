# frozen_string_literal: true

require_relative "../test_helper"

class GarminClientTest < Minitest::Test
  def build(fake, max_body_bytes: 1024 * 1024, max_retries: 2, api_key: FakeGarmin::API_KEY, clock: -> { Time.now.to_f }, url: fake.url)
    @log = StringIO.new
    logger = GarminMcp::Logger.new(io: @log, level: "debug")
    http = GarminMcp::Garmin::HttpClient.new(base_url: url, timeout: 5, max_concurrency: 4, max_body_bytes:, logger:, max_retries:, base_delay: 0)
    tokens = GarminMcp::Garmin::TokenProvider.new(http:, api_key:, logger:, clock:)
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

  def retries = @log.string.scan("garmin_retry").size

  # Makes the underlying async-http client raise the given errors in turn, then behave normally.
  def fail_requests(http, *errors)
    client = http.instance_variable_get(:@client)
    original = client.method(:call)
    client.define_singleton_method(:call) { |request| errors.empty? ? original.call(request) : raise(errors.shift) }
  end

  def test_unreachable_host_raises_transport_error_after_retries
    Sync do
      port = TCPServer.open("127.0.0.1", 0) { |server| server.addr[1] }
      client, = build(nil, max_retries: 1, url: "http://127.0.0.1:#{port}")

      error = assert_raises(GarminMcp::Garmin::TransportError) { client.get("/x") }
      assert_match(/\ACould not reach Garmin at 127\.0\.0\.1 \(Errno::ECONNREFUSED\)/, error.message)
      assert_equal 1, retries
    end
  end

  def test_network_errors_are_retried
    with_fake_garmin do |fake|
      fake.json("/x", {})
      client, _, http = build(fake)
      client.get("/x")
      fail_requests(http, Errno::EHOSTUNREACH, Errno::ENETUNREACH)

      assert_equal 200, client.get("/x").status
      assert_equal 2, retries
    end
  end

  def test_tls_failures_are_reported_without_retry
    Sync do |task|
      server = TCPServer.new("127.0.0.1", 0)
      # Answers the TLS handshake in plain text, like a misconfigured proxy.
      listener = task.async { loop { server.accept.then { |socket| socket.write("HTTP/1.1 400 Bad Request\r\n\r\n") && socket.close } } }
      client, = build(nil, url: "https://127.0.0.1:#{server.addr[1]}")

      error = assert_raises(GarminMcp::Garmin::TransportError) { client.get("/x") }
      assert_match(/\AThe TLS connection to 127\.0\.0\.1 failed \(.+\)\. Check the CA certificates/, error.message)
      assert_equal 0, retries
    ensure
      listener&.stop
      server&.close
    end
  end

  def test_unexpected_errors_become_transport_errors
    with_fake_garmin do |fake|
      fake.json("/x", {})
      client, _, http = build(fake)
      client.get("/x")
      fail_requests(http, RuntimeError.new("secret response excerpt"))

      error = assert_raises(GarminMcp::Garmin::TransportError) { client.get("/x") }
      assert_equal "The request to Garmin at 127.0.0.1 failed unexpectedly (RuntimeError).", error.message
      assert_equal 0, retries
    end
  end

  def test_token_body_that_is_not_a_token_is_rejected
    ["\xFF\xFEnot-utf8".b, "two words", ""].each do |body|
      with_fake_garmin do |fake|
        fake.route("POST", FakeGarmin::TOKEN_PATH) { [200, { "content-type" => "text/plain" }, body] }
        client, = build(fake)

        error = assert_raises(GarminMcp::Garmin::Error) { client.get("/x") }
        assert_equal "Garmin token exchange returned an unexpected response", error.message
      end
    end
  end

  def test_token_with_unreadable_claims_gets_fallback_lifetime
    with_fake_garmin do |fake|
      fake.route("POST", FakeGarmin::TOKEN_PATH) { [200, {}, "e30.#{["true"].pack("m0")}.sig"] }
      fake.json("/x", {})
      client, = build(fake)

      assert_equal 200, client.get("/x").status
      assert_includes @log.string, "garmin_token_without_expiry"
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
