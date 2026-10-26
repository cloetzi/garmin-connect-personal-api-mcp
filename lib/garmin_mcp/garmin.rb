# frozen_string_literal: true

module GarminMcp
  module Garmin
    class Error < GarminMcp::Error; end

    # The key exchange was rejected; the key is wrong, expired or revoked.
    class AuthenticationError < Error; end

    # Garmin could not be reached or did not answer in time.
    class TransportError < Error; end
  end
end
