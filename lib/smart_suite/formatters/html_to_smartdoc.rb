# frozen_string_literal: true

module SmartSuite
  module Formatters
    # Converts HTML (from SmartSuite rich text fields) to SmartDoc format
    # Handles the HTML output that SmartSuite returns for richtextareafield
    class HtmlToSmartdoc
      class << self
        # Convert HTML string to SmartDoc format
        # @param html [String] HTML content (may include wrapper divs)
        # @return [Hash] SmartDoc structure with 'data' key
        def convert(html)
          return empty_doc if html.nil? || html.strip.empty?

          # Parse HTML into content blocks
          content = parse_html(html)
          content = [ create_paragraph("") ] if content.empty?

          { "data" => { "type" => "doc", "content" => content } }
        end

        private

        def empty_doc
          { "data" => { "type" => "doc", "content" => [ create_paragraph("") ] } }
        end

        def parse_html(html)
          content = []

          # Remove wrapper divs and normalize
          text = unwrap_divs(html)

          # Split into block-level elements
          blocks = extract_blocks(text)

          blocks.each do |block|
            node = parse_block(block)
            content << node if node
          end

          content
        end

        def unwrap_divs(html)
          text = html.dup
          # Remove <div...> tags but keep content
          text.gsub!(/<div[^>]*>/i, "")
          text.gsub!(%r{</div>}i, "")
          # Convert <br> to newlines
          text.gsub!(%r{<br\s*/?>}i, "\n")
          # Normalize whitespace between tags
          text.gsub!(/>\s+</, "><")
          text.strip
        end

        def extract_blocks(html)
          blocks = []
          remaining = html

          while remaining && !remaining.strip.empty?
            # Find the first block-level element
            first_match = find_first_block_match(remaining)

            if first_match
              # Add any text before the match as a paragraph
              before = remaining[0...first_match[:start]].strip
              add_text_as_paragraph(blocks, before)

              blocks << first_match[:block]
              remaining = remaining[first_match[:end]..]
            else
              # No more block elements, treat rest as paragraph
              add_text_as_paragraph(blocks, remaining.strip)
              remaining = nil
            end
          end

          blocks
        end

        def find_first_block_match(html)
          matches = []

          # Try to match each block type and record position
          if (match = html.match(%r{<(h[1-6])([^>]*)>(.*?)</\1>}im))
            matches << {
              start: match.begin(0),
              end: match.end(0),
              block: { type: :heading, level: match[1][1].to_i, content: match[3] }
            }
          end

          if (match = html.match(%r{<ul([^>]*)>(.*?)</ul>}im))
            matches << {
              start: match.begin(0),
              end: match.end(0),
              block: { type: :bullet_list, content: match[2] }
            }
          end

          if (match = html.match(%r{<ol([^>]*)>(.*?)</ol>}im))
            matches << {
              start: match.begin(0),
              end: match.end(0),
              block: { type: :ordered_list, content: match[2] }
            }
          end

          if (match = html.match(%r{<p([^>]*)>(.*?)</p>}im))
            matches << {
              start: match.begin(0),
              end: match.end(0),
              block: { type: :paragraph, content: match[2].strip }
            }
          end

          if (match = html.match(%r{<hr\s*/?>}i))
            matches << {
              start: match.begin(0),
              end: match.end(0),
              block: { type: :horizontal_rule }
            }
          end

          if (match = html.match(%r{<table[^>]*>(.*?)</table>}im))
            matches << {
              start: match.begin(0),
              end: match.end(0),
              block: { type: :table, content: match[1] }
            }
          end

          # Return the earliest match, skip empty paragraphs
          matches.reject { |m| m[:block][:type] == :paragraph && m[:block][:content].empty? }
                 .min_by { |m| m[:start] }
        end

        def add_text_as_paragraph(blocks, text)
          return if text.nil? || text.empty?

          # Strip block-level tags that might be leftover
          cleaned = text.gsub(%r{</?(?:div|p)[^>]*>}i, "").strip
          blocks << { type: :paragraph, content: cleaned } unless cleaned.empty?
        end

        def parse_block(block)
          case block[:type]
          when :heading
            create_heading(block[:content], block[:level])
          when :paragraph
            para = create_paragraph(block[:content])
            # Only return if there's actual content
            para if para["content"].any? { |c| !c["text"].empty? }
          when :bullet_list
            items = parse_list_items(block[:content])
            create_bullet_list(items) unless items.empty?
          when :ordered_list
            items = parse_list_items(block[:content])
            create_ordered_list(items) unless items.empty?
          when :horizontal_rule
            { "type" => "horizontal_rule" }
          when :table
            parse_html_table(block[:content])
          end
        end

        def parse_html_table(html)
          rows = []

          # Extract rows from tbody or directly from table content
          table_content = html.gsub(%r{<colgroup>.*?</colgroup>}im, "")
          table_content = table_content.gsub(%r{</?tbody[^>]*>}i, "")

          # Parse each row
          table_content.scan(%r{<tr[^>]*>(.*?)</tr>}im) do |row_match|
            row_html = row_match[0]
            cells = []

            # Check if this row has headers or cells
            has_headers = row_html.include?("<th")

            # Parse cells (th or td)
            cell_pattern = has_headers ? %r{<th[^>]*>(.*?)</th>}im : %r{<td[^>]*>(.*?)</td>}im
            row_html.scan(cell_pattern) do |cell_match|
              cell_content = cell_match[0]
              # Remove nested <p> tags
              cell_content = cell_content.gsub(%r{<p[^>]*>(.*?)</p>}im, '\1')
              cell_content = strip_all_tags(cell_content).strip
              cells << { text: cell_content, is_header: has_headers }
            end

            rows << cells unless cells.empty?
          end

          create_table(rows)
        end

        def create_table(rows)
          return nil if rows.empty?

          {
            "type" => "table",
            "content" => rows.map do |cells|
              {
                "type" => "table_row",
                "content" => cells.map do |cell|
                  {
                    "type" => cell[:is_header] ? "table_header" : "table_cell",
                    "content" => [
                      {
                        "type" => "paragraph",
                        "content" => [ { "type" => "text", "text" => cell[:text] } ]
                      }
                    ]
                  }
                end
              }
            end
          }
        end

        def parse_list_items(html)
          items = []
          html.scan(%r{<li[^>]*>(.*?)</li>}im) do |match|
            item_content = match[0]
            # Remove nested <p> tags from list items but keep inline formatting
            item_content = item_content.gsub(%r{<p[^>]*>(.*?)</p>}im, '\1')
            items << item_content.strip unless item_content.strip.empty?
          end
          items
        end

        def create_heading(html_content, level)
          {
            "type" => "heading",
            "attrs" => { "level" => level },
            "content" => parse_inline_formatting(html_content)
          }
        end

        def create_paragraph(html_content)
          {
            "type" => "paragraph",
            "content" => parse_inline_formatting(html_content)
          }
        end

        def create_bullet_list(items)
          {
            "type" => "bullet_list",
            "content" => items.map { |item| create_list_item(item) }
          }
        end

        def create_ordered_list(items)
          {
            "type" => "ordered_list",
            "attrs" => { "order" => 1 },
            "content" => items.map { |item| create_list_item(item) }
          }
        end

        def create_list_item(html_content)
          {
            "type" => "list_item",
            "content" => [ create_paragraph(html_content) ]
          }
        end

        def parse_inline_formatting(html)
          return [ { "type" => "text", "text" => "" } ] if html.nil? || html.empty?

          # Decode HTML entities first
          text = decode_html_entities(html)

          result = []
          remaining = text

          while remaining && !remaining.empty?
            # Match <strong> or <b>
            if (match = remaining.match(%r{<(?:strong|b)(?:\s[^>]*)?>(.+?)</(?:strong|b)>}i))
              add_text_before(result, remaining, match)
              result << create_marked_text(match[1], [ { "type" => "strong" } ])
              remaining = remaining[match.end(0)..]

            # Match <em> or <i>
            elsif (match = remaining.match(%r{<(?:em|i)(?:\s[^>]*)?>(.+?)</(?:em|i)>}i))
              add_text_before(result, remaining, match)
              result << create_marked_text(match[1], [ { "type" => "em" } ])
              remaining = remaining[match.end(0)..]

            # Match <u> (underline)
            elsif (match = remaining.match(%r{<u(?:\s[^>]*)?>(.+?)</u>}i))
              add_text_before(result, remaining, match)
              result << create_marked_text(match[1], [ { "type" => "underline" } ])
              remaining = remaining[match.end(0)..]

            # Match <s> or <strike> (strikethrough)
            elsif (match = remaining.match(%r{<(?:s|strike)(?:\s[^>]*)?>(.+?)</(?:s|strike)>}i))
              add_text_before(result, remaining, match)
              result << create_marked_text(match[1], [ { "type" => "strikethrough" } ])
              remaining = remaining[match.end(0)..]

            # Match <a href="...">
            elsif (match = remaining.match(%r{<a\s[^>]*href=["']([^"']+)["'][^>]*>(.+?)</a>}i))
              add_text_before(result, remaining, match)
              result << create_marked_text(match[2], [ { "type" => "link", "attrs" => { "href" => match[1] } } ])
              remaining = remaining[match.end(0)..]

            else
              # No more inline formatting, add remaining text (strip any remaining tags)
              clean_text = strip_all_tags(remaining)
              result << { "type" => "text", "text" => clean_text } unless clean_text.empty?
              remaining = nil
            end
          end

          result.empty? ? [ { "type" => "text", "text" => strip_all_tags(html) } ] : result
        end

        def add_text_before(result, remaining, match)
          before = remaining[0...match.begin(0)]
          clean_before = strip_all_tags(before)
          result << { "type" => "text", "text" => clean_before } unless clean_before.empty?
        end

        def create_marked_text(html, marks)
          # Recursively parse any nested formatting inside
          clean_text = strip_all_tags(html)
          {
            "type" => "text",
            "marks" => marks,
            "text" => clean_text
          }
        end

        def strip_all_tags(text)
          return "" if text.nil?

          # Remove HTML tags but preserve spacing
          text.gsub(/<[^>]+>/, "").gsub(/\s+/, " ")
        end

        def decode_html_entities(text)
          text.gsub("&lt;", "<")
              .gsub("&gt;", ">")
              .gsub("&amp;", "&")
              .gsub("&quot;", '"')
              .gsub("&#39;", "'")
              .gsub("&#x27;", "'")
              .gsub("&nbsp;", " ")
        end
      end
    end
  end
end
