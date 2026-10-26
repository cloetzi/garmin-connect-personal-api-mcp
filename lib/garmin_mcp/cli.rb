# frozen_string_literal: true

require "json"

module GarminMcp
  # Entry point for bin/garmin-mcp.
  class CLI
    USAGE = <<~TEXT
      Usage: garmin-mcp [command]

      Commands:
        http          Serve MCP over Streamable HTTP (default)
        stdio         Serve MCP over stdin/stdout
        check-config [http|stdio]
                      Validate configuration and overrides for a transport (default http), then exit
        tools         Print the tool catalog as JSON (no credentials needed)
        version       Print the version

      Configuration is read from environment variables; see docs/configuration.md.
    TEXT

    def self.start(argv) = new.run(argv)

    def run(argv)
      command = argv.first || "http"
      case command
      when "http" then serve_http
      when "stdio" then serve_stdio
      when "check-config" then check_config(argv[1] || "http")
      when "tools" then print_tools
      when "version", "--version", "-v" then puts VERSION
      when "help", "--help", "-h" then puts USAGE
      else
        warn "unknown command: #{command}\n\n#{USAGE}"
        exit 64
      end
    rescue GarminMcp::Error => e
      warn "garmin-mcp: #{e.message}"
      exit 78
    end

    private

    def serve_http
      require "falcon"

      app = boot(:http)
      config = app.config
      warn_insecure(app)
      host = config.host.include?(":") ? "[#{config.host}]" : config.host
      endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{config.port}")
      middleware = Falcon::Server.rack_middleware(app.rack_app, cache: false)

      with_shutdown(app) do
        Sync do
          task = Falcon::Server.new(middleware, endpoint).run
          app.logger.info("listening", url: "http://#{host}:#{config.port}#{config.path}", tools: app.tools.size,
                                       auth: config.auth_disabled ? "disabled" : "bearer")
          task.wait
        end
      end
    end

    def serve_stdio
      app = boot(:stdio)
      transport = MCP::Server::Transports::StdioTransport.new(app.mcp_server)
      app.logger.info("stdio_ready", tools: app.tools.size)
      with_shutdown(app) { Sync { transport.open } }
    end

    def check_config(transport)
      unless %w[http stdio].include?(transport)
        warn "unknown transport: #{transport}\n\n#{USAGE}"
        exit 64
      end

      app = boot(transport.to_sym)
      puts "Configuration OK for the #{transport} transport: #{app.tools.size} tools enabled (#{app.tools.map(&:name).join(", ")})"
      puts "MCP authentication: #{check_config_auth(transport, app.config)}"
    end

    def check_config_auth(transport, config)
      return "not used (stdio)" if transport == "stdio"

      config.auth_disabled ? "DISABLED" : "bearer token"
    end

    def print_tools
      puts JSON.pretty_generate(Application.catalog(overrides_file: ENV.fetch("GARMIN_MCP_OVERRIDES_FILE", nil)).manifest)
    end

    # Load all code up front so nothing autoloads inside request fibers and load errors surface at startup.
    def boot(transport)
      Zeitwerk::Loader.eager_load_namespace(GarminMcp)
      Application.new(Config.from_env(transport:))
    end

    def warn_insecure(app)
      return unless app.config.auth_disabled

      app.logger.warn("auth_disabled", message: "MCP authentication is disabled; anyone who can reach this port can read your Garmin data")
    end

    def with_shutdown(app)
      Signal.trap("TERM") { raise Interrupt }
      yield
    rescue Interrupt
      app.logger.info("shutdown")
    ensure
      app.close
    end
  end
end
