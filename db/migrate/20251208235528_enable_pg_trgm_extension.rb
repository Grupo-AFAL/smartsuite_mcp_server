# frozen_string_literal: true

# Enable pg_trgm extension for fuzzy text search with typo tolerance
# This extension provides:
# - similarity() function: Returns similarity score (0-1) between two strings
# - word_similarity(): Better for word-level matching
# - % operator: Returns true if similarity > pg_trgm.similarity_threshold
# - <-> operator: Returns "distance" (1 - similarity) for ORDER BY
# - GIN/GiST index support for fast trigram-based searches
class EnablePgTrgmExtension < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pg_trgm"
  end

  def down
    disable_extension "pg_trgm"
  end
end
