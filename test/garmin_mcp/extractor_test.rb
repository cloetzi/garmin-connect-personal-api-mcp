# frozen_string_literal: true

require_relative "../test_helper"
require_relative "../../lib/garmin_mcp/openapi/extractor"

class ExtractorTest < Minitest::Test
  Extractor = GarminMcp::OpenAPI::Extractor

  def spec_literal(spec) = JSON.generate(spec).gsub("\\", "\\\\\\\\").gsub("'", "\\\\'")

  def minimal_spec(description = "plain")
    {
      "openapi" => "3.0.1",
      "servers" => [{ "url" => Extractor::EXPECTED_SERVER }],
      "paths" => { "/x" => { "get" => { "description" => description } } }
    }
  end

  def test_extracts_spec_from_bundle_alongside_other_json_literals
    spec = minimal_spec("It's a \"quoted\" café ✓ with \\ backslash")
    bundle = "a=JSON.parse('{\"other\":true}');wOaG:function(e){e.exports=JSON.parse('#{spec_literal(spec)}')},b=1"

    assert_equal spec, Extractor.extract(bundle)
  end

  def test_decodes_javascript_escapes
    assert_equal "a\nb'c\\dé\u{1F600}", Extractor.unescape_js("a\\nb\\'c\\\\d\\xe9\\ud83d\\ude00")
  end

  def test_rejects_bundle_without_spec
    error = assert_raises(Extractor::Error) { Extractor.extract("JSON.parse('{\"a\":1}')") }
    assert_match(/no OpenAPI document/, error.message)
  end

  def test_rejects_spec_for_another_server
    spec = minimal_spec.merge("servers" => [{ "url" => "https://evil.example" }])
    assert_raises(Extractor::Error) { Extractor.extract("JSON.parse('#{spec_literal(spec)}')") }
  end

  def test_vendored_spec_is_valid
    Extractor.validate!(JSON.parse(File.read(GarminMcp::Application::SPEC_PATH)))
  end
end
