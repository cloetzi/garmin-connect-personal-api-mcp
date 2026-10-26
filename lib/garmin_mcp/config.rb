# frozen_string_literal: true

require "ipaddr"
require "uri"

module GarminMcp
  # Server configuration from environment variables. Secrets can also be read from files
  # (`*_FILE`, e.g. Docker secrets). Invalid configuration fails at startup with every problem listed.
  class Config
    class Error < GarminMcp::Error; end

    DEFAULT_BASE_URL = "https://personal.connectapi.garmin.com"
    # The Garmin host is fixed: requests carry the API key, so the only alternative is a local fake for tests.
    BASE_URL_RULE = "must be #{DEFAULT_BASE_URL}, or (for local test servers only) an http or https URL with " \
                    "a loopback IP address, an optional port and nothing else, such as http://127.0.0.1:9292".freeze
    MIN_AUTH_TOKEN_LENGTH = 32
    LOG_LEVELS = %w[debug info warn error].freeze
    LOG_FORMATS = %w[text json].freeze

    ATTRIBUTES = %i[
      api_key base_url auth_tokens auth_disabled listen_address path allowed_hosts allowed_origins
      tools exclude_tools overrides_file max_response_bytes strip_nulls timeout max_concurrency
      max_download_bytes log_level log_format
    ].freeze

    attr_reader(*ATTRIBUTES)

    # transport: :http requires MCP authentication settings; :stdio ignores them.
    # credentials: false skips the Garmin API key and MCP tokens, for commands that never serve or call Garmin.
    def self.from_env(env = ENV, transport: :http, credentials: true) = new(env, transport, credentials).freeze

    def initialize(env, transport, credentials) # rubocop:disable Metrics/AbcSize -- one assignment per setting
      @reader = EnvReader.new(env)
      @errors = @reader.errors # Config's own checks add theirs here too, so validate! lists every problem
      @api_key = credentials ? secret("GARMIN_PERSONAL_API_KEY", required: true) : nil
      @base_url = base_url_value
      @auth_disabled = boolean("GARMIN_MCP_AUTH_DISABLED", false)
      @auth_tokens = credentials && transport == :http ? auth_tokens_value : []
      @listen_address = ListenAddress.read(@reader)
      @path = path_value
      @allowed_hosts = list("GARMIN_MCP_ALLOWED_HOSTS")
      @allowed_origins = list("GARMIN_MCP_ALLOWED_ORIGINS")
      @tools = string("GARMIN_MCP_TOOLS", nil) && list("GARMIN_MCP_TOOLS")
      @exclude_tools = list("GARMIN_MCP_EXCLUDE_TOOLS")
      @overrides_file = overrides_file_value
      @max_response_bytes = integer("GARMIN_MCP_MAX_RESPONSE_BYTES", 100_000, 1_000..10_000_000)
      @strip_nulls = boolean("GARMIN_MCP_STRIP_NULLS", true)
      @timeout = integer("GARMIN_MCP_TIMEOUT", 30, 1..300)
      @max_concurrency = integer("GARMIN_MCP_MAX_CONCURRENCY", 4, 1..64)
      @max_download_bytes = integer("GARMIN_MCP_MAX_DOWNLOAD_BYTES", 25 * 1024 * 1024, 1024..(512 * 1024 * 1024))
      @log_level = choice("GARMIN_MCP_LOG_LEVEL", "info", LOG_LEVELS)
      @log_format = choice("GARMIN_MCP_LOG_FORMAT", "text", LOG_FORMATS)
      validate!
    end

    def inspect = "#<#{self.class.name} listen=#{listen_address.authority} path=#{path} auth=#{auth_disabled ? "disabled" : "bearer"}>"

    private

    def string(...) = @reader.string(...)
    def list(...) = @reader.list(...)
    def integer(...) = @reader.integer(...)
    def boolean(...) = @reader.boolean(...)
    def choice(...) = @reader.choice(...)
    def secret(...) = @reader.secret(...)

    def validate!
      @reader.validate!
      remove_instance_variable(:@reader)
      remove_instance_variable(:@errors)
    end

    def auth_tokens_value
      raw = secret("GARMIN_MCP_AUTH_TOKEN")
      tokens = raw.to_s.split(/[\s,]+/).reject(&:empty?)
      if @auth_disabled
        @errors << "GARMIN_MCP_AUTH_DISABLED=true conflicts with GARMIN_MCP_AUTH_TOKEN; set only one" if tokens.any?
      elsif tokens.empty?
        @errors << "GARMIN_MCP_AUTH_TOKEN (or GARMIN_MCP_AUTH_TOKEN_FILE) is required; " \
                   "generate one with `openssl rand -hex 32`, or set GARMIN_MCP_AUTH_DISABLED=true to run without authentication"
      elsif tokens.any? { |token| token.length < MIN_AUTH_TOKEN_LENGTH }
        @errors << "GARMIN_MCP_AUTH_TOKEN values must be at least #{MIN_AUTH_TOKEN_LENGTH} characters"
      end
      tokens.freeze
    end

    def base_url_value
      value = string("GARMIN_PERSONAL_API_BASE_URL", DEFAULT_BASE_URL).chomp("/")
      return value if value == DEFAULT_BASE_URL || loopback_origin?(URI(value))

      @errors << "GARMIN_PERSONAL_API_BASE_URL #{BASE_URL_RULE}"
      value
    rescue URI::InvalidURIError
      @errors << "GARMIN_PERSONAL_API_BASE_URL is not a valid URL; it #{BASE_URL_RULE}"
      value
    end

    def path_value
      value = string("GARMIN_MCP_PATH", "/mcp")
      if value == HealthCheck::PATH
        @errors << "GARMIN_MCP_PATH cannot be #{HealthCheck::PATH}, which serves health checks"
      elsif !value.match?(%r{\A/[A-Za-z0-9/_.~-]*\z})
        @errors << "GARMIN_MCP_PATH must start with / and contain only URL path characters"
      end
      value
    end

    def overrides_file_value
      value = string("GARMIN_MCP_OVERRIDES_FILE", nil)
      return unless value

      @errors << "GARMIN_MCP_OVERRIDES_FILE: cannot read #{value}" unless File.file?(value) && File.readable?(value)
      value
    end

    # Hostnames, even localhost, are refused: /etc/hosts entries (e.g. Docker's --add-host) can point them anywhere.
    def loopback_origin?(uri)
      %w[http https].include?(uri.scheme) && uri.userinfo.nil? && uri.path.empty? && uri.query.nil? &&
        uri.fragment.nil? && IPAddr.new(uri.host.to_s.delete("[]")).loopback?
    rescue IPAddr::Error
      false
    end
  end
end
