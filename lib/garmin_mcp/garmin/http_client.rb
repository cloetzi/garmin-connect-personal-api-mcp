# frozen_string_literal: true

require "async"
require "async/http/client"
require "async/http/endpoint"
require "async/semaphore"
require "time"

module GarminMcp
  module Garmin
    class Error < GarminMcp::Error; end

    # The key exchange was rejected; the key is wrong, expired or revoked.
    class AuthenticationError < Error; end

    # Garmin could not be reached or did not answer in time.
    class TransportError < Error; end

    Response = Data.define(:status, :content_type, :body, :retry_after) do
      def success? = (200..299).cover?(status)
      def json? = content_type.to_s.include?("json")
    end

    # Fiber-based HTTP client for the Garmin host: persistent connections, bounded concurrency,
    # an overall deadline per attempt, a response size cap, and bounded retries on transient failures.
    class HttpClient
      RETRY_STATUSES = [429, 502, 503, 504].freeze
      RETRY_ERRORS = [
        Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EPIPE, Errno::ETIMEDOUT,
        EOFError, IOError, SocketError, Protocol::HTTP::Error
      ].freeze
      MAX_RETRY_AFTER = 10
      USER_AGENT = "garmin-connect-personal-api-mcp/#{VERSION}".freeze

      def initialize(base_url:, timeout:, max_concurrency:, max_body_bytes:, logger:, max_retries: 2, base_delay: 0.5)
        @endpoint = Async::HTTP::Endpoint.parse(base_url, timeout:)
        @timeout = timeout
        @max_body_bytes = max_body_bytes
        @max_retries = max_retries
        @base_delay = base_delay
        @logger = logger
        @semaphore = Async::Semaphore.new(max_concurrency)
        @client = Async::HTTP::Client.new(@endpoint)
      end

      def request(method, path, headers = [])
        headers = [["user-agent", USER_AGENT], *headers]
        attempt = 0
        loop do
          response = perform(method, path, headers)
          delay = retry_delay(response, attempt) if RETRY_STATUSES.include?(response.status)
          return response unless delay

          attempt += 1
          @logger.warn("garmin_retry", method:, path: path_only(path), status: response.status, delay:)
          sleep(delay)
        rescue *RETRY_ERRORS => e
          raise TransportError, "could not reach Garmin (#{e.class})" if attempt >= @max_retries

          attempt += 1
          @logger.warn("garmin_retry", method:, path: path_only(path), error: e.class.name)
          sleep(backoff(attempt))
        end
      end

      def close = @client.close

      private

      def perform(method, path, headers)
        @semaphore.acquire do
          Async::Task.current.with_timeout(@timeout) do
            response = @client.call(Protocol::HTTP::Request[method, path, headers])
            begin
              Response.new(
                status: response.status,
                content_type: response.headers["content-type"],
                body: read_body(response),
                retry_after: parse_retry_after(response.headers["retry-after"])
              )
            ensure
              response.close
            end
          end
        end
      rescue Async::TimeoutError
        raise TransportError, "Garmin did not respond within #{@timeout} seconds"
      end

      def read_body(response)
        declared = response.headers["content-length"]&.to_i
        raise Error, "Garmin response exceeds #{@max_body_bytes} bytes" if declared && declared > @max_body_bytes

        buffer = String.new(encoding: Encoding::BINARY)
        response.body&.each do |chunk|
          buffer << chunk
          raise Error, "Garmin response exceeds #{@max_body_bytes} bytes" if buffer.bytesize > @max_body_bytes
        end
        buffer.force_encoding(Encoding::UTF_8)
      end

      def retry_delay(response, attempt)
        return if attempt >= @max_retries

        delay = response.retry_after || backoff(attempt + 1)
        delay if delay <= MAX_RETRY_AFTER
      end

      # Retry-After is either delay-seconds or an HTTP date.
      def parse_retry_after(value)
        return if value.nil?

        value = value.to_s
        return Float(value).clamp(0, Float::INFINITY) if value.match?(/\A\d+(\.\d+)?\z/)

        (Time.httpdate(value) - Time.now).clamp(0, Float::INFINITY)
      rescue ArgumentError
        nil
      end

      def backoff(attempt) = (@base_delay * (2**(attempt - 1))) + rand(0.0..@base_delay)

      def path_only(path) = path.split("?", 2).first
    end
  end
end
