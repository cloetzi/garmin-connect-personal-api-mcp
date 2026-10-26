# frozen_string_literal: true

require_relative "../test_helper"

class LoaderTest < Minitest::Test
  # Fails with Zeitwerk::NameError when a file does not define the constant its path implies.
  def test_every_file_follows_zeitwerk_conventions
    Zeitwerk::Loader.eager_load_namespace(GarminMcp)

    assert_kind_of Class, GarminMcp::OpenAPI::Extractor
  end

  # Callers (the CLI, bin/fetch-openapi) rescue GarminMcp::Error, so every error class must descend from it.
  def test_every_error_class_inherits_from_the_base_error
    Zeitwerk::Loader.eager_load_namespace(GarminMcp)
    errors = ObjectSpace.each_object(Class).select { |klass| klass < Exception && klass.name&.start_with?("GarminMcp::") }

    assert_includes errors, GarminMcp::OpenAPI::Extractor::Error
    assert_empty(errors.reject { |klass| klass <= GarminMcp::Error })
  end
end
