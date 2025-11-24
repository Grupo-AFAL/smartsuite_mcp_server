# frozen_string_literal: true

require_relative '../../test_helper'
require_relative '../../../lib/smartsuite/formatters/markdown_to_smartdoc'

class TestMarkdownToSmartdoc < Minitest::Test
  def test_convert_empty_string
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert('')

    assert_equal 'doc', result['data']['type']
    assert_empty result['data']['content']
  end

  def test_convert_nil
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(nil)

    assert_equal 'doc', result['data']['type']
    assert_empty result['data']['content']
  end

  def test_convert_simple_paragraph
    markdown = 'This is a simple paragraph.'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    assert_equal 'doc', result['data']['type']
    assert_equal 1, result['data']['content'].size

    para = result['data']['content'][0]
    assert_equal 'paragraph', para['type']
    assert_equal 'This is a simple paragraph.', para['content'][0]['text']
  end

  def test_convert_heading_level_1
    markdown = '# Main Title'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    heading = result['data']['content'][0]
    assert_equal 'heading', heading['type']
    assert_equal 1, heading['attrs']['level']
    assert_equal 'Main Title', heading['content'][0]['text']
  end

  def test_convert_heading_level_2
    markdown = '## Section Title'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    heading = result['data']['content'][0]
    assert_equal 'heading', heading['type']
    assert_equal 2, heading['attrs']['level']
    assert_equal 'Section Title', heading['content'][0]['text']
  end

  def test_convert_heading_level_3
    markdown = '### Subsection Title'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    heading = result['data']['content'][0]
    assert_equal 'heading', heading['type']
    assert_equal 3, heading['attrs']['level']
    assert_equal 'Subsection Title', heading['content'][0]['text']
  end

  def test_convert_bullet_list_dash
    markdown = "- Item one\n- Item two\n- Item three"
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    list = result['data']['content'][0]
    assert_equal 'bullet_list', list['type']
    assert_equal 3, list['content'].size

    list['content'].each_with_index do |item, index|
      assert_equal 'list_item', item['type']
      assert_equal 'paragraph', item['content'][0]['type']
      assert_equal "Item #{%w[one two three][index]}", item['content'][0]['content'][0]['text']
    end
  end

  def test_convert_bullet_list_asterisk
    markdown = "* First\n* Second"
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    list = result['data']['content'][0]
    assert_equal 'bullet_list', list['type']
    assert_equal 2, list['content'].size
  end

  def test_convert_bold_double_asterisk
    markdown = 'This is **bold** text.'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    para = result['data']['content'][0]
    content = para['content']

    # Should have: "This is ", bold "bold", " text."
    assert_equal 3, content.size
    assert_equal 'This is ', content[0]['text']
    assert_equal 'bold', content[1]['text']
    assert_equal [{ 'type' => 'strong' }], content[1]['marks']
    assert_equal ' text.', content[2]['text']
  end

  def test_convert_bold_double_underscore
    markdown = 'This is __bold__ text.'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    para = result['data']['content'][0]
    content = para['content']

    assert_equal 3, content.size
    assert_equal 'bold', content[1]['text']
    assert_equal [{ 'type' => 'strong' }], content[1]['marks']
  end

  def test_convert_italic_single_asterisk
    markdown = 'This is *italic* text.'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    para = result['data']['content'][0]
    content = para['content']

    assert_equal 3, content.size
    assert_equal 'italic', content[1]['text']
    assert_equal [{ 'type' => 'em' }], content[1]['marks']
  end

  def test_convert_italic_single_underscore
    markdown = 'This is _italic_ text.'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    para = result['data']['content'][0]
    content = para['content']

    assert_equal 3, content.size
    assert_equal 'italic', content[1]['text']
    assert_equal [{ 'type' => 'em' }], content[1]['marks']
  end

  def test_convert_table
    markdown = <<~MARKDOWN
      | Name | Age |
      |------|-----|
      | Alice | 30 |
      | Bob | 25 |
    MARKDOWN

    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    table = result['data']['content'][0]
    assert_equal 'table', table['type']
    assert_equal 3, table['content'].size # header + 2 data rows

    # Check header row
    header_row = table['content'][0]
    assert_equal 'table_row', header_row['type']
    assert_equal 'table_header', header_row['content'][0]['type']
    assert_equal 'Name', header_row['content'][0]['content'][0]['content'][0]['text']

    # Check data rows
    data_row = table['content'][1]
    assert_equal 'table_row', data_row['type']
    assert_equal 'table_cell', data_row['content'][0]['type']
    assert_equal 'Alice', data_row['content'][0]['content'][0]['content'][0]['text']
  end

  def test_convert_mixed_content
    markdown = <<~MARKDOWN
      ## Meeting Summary

      - Action item 1
      - Action item 2

      The meeting went **well**.
    MARKDOWN

    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)
    content = result['data']['content']

    # Should have: heading, bullet_list, paragraph
    assert_equal 3, content.size
    assert_equal 'heading', content[0]['type']
    assert_equal 'bullet_list', content[1]['type']
    assert_equal 'paragraph', content[2]['type']
  end

  def test_strip_html_wrapper_div
    # SmartSuite sometimes wraps content in HTML divs
    markdown = '<div class="rendered"><p>## Summary</p></div>'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    # Should strip HTML and parse the markdown
    heading = result['data']['content'][0]
    assert_equal 'heading', heading['type']
    assert_equal 'Summary', heading['content'][0]['text']
  end

  def test_strip_html_br_tags
    markdown = "Line one<br>Line two<br/>Line three"
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    # br tags should be converted to newlines, creating separate paragraphs
    assert result['data']['content'].size >= 1
  end

  def test_convert_returns_smartdoc_structure
    markdown = 'Test content'
    result = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    # Verify the structure matches SmartDoc format
    assert result.key?('data')
    assert_equal 'doc', result['data']['type']
    assert result['data'].key?('content')
    assert result['data']['content'].is_a?(Array)
  end

  def test_result_usable_in_record_update
    # Verify the output can be used directly as a field value
    markdown = "## Notes\n- First point\n- Second point"
    smartdoc = SmartSuite::Formatters::MarkdownToSmartdoc.convert(markdown)

    # This is how it would be used in a record update
    record_data = { 'description' => smartdoc }

    assert record_data['description'].is_a?(Hash)
    assert record_data['description'].key?('data')
  end
end
