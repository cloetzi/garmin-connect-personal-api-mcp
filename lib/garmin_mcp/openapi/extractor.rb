# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module GarminMcp
  module OpenAPI
    # Garmin does not publish the Personal API spec as a file: the swagger page is a Gatsby site whose
    # page component bundles the spec as a `JSON.parse('...')` string literal. This class finds that
    # bundle and decodes the literal. Only used by `bin/fetch-openapi`; the server never fetches the spec.
    class Extractor
      class Error < GarminMcp::Error; end

      PAGE_URL = "https://developer.garmin.com/gc-developer-program/personal/swagger-docs/"
      EXPECTED_SERVER = "https://personal.connectapi.garmin.com"
      BUNDLE_PATTERN = %r{/component---src-pages-gc-developer-program-personal-swagger-docs-js-[0-9a-f]+\.js}
      MAX_DOWNLOAD_BYTES = 20 * 1024 * 1024
      JS_ESCAPES = { "n" => "\n", "t" => "\t", "r" => "\r", "b" => "\b", "f" => "\f", "v" => "\v", "0" => "\0" }.freeze

      def initialize(page_url: PAGE_URL)
        @page_url = URI(page_url)
      end

      # Returns the parsed spec Hash and the bundle URL it came from.
      def fetch
        html = download(@page_url)
        bundle_path = html[BUNDLE_PATTERN] or raise Error, "swagger-docs bundle not referenced by #{@page_url}"
        bundle_url = @page_url + bundle_path
        [self.class.extract(download(bundle_url)), bundle_url.to_s]
      end

      def self.extract(javascript)
        candidates = each_json_parse_literal(javascript).filter_map do |literal|
          parsed = JSON.parse(unescape_js(literal))
          parsed if parsed.is_a?(Hash) && parsed.key?("openapi") && parsed.key?("paths")
        rescue JSON::ParserError
          nil
        end
        raise Error, "no OpenAPI document found in bundle" if candidates.empty?
        raise Error, "#{candidates.size} OpenAPI documents found in bundle; expected one" if candidates.size > 1

        validate!(candidates.first)
      end

      def self.validate!(spec)
        raise Error, "unsupported OpenAPI version #{spec["openapi"].inspect}" unless spec["openapi"].to_s.start_with?("3.")

        servers = Array(spec["servers"]).map { |server| server["url"] }
        raise Error, "spec servers #{servers.inspect} do not include #{EXPECTED_SERVER}" unless servers.include?(EXPECTED_SERVER)
        raise Error, "spec has no paths" if spec["paths"].empty?

        spec
      end

      # Yields the raw (still escaped) body of every `JSON.parse('...')` / `JSON.parse("...")` literal.
      def self.each_json_parse_literal(javascript)
        return enum_for(__method__, javascript) unless block_given?

        offset = 0
        while (start = javascript.index(/JSON\.parse\((['"])/, offset))
          quote = Regexp.last_match(1)
          cursor = start + "JSON.parse(".length + 1
          cursor += javascript[cursor] == "\\" ? 2 : 1 while cursor < javascript.length && javascript[cursor] != quote
          yield javascript[(start + "JSON.parse(".length + 1)...cursor]
          offset = cursor + 1
        end
      end

      def self.unescape_js(literal)
        literal.gsub(/(?:\\u\h{4})+|\\u\{\h+\}|\\x\h{2}|\\\r?\n|\\./m) do |escape|
          case escape
          when /\A\\u\{/ then [escape[3..-2].hex].pack("U")
          when /\A\\u/ then escape.scan(/\h{4}/).map(&:hex).pack("n*").force_encoding("UTF-16BE").encode("UTF-8")
          when /\A\\x/ then [escape[2..].hex].pack("U")
          when /\A\\\r?\n\z/ then ""
          else JS_ESCAPES.fetch(escape[1], escape[1])
          end
        end
      end

      private

      def download(uri)
        raise Error, "refusing to download from #{uri}" unless uri.scheme == "https" && uri.host == @page_url.host

        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
          request = Net::HTTP::Get.new(uri, "User-Agent" => "garmin-connect-personal-api-mcp spec sync")
          http.request(request) do |response|
            raise Error, "GET #{uri} returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

            body = +""
            response.read_body do |chunk|
              body << chunk
              raise Error, "GET #{uri} exceeded #{MAX_DOWNLOAD_BYTES} bytes" if body.bytesize > MAX_DOWNLOAD_BYTES
            end
            return body.force_encoding(Encoding::UTF_8)
          end
        end
      end
    end
  end
end
