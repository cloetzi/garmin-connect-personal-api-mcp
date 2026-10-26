# frozen_string_literal: true

require "mcp"

module GarminMcp
  # Wires configuration, catalog, Garmin client and MCP server together.
  class Application
    SPEC_PATH = File.expand_path("../../data/openapi.json", __dir__)
    SERVER_NAME = "garmin-connect-personal-api"

    attr_reader :config, :logger, :catalog, :tools

    def self.catalog(overrides_file: nil)
      spec = OpenAPI::Spec.load(SPEC_PATH)
      Catalog.new(spec, Overrides.load(spec, [Overrides::BUNDLED_PATH, overrides_file].compact))
    end

    def initialize(config, logger: Logger.new(level: config.log_level, format: config.log_format))
      @config = config
      @logger = logger
      @catalog = self.class.catalog(overrides_file: config.overrides_file)
      @tools = catalog.select(include: config.tools, exclude: config.exclude_tools)
      raise Error, "no tools are enabled; check GARMIN_MCP_TOOLS and GARMIN_MCP_EXCLUDE_TOOLS" if tools.empty?
    end

    def http
      @http ||= Garmin::HttpClient.new(
        base_url: config.base_url,
        timeout: config.timeout,
        max_concurrency: config.max_concurrency,
        max_body_bytes: config.max_download_bytes,
        logger:
      )
    end

    # A fresh MCP server per transport; the SDK binds one transport to one server.
    def mcp_server
      runner = ToolRunner.new(
        client: Garmin::Client.new(http:, tokens:),
        logger:,
        max_response_bytes: config.max_response_bytes,
        strip_nulls: config.strip_nulls
      )
      MCP::Server.new(
        name: SERVER_NAME,
        title: "Garmin Connect Personal API",
        version: VERSION,
        instructions: catalog.instructions,
        tools: tools.map { |definition| runner.mcp_tool(definition) },
        capabilities: { tools: {} },
        configuration: MCP::Configuration.new(exception_reporter: method(:report_exception))
      )
    end

    def rack_app = HttpApp.new(server: mcp_server, config:, logger:)

    def close = @http&.close

    private

    def tokens = @tokens ||= Garmin::TokenProvider.new(http:, api_key: config.api_key, logger:)

    def report_exception(exception, _context)
      logger.error("unhandled_exception", error: exception.class.name, message: exception.message.to_s[0, 200])
    end
  end
end
