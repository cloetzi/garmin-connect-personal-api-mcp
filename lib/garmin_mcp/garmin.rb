# frozen_string_literal: true

module GarminMcp
  module Garmin
    class Error < GarminMcp::Error; end

    # The key exchange was rejected; the key is wrong, expired or revoked.
    class AuthenticationError < Error; end

    # The HTTP exchange with Garmin failed: unreachable host, TLS failure, timeout, broken connection.
    class TransportError < Error
      def initialize(message = nil, retryable: false)
        super(message)
        @retryable = retryable
      end

      def retryable? = @retryable
    end
  end
end
