# frozen_string_literal: true

source "https://rubygems.org"

# .ruby-version and the Dockerfile pin the exact Ruby. An exact pin here makes frozen
# `bundle install` fail on every Ruby bump until Gemfile.lock is regenerated.
ruby "~> 4.0"

gem "async-http", "~> 0.105"
gem "falcon", "~> 0.57"
gem "mcp", "~> 1.9"
gem "zeitwerk", "~> 2.8"

group :development, :test do
  gem "minitest", "~> 6.0"
  gem "rake", "~> 13.3"
  gem "rubocop", "~> 1.92", require: false
  gem "rubocop-minitest", require: false
  gem "rubocop-rake", require: false
end
