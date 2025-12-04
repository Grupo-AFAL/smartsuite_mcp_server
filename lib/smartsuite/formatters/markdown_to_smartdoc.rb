# frozen_string_literal: true

module SmartSuite
  module Formatters
    # Converts Markdown text to SmartSuite's SmartDoc format (TipTap/ProseMirror with snake_case)
    class MarkdownToSmartdoc
      class << self
        # Convert markdown string to SmartDoc format
        # @param markdown [String] Markdown text (may be wrapped in HTML div)
        # @return [Hash] SmartDoc structure with 'data' key
        def convert(markdown)
          # Strip HTML wrapper if present
          text = strip_html_wrapper(markdown)

          # Parse markdown into content blocks
          content = parse_markdown(text)

          { "data" => { "type" => "doc", "content" => content } }
        end

        private

        def strip_html_wrapper(text)
          return "" if text.nil? || text.empty?

          # Remove <div class="rendered"><p> wrapper and </p></div>
          text = text.gsub(/<div[^>]*>/, "")
          text = text.gsub("</div>", "")
          text = text.gsub("<p>", "")
          text = text.gsub("</p>", "")
          # Convert <br> to newlines
          text = text.gsub(%r{<br\s*/?>}, "\n")
          text.strip
        end

        def parse_markdown(text)
          content = []
          lines = text.split("\n")
          i = 0

          while i < lines.length
            line = lines[i]

            if line.match?(/^---+\s*$/)
              # Horizontal rule
              content << { "type" => "horizontal_rule" }
              i += 1
            elsif line.start_with?("```")
              # Code block
              code_block, i = parse_code_block(lines, i)
              content << code_block if code_block
            elsif line.start_with?("## ")
              # Heading level 2
              content << create_heading(line[3..].strip, 2)
              i += 1
            elsif line.start_with?("# ")
              # Heading level 1
              content << create_heading(line[2..].strip, 1)
              i += 1
            elsif line.start_with?("### ")
              # Heading level 3
              content << create_heading(line[4..].strip, 3)
              i += 1
            elsif line.match?(/^\d+\.\s/)
              # Ordered list
              list_items, i = parse_ordered_list(lines, i)
              content << create_ordered_list(list_items)
            elsif line.start_with?("- ") || line.start_with?("* ")
              # Bullet list
              list_items, i = parse_list(lines, i)
              content << create_bullet_list(list_items)
            elsif line.start_with?("|")
              # Table
              table, i = parse_table(lines, i)
              content << table if table
            elsif line.strip.empty?
              # Skip empty lines
              i += 1
            else
              # Regular paragraph
              content << create_paragraph(line.strip) unless line.strip.empty?
              i += 1
            end
          end

          content
        end

        def create_heading(text, level)
          {
            "type" => "heading",
            "attrs" => { "level" => level },
            "content" => parse_inline_formatting(text)
          }
        end

        def create_paragraph(text)
          {
            "type" => "paragraph",
            "content" => parse_inline_formatting(text)
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

        def create_list_item(text)
          {
            "type" => "list_item",
            "content" => [
              {
                "type" => "paragraph",
                "content" => parse_inline_formatting(text)
              }
            ]
          }
        end

        def parse_list(lines, start_index)
          items = []
          i = start_index

          while i < lines.length
            line = lines[i]
            if line.start_with?("- ") || line.start_with?("* ")
              items << line[2..].strip
              i += 1
            elsif line.strip.empty?
              i += 1
              # Check if next line continues the list
              break if i >= lines.length || (!lines[i].start_with?("- ") && !lines[i].start_with?("* "))
            else
              break
            end
          end

          [ items, i ]
        end

        def parse_ordered_list(lines, start_index)
          items = []
          i = start_index

          while i < lines.length
            line = lines[i]
            if line.match?(/^\d+\.\s/)
              # Remove number and period
              items << line.sub(/^\d+\.\s/, "").strip
              i += 1
            elsif line.strip.empty?
              i += 1
              # Check if next line continues the list
              break if i >= lines.length || !lines[i].match?(/^\d+\.\s/)
            else
              break
            end
          end

          [ items, i ]
        end

        def parse_code_block(lines, start_index)
          i = start_index
          opening_line = lines[i]

          # Extract language if present (```language)
          language = opening_line[3..].strip
          language = nil if language.empty?

          i += 1
          code_lines = []

          # Collect lines until closing ```
          while i < lines.length
            line = lines[i]
            if line.start_with?("```")
              i += 1
              break
            end
            code_lines << line
            i += 1
          end

          # Create code block with hard_break nodes for line breaks
          content = []
          code_lines.each_with_index do |line, index|
            content << { "type" => "text", "text" => line }
            content << { "type" => "hard_break" } if index < code_lines.length - 1
          end

          code_block = {
            "type" => "code_block",
            "attrs" => {
              "language" => language || "plaintext",
              "lineWrapping" => true
            },
            "content" => content
          }

          [ code_block, i ]
        end

        def parse_table(lines, start_index)
          rows = []
          i = start_index

          while i < lines.length && lines[i].start_with?("|")
            line = lines[i].strip

            # Skip separator line (|---|---|)
            if line.match?(/^\|[\s\-:]+\|/)
              i += 1
              next
            end

            # Parse table row
            cells = line.split("|").map(&:strip).reject(&:empty?)
            rows << cells unless cells.empty?
            i += 1
          end

          return [ nil, i ] if rows.empty?

          table = create_table(rows)
          [ table, i ]
        end

        def create_table(rows)
          return nil if rows.empty?

          table_rows = rows.each_with_index.map do |cells, row_index|
            cell_type = row_index.zero? ? "table_header" : "table_cell"

            {
              "type" => "table_row",
              "content" => cells.map do |cell_text|
                {
                  "type" => cell_type,
                  "content" => [
                    {
                      "type" => "paragraph",
                      "content" => parse_inline_formatting(cell_text)
                    }
                  ]
                }
              end
            }
          end

          { "type" => "table", "content" => table_rows }
        end

        def parse_inline_formatting(text)
          return [ { "type" => "text", "text" => "" } ] if text.nil? || text.empty?

          result = []
          remaining = text

          while remaining && !remaining.empty?
            # Try to match links first [text](url)
            if (match = remaining.match(/\[([^\]]+)\]\(([^)]+)\)/))
              # Add text before match
              result << { "type" => "text", "text" => remaining[0...match.begin(0)] } if match.begin(0).positive?

              # Parse formatting inside link text
              link_text_parts = parse_inline_formatting_recursive(match[1])

              # Add marks to each part
              link_text_parts.each do |part|
                marks = part["marks"] || []
                marks << { "type" => "link", "attrs" => { "href" => match[2] } }
                result << {
                  "type" => "text",
                  "marks" => marks,
                  "text" => part["text"]
                }
              end

              remaining = remaining[match.end(0)..]
            # Try to match bold+italic (***text*** or ___text___)
            elsif (match = remaining.match(/\*\*\*(.+?)\*\*\*/) || remaining.match(/___(.+?)___/))
              # Add text before match
              result << { "type" => "text", "text" => remaining[0...match.begin(0)] } if match.begin(0).positive?
              # Add bold+italic text
              result << {
                "type" => "text",
                "marks" => [ { "type" => "strong" }, { "type" => "em" } ],
                "text" => match[1]
              }
              remaining = remaining[match.end(0)..]
            # Try to match bold (**text** or __text__)
            elsif (match = remaining.match(/\*\*(.+?)\*\*/) || remaining.match(/__(.+?)__/))
              # Add text before match
              result << { "type" => "text", "text" => remaining[0...match.begin(0)] } if match.begin(0).positive?
              # Add bold text
              result << {
                "type" => "text",
                "marks" => [ { "type" => "strong" } ],
                "text" => match[1]
              }
              remaining = remaining[match.end(0)..]
            # Try to match italic (*text* or _text_) - but not ** or __
            elsif (match = remaining.match(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/) || remaining.match(/(?<!_)_(?!_)(.+?)(?<!_)_(?!_)/))
              # Add text before match
              result << { "type" => "text", "text" => remaining[0...match.begin(0)] } if match.begin(0).positive?
              # Add italic text
              result << {
                "type" => "text",
                "marks" => [ { "type" => "em" } ],
                "text" => match[1]
              }
              remaining = remaining[match.end(0)..]
            else
              # No more formatting, add remaining text
              result << { "type" => "text", "text" => remaining }
              remaining = nil
            end
          end

          result.empty? ? [ { "type" => "text", "text" => text } ] : result
        end

        # Helper method to parse formatting recursively (for link text)
        def parse_inline_formatting_recursive(text)
          return [ { "type" => "text", "text" => text } ] if text.nil? || text.empty?

          result = []
          remaining = text

          while remaining && !remaining.empty?
            # Try to match bold+italic
            if (match = remaining.match(/\*\*\*(.+?)\*\*\*/) || remaining.match(/___(.+?)___/))
              result << { "type" => "text", "text" => remaining[0...match.begin(0)] } if match.begin(0).positive?
              result << {
                "type" => "text",
                "marks" => [ { "type" => "strong" }, { "type" => "em" } ],
                "text" => match[1]
              }
              remaining = remaining[match.end(0)..]
            # Try to match bold
            elsif (match = remaining.match(/\*\*(.+?)\*\*/) || remaining.match(/__(.+?)__/))
              result << { "type" => "text", "text" => remaining[0...match.begin(0)] } if match.begin(0).positive?
              result << {
                "type" => "text",
                "marks" => [ { "type" => "strong" } ],
                "text" => match[1]
              }
              remaining = remaining[match.end(0)..]
            # Try to match italic
            elsif (match = remaining.match(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/) || remaining.match(/(?<!_)_(?!_)(.+?)(?<!_)_(?!_)/))
              result << { "type" => "text", "text" => remaining[0...match.begin(0)] } if match.begin(0).positive?
              result << {
                "type" => "text",
                "marks" => [ { "type" => "em" } ],
                "text" => match[1]
              }
              remaining = remaining[match.end(0)..]
            else
              result << { "type" => "text", "text" => remaining }
              remaining = nil
            end
          end

          result.empty? ? [ { "type" => "text", "text" => text } ] : result
        end
      end
    end
  end
end
