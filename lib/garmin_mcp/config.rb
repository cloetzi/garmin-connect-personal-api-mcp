# frozen_string_literal: true

require "ipaddr"
require "uri"

module GarminMcp
  # Server configuration from environment variables. Secrets can also be read from files
  # (`*_FILE`, e.g. Docker secrets). Invalid configuration fails at startup with every problem listed.
  class Config
    class Error < GarminMcp::Error; end

    DEFAULT_BASE_URL = "https://personal.connectapi.garmin.com"
    MIN_AUTH_TOKEN_LENGTH = 32
    LOG_LEVELS = %w[debug info warn error].freeze
    LOG_FORMATS = %w[text json].freeze

    ATTRIBUTES = %i[
      api_key base_url auth_tokens auth_disabled host port path allowed_hosts allowed_origins
      tools exclude_tools overrides_file max_response_bytes strip_nulls timeout max_concurrency
      max_download_bytes log_level log_format
    ].freeze

    attr_reader(*ATTRIBUTES)

    # transport: :http requires MCP authentication settings; :stdio ignores them.
    # credentials: false skips the Garmin API key and MCP tokens, for commands that never serve or call Garmin.
    def self.from_env(env = ENV, transport: :http, credentials: true) = new(env, transport, credentials).freeze

    # [host, port] of the HTTP listener, parsed as for the server but without reading secrets or any other setting,
    # so the container health check stays cheap. Raises Error when either is invalid.
    def self.listen_address(env = ENV) = allocate.send(:read_listen_address, env)

    def initialize(env, transport, credentials) # rubocop:disable Metrics/AbcSize -- one assignment per setting
      @env = env
      @errors = []
      @api_key = credentials ? secret("GARMIN_PERSONAL_API_KEY", required: true) : nil
      @base_url = base_url_value
      @auth_disabled = boolean("GARMIN_MCP_AUTH_DISABLED", false)
      @auth_tokens = credentials && transport == :http ? auth_tokens_value : []
      @host, @port = listen_address_value
      @path = path_value
      @allowed_hosts = list("GARMIN_MCP_ALLOWED_HOSTS")
      @allowed_origins = list("GARMIN_MCP_ALLOWED_ORIGINS")
      @tools = @env["GARMIN_MCP_TOOLS"].to_s.strip.empty? ? nil : list("GARMIN_MCP_TOOLS")
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

    def inspect = "#<#{self.class.name} host=#{host} port=#{port} path=#{path} auth=#{auth_disabled ? "disabled" : "bearer"}>"

    private

    def read_listen_address(env)
      @env = env
      @errors = []
      listen_address_value.tap { validate! }
    end

    def validate!
      raise Error, "invalid configuration:\n  - #{@errors.join("\n  - ")}" if @errors.any?

      remove_instance_variable(:@env)
      remove_instance_variable(:@errors)
    end

    def secret(name, required: false)
      file_name = "#{name}_FILE"
      direct = @env[name].to_s.strip
      file = @env[file_name].to_s.strip
      unless direct.empty? || file.empty?
        @errors << "set only one of #{name} and #{file_name}"
        return
      end

      value = file.empty? ? direct : read_secret_file(file_name, file)
      @errors << "#{name} (or #{file_name}) is required" if required && value.to_s.empty?
      value.to_s.empty? ? nil : value
    end

    def read_secret_file(name, path)
      File.read(path).strip
    rescue SystemCallError => e
      @errors << "#{name}: cannot read #{path} (#{e.class.name.split("::").last})"
      nil
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
      uri = URI(value)
      return value if uri.scheme == "https" && uri.host
      return value if uri.scheme == "http" && loopback?(uri.host)

      @errors << "GARMIN_PERSONAL_API_BASE_URL must be an https URL (plain http is only allowed for loopback hosts)"
      value
    rescue URI::InvalidURIError
      @errors << "GARMIN_PERSONAL_API_BASE_URL is not a valid URL"
      value
    end

    def listen_address_value = [string("GARMIN_MCP_HOST", "127.0.0.1"), integer("GARMIN_MCP_PORT", 8080, 1..65_535)]

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
      value = @env["GARMIN_MCP_OVERRIDES_FILE"].to_s.strip
      return if value.empty?

      @errors << "GARMIN_MCP_OVERRIDES_FILE: cannot read #{value}" unless File.file?(value) && File.readable?(value)
      value
    end

    def loopback?(host)
      host == "localhost" || IPAddr.new(host.to_s.delete("[]")).loopback?
    rescue IPAddr::Error
      false
    end

    def string(name, default)
      value = @env[name].to_s.strip
      value.empty? ? default : value
    end

    def list(name) = @env[name].to_s.split(",").map(&:strip).reject(&:empty?).freeze

    def integer(name, default, range)
      raw = @env[name].to_s.strip
      return default if raw.empty?

      value = Integer(raw, 10)
      return value if range.cover?(value)

      @errors << "#{name} must be between #{range.min} and #{range.max}"
      default
    rescue ArgumentError
      @errors << "#{name} must be an integer"
      default
    end

    def boolean(name, default)
      case @env[name].to_s.strip.downcase
      when "" then default
      when "true", "1", "yes" then true
      when "false", "0", "no" then false
      else
        @errors << "#{name} must be true or false"
        default
      end
    end

    def choice(name, default, choices)
      value = string(name, default).downcase
      return value if choices.include?(value)

      @errors << "#{name} must be one of #{choices.join(", ")}"
      default
    end
  end
end
