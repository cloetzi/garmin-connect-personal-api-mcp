# frozen_string_literal: true

require_relative "../test_helper"

class LoaderTest < Minitest::Test
  # Fails with Zeitwerk::NameError when a file does not define the constant its path implies.
  def test_every_file_follows_zeitwerk_conventions
    Zeitwerk::Loader.eager_load_namespace(GarminMcp)

    assert_kind_of Class, GarminMcp::OpenAPI::Extractor
  end
end
