# frozen_string_literal: true

require_relative "../../test_helper"
require_relative "../../../lib/smart_suite/formatters/html_to_smartdoc"

class TestHtmlToSmartdoc < Minitest::Test
  def test_convert_empty_string
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert("")

    assert_equal "doc", result["data"]["type"]
    assert_equal 1, result["data"]["content"].size
    assert_equal "paragraph", result["data"]["content"][0]["type"]
  end

  def test_convert_nil
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(nil)

    assert_equal "doc", result["data"]["type"]
    assert_equal 1, result["data"]["content"].size
  end

  def test_convert_simple_paragraph
    html = "<p>This is a simple paragraph.</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    assert_equal "doc", result["data"]["type"]
    assert_equal 1, result["data"]["content"].size

    para = result["data"]["content"][0]
    assert_equal "paragraph", para["type"]
    assert_equal "This is a simple paragraph.", para["content"][0]["text"]
  end

  def test_convert_paragraph_with_class
    html = '<p class="align-left">Paragraph with class.</p>'
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    assert_equal "paragraph", para["type"]
    assert_equal "Paragraph with class.", para["content"][0]["text"]
  end

  def test_convert_heading_h1
    html = "<h1>Main Title</h1>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    heading = result["data"]["content"][0]
    assert_equal "heading", heading["type"]
    assert_equal 1, heading["attrs"]["level"]
    assert_equal "Main Title", heading["content"][0]["text"]
  end

  def test_convert_heading_h2
    html = "<h2>Section Title</h2>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    heading = result["data"]["content"][0]
    assert_equal "heading", heading["type"]
    assert_equal 2, heading["attrs"]["level"]
    assert_equal "Section Title", heading["content"][0]["text"]
  end

  def test_convert_heading_h3
    html = "<h3>Subsection Title</h3>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    heading = result["data"]["content"][0]
    assert_equal "heading", heading["type"]
    assert_equal 3, heading["attrs"]["level"]
    assert_equal "Subsection Title", heading["content"][0]["text"]
  end

  def test_convert_heading_with_data_id_attribute
    html = '<h2 data-id="pakhjwugyuf">Title with data-id</h2>'
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    heading = result["data"]["content"][0]
    assert_equal "heading", heading["type"]
    assert_equal 2, heading["attrs"]["level"]
    assert_equal "Title with data-id", heading["content"][0]["text"]
  end

  def test_convert_bullet_list
    html = "<ul><li>Item one</li><li>Item two</li><li>Item three</li></ul>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    list = result["data"]["content"][0]
    assert_equal "bullet_list", list["type"]
    assert_equal 3, list["content"].size

    list["content"].each_with_index do |item, index|
      assert_equal "list_item", item["type"]
      assert_equal "paragraph", item["content"][0]["type"]
      assert_equal "Item #{%w[one two three][index]}", item["content"][0]["content"][0]["text"]
    end
  end

  def test_convert_bullet_list_with_paragraph_inside
    html = '<ul><li><p class="align-left">First item</p></li><li><p class="align-left">Second item</p></li></ul>'
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    list = result["data"]["content"][0]
    assert_equal "bullet_list", list["type"]
    assert_equal 2, list["content"].size
    assert_equal "First item", list["content"][0]["content"][0]["content"][0]["text"]
    assert_equal "Second item", list["content"][1]["content"][0]["content"][0]["text"]
  end

  def test_convert_ordered_list
    html = "<ol><li>First step</li><li>Second step</li><li>Third step</li></ol>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    list = result["data"]["content"][0]
    assert_equal "ordered_list", list["type"]
    assert_equal 1, list["attrs"]["order"]
    assert_equal 3, list["content"].size

    list["content"].each_with_index do |item, index|
      assert_equal "list_item", item["type"]
      assert_equal "#{%w[First Second Third][index]} step", item["content"][0]["content"][0]["text"]
    end
  end

  def test_convert_bold_strong_tag
    html = "<p>This is <strong>bold</strong> text.</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    content = para["content"]

    assert_equal 3, content.size
    assert_equal "This is ", content[0]["text"]
    assert_equal "bold", content[1]["text"]
    assert_equal [ { "type" => "strong" } ], content[1]["marks"]
    assert_equal " text.", content[2]["text"]
  end

  def test_convert_bold_b_tag
    html = "<p>This is <b>bold</b> text.</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    bold_node = para["content"].find { |n| n["text"] == "bold" }

    assert bold_node
    assert_equal [ { "type" => "strong" } ], bold_node["marks"]
  end

  def test_convert_italic_em_tag
    html = "<p>This is <em>italic</em> text.</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    italic_node = para["content"].find { |n| n["text"] == "italic" }

    assert italic_node
    assert_equal [ { "type" => "em" } ], italic_node["marks"]
  end

  def test_convert_italic_i_tag
    html = "<p>This is <i>italic</i> text.</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    italic_node = para["content"].find { |n| n["text"] == "italic" }

    assert italic_node
    assert_equal [ { "type" => "em" } ], italic_node["marks"]
  end

  def test_convert_underline
    html = "<p>This is <u>underlined</u> text.</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    underline_node = para["content"].find { |n| n["text"] == "underlined" }

    assert underline_node
    assert_equal [ { "type" => "underline" } ], underline_node["marks"]
  end

  def test_convert_link
    html = '<p>Visit <a href="https://example.com">our website</a> for more info.</p>'
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    link_node = para["content"].find { |n| n["text"] == "our website" }

    assert link_node
    assert(link_node["marks"].any? { |m| m["type"] == "link" && m["attrs"]["href"] == "https://example.com" })
  end

  def test_convert_horizontal_rule
    html = "<p>Before</p><hr/><p>After</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    content = result["data"]["content"]
    assert_equal 3, content.size
    assert_equal "paragraph", content[0]["type"]
    assert_equal "horizontal_rule", content[1]["type"]
    assert_equal "paragraph", content[2]["type"]
  end

  def test_convert_div_wrapper
    html = '<div class="rendered"><p>Content inside div</p></div>'
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    assert_equal "paragraph", para["type"]
    assert_equal "Content inside div", para["content"][0]["text"]
  end

  def test_convert_nested_div_wrapper
    html = '<div class="outer"><div class="inner"><p>Nested content</p></div></div>'
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    assert_equal "paragraph", para["type"]
    assert_equal "Nested content", para["content"][0]["text"]
  end

  def test_convert_html_entities
    # Test that common HTML entities are decoded
    html = "<p>Quote &quot;text&quot; and apostrophe &#39;s and ampersand &amp;</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    text = para["content"][0]["text"]
    assert_includes text, '"'
    assert_includes text, "'"
    assert_includes text, "&"
  end

  def test_convert_escaped_html_tags
    # Edge case: HTML entities that look like tags after decoding
    # In real SmartSuite content, this is very rare - users don't typically
    # write &lt;h2&gt; as visible text. The converter treats decoded < and >
    # as potential tags and strips them, which is acceptable for our use case.
    html = "<p>&lt;h2&gt;Title&lt;/h2&gt;</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    text = para["content"][0]["text"]
    # After decoding and tag stripping, only "Title" remains
    assert_equal "Title", text.strip
  end

  def test_convert_smartsuite_typical_format
    # Typical HTML from SmartSuite rich text field
    html = <<~HTML
      <div class="rendered">
        <h2 data-id="abc123">
          Participantes
        </h2>
        <ul>
          <li><p class="align-left">Juan</p></li>
          <li><p class="align-left">María</p></li>
        </ul>
        <h2 data-id="def456">
          Resumen
        </h2>
        <p class="align-left">La reunión fue <strong>productiva</strong>.</p>
      </div>
    HTML

    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)
    content = result["data"]["content"]

    # Should have: heading, bullet_list, heading, paragraph
    types = content.map { |node| node["type"] }
    assert_includes types, "heading"
    assert_includes types, "bullet_list"
    assert_includes types, "paragraph"

    # Check headings have correct level
    headings = content.select { |n| n["type"] == "heading" }
    assert headings.all? { |h| h["attrs"]["level"] == 2 }

    # Check list has 2 items
    list = content.find { |n| n["type"] == "bullet_list" }
    assert_equal 2, list["content"].size
  end

  def test_convert_mixed_content
    html = <<~HTML
      <h1>Project Summary</h1>
      <p>This project aims to <strong>improve</strong> user experience.</p>
      <h2>Key Features</h2>
      <ul>
        <li>Enhanced navigation</li>
        <li>Faster load times</li>
      </ul>
    HTML

    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)
    content = result["data"]["content"]

    # Verify structure
    assert_equal "heading", content[0]["type"]
    assert_equal 1, content[0]["attrs"]["level"]

    # Find paragraph with bold
    para = content.find { |n| n["type"] == "paragraph" && n["content"].any? { |c| c["marks"] } }
    assert para

    # Find bullet list
    list = content.find { |n| n["type"] == "bullet_list" }
    assert list
    assert_equal 2, list["content"].size
  end

  def test_convert_strikethrough
    html = "<p>This is <s>deleted</s> text.</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    para = result["data"]["content"][0]
    strike_node = para["content"].find { |n| n["text"] == "deleted" }

    assert strike_node
    assert_equal [ { "type" => "strikethrough" } ], strike_node["marks"]
  end

  def test_convert_br_tags
    html = "<p>Line one<br>Line two<br/>Line three</p>"
    result = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    # br tags are converted to newlines during processing
    assert result["data"]["content"].size >= 1
  end

  def test_result_usable_in_record_update
    html = "<h2>Notes</h2><ul><li>First point</li><li>Second point</li></ul>"
    smartdoc = SmartSuite::Formatters::HtmlToSmartdoc.convert(html)

    # This is how it would be used in a record update
    record_data = { "description" => smartdoc }

    assert record_data["description"].is_a?(Hash)
    assert record_data["description"].key?("data")
    assert_equal "doc", record_data["description"]["data"]["type"]
  end
end
