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

          { 'data' => { 'type' => 'doc', 'content' => content } }
        end

        private

        def strip_html_wrapper(text)
          return '' if text.nil? || text.empty?

          # Remove <div class="rendered"><p> wrapper and </p></div>
          text = text.gsub(/<div[^>]*>/, '')
          text = text.gsub('</div>', '')
          text = text.gsub('<p>', '')
          text = text.gsub('</p>', '')
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

            if line.start_with?('## ')
              # Heading level 2
              content << create_heading(line[3..].strip, 2)
              i += 1
            elsif line.start_with?('# ')
              # Heading level 1
              content << create_heading(line[2..].strip, 1)
              i += 1
            elsif line.start_with?('### ')
              # Heading level 3
              content << create_heading(line[4..].strip, 3)
              i += 1
            elsif line.start_with?('- ') || line.start_with?('* ')
              # Bullet list
              list_items, i = parse_list(lines, i)
              content << create_bullet_list(list_items)
            elsif line.start_with?('|')
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
            'type' => 'heading',
            'attrs' => { 'level' => level },
            'content' => parse_inline_formatting(text)
          }
        end

        def create_paragraph(text)
          {
            'type' => 'paragraph',
            'content' => parse_inline_formatting(text)
          }
        end

        def create_bullet_list(items)
          {
            'type' => 'bullet_list',
            'content' => items.map { |item| create_list_item(item) }
          }
        end

        def create_list_item(text)
          {
            'type' => 'list_item',
            'content' => [
              {
                'type' => 'paragraph',
                'content' => parse_inline_formatting(text)
              }
            ]
          }
        end

        def parse_list(lines, start_index)
          items = []
          i = start_index

          while i < lines.length
            line = lines[i]
            if line.start_with?('- ') || line.start_with?('* ')
              items << line[2..].strip
              i += 1
            elsif line.strip.empty?
              i += 1
              # Check if next line continues the list
              break if i >= lines.length || (!lines[i].start_with?('- ') && !lines[i].start_with?('* '))
            else
              break
            end
          end

          [items, i]
        end

        def parse_table(lines, start_index)
          rows = []
          i = start_index

          while i < lines.length && lines[i].start_with?('|')
            line = lines[i].strip

            # Skip separator line (|---|---|)
            if line.match?(/^\|[\s\-:]+\|/)
              i += 1
              next
            end

            # Parse table row
            cells = line.split('|').map(&:strip).reject(&:empty?)
            rows << cells unless cells.empty?
            i += 1
          end

          return [nil, i] if rows.empty?

          table = create_table(rows)
          [table, i]
        end

        def create_table(rows)
          return nil if rows.empty?

          table_rows = rows.each_with_index.map do |cells, row_index|
            cell_type = row_index.zero? ? 'table_header' : 'table_cell'

            {
              'type' => 'table_row',
              'content' => cells.map do |cell_text|
                {
                  'type' => cell_type,
                  'content' => [
                    {
                      'type' => 'paragraph',
                      'content' => parse_inline_formatting(cell_text)
                    }
                  ]
                }
              end
            }
          end

          { 'type' => 'table', 'content' => table_rows }
        end

        def parse_inline_formatting(text)
          return [{ 'type' => 'text', 'text' => '' }] if text.nil? || text.empty?

          result = []
          remaining = text

          while remaining && !remaining.empty?
            # Try to match bold (**text** or __text__)
            if (match = remaining.match(/\*\*(.+?)\*\*/) || remaining.match(/__(.+?)__/))
              # Add text before match
              result << { 'type' => 'text', 'text' => remaining[0...match.begin(0)] } if match.begin(0).positive?
              # Add bold text
              result << {
                'type' => 'text',
                'marks' => [{ 'type' => 'strong' }],
                'text' => match[1]
              }
              remaining = remaining[match.end(0)..]
            # Try to match italic (*text* or _text_) - but not ** or __
            elsif (match = remaining.match(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/) || remaining.match(/(?<!_)_(?!_)(.+?)(?<!_)_(?!_)/))
              # Add text before match
              result << { 'type' => 'text', 'text' => remaining[0...match.begin(0)] } if match.begin(0).positive?
              # Add italic text
              result << {
                'type' => 'text',
                'marks' => [{ 'type' => 'em' }],
                'text' => match[1]
              }
              remaining = remaining[match.end(0)..]
            else
              # No more formatting, add remaining text
              result << { 'type' => 'text', 'text' => remaining }
              remaining = nil
            end
          end

          result.empty? ? [{ 'type' => 'text', 'text' => text }] : result
        end
      end
    end
  end
end
