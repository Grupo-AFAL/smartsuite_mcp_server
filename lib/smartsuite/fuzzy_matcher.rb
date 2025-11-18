# frozen_string_literal: true

module SmartSuite
  # FuzzyMatcher provides fuzzy string matching with typo tolerance.
  #
  # Supports:
  # - Case-insensitive matching
  # - Partial substring matching
  # - Typo tolerance using Levenshtein distance
  #
  # @example Basic usage
  #   FuzzyMatcher.match?("Desarrollos", "desarrollo")  # => true
  #   FuzzyMatcher.match?("Desarrollos", "desarollo")   # => true (1 typo)
  #   FuzzyMatcher.match?("Desarrollos", "project")     # => false
  module FuzzyMatcher
    # Minimum similarity score (0.0 to 1.0) to consider a match
    # Lower = more tolerant of typos, Higher = stricter matching
    DEFAULT_THRESHOLD = 0.6

    # Maximum allowed edit distance for exact word matching
    MAX_EDIT_DISTANCE = 2

    # Check if target matches the query using fuzzy matching
    #
    # @param target [String] The string to search in (e.g., solution name)
    # @param query [String] The search query (e.g., user input)
    # @param threshold [Float] Minimum similarity score (0.0 to 1.0)
    # @return [Boolean] true if query matches target
    #
    # @example
    #   FuzzyMatcher.match?("Gestión de Proyectos", "gestion")      # => true
    #   FuzzyMatcher.match?("Gestión de Proyectos", "proyectos")    # => true
    #   FuzzyMatcher.match?("Gestión de Proyectos", "gestin")       # => true (1 typo)
    #   FuzzyMatcher.match?("Gestión de Proyectos", "finance")      # => false
    def self.match?(target, query, threshold: DEFAULT_THRESHOLD)
      return true if query.nil? || query.empty?
      return false if target.nil? || target.empty?

      # Normalize strings (downcase, remove accents for comparison)
      normalized_target = normalize(target)
      normalized_query = normalize(query)

      # Strategy 1: Direct substring match (highest priority)
      return true if normalized_target.include?(normalized_query)

      # Strategy 2: Word-by-word matching (for multi-word queries)
      query_words = normalized_query.split(/\s+/)
      target_words = normalized_target.split(/\s+/)

      # Check if all query words match at least one target word
      query_words.all? do |query_word|
        target_words.any? do |target_word|
          # Exact substring match
          target_word.include?(query_word) ||
            # Or close enough (typo tolerance)
            similar_enough?(target_word, query_word, threshold)
        end
      end
    end

    # Calculate similarity score between two strings
    #
    # @param str1 [String] First string
    # @param str2 [String] Second string
    # @return [Float] Similarity score (0.0 to 1.0)
    def self.similarity(str1, str2)
      return 1.0 if str1 == str2
      return 0.0 if str1.empty? || str2.empty?

      distance = levenshtein_distance(str1, str2)
      max_length = [str1.length, str2.length].max

      # Convert distance to similarity score (0.0 = completely different, 1.0 = identical)
      1.0 - (distance.to_f / max_length)
    end

    # Check if two strings are similar enough based on threshold
    #
    # @param str1 [String] First string
    # @param str2 [String] Second string
    # @param threshold [Float] Minimum similarity score
    # @return [Boolean] true if similar enough
    def self.similar_enough?(str1, str2, threshold = DEFAULT_THRESHOLD)
      # For very short strings, require exact match or very close
      return str1 == str2 || levenshtein_distance(str1, str2) <= 1 if str1.length <= 3 || str2.length <= 3

      # For longer strings, use edit distance with threshold
      distance = levenshtein_distance(str1, str2)
      distance <= MAX_EDIT_DISTANCE || similarity(str1, str2) >= threshold
    end

    # Calculate Levenshtein distance (minimum edits to transform str1 to str2)
    #
    # @param str1 [String] First string
    # @param str2 [String] Second string
    # @return [Integer] Edit distance
    def self.levenshtein_distance(str1, str2)
      return str2.length if str1.empty?
      return str1.length if str2.empty?

      # Create matrix for dynamic programming
      matrix = Array.new(str1.length + 1) { Array.new(str2.length + 1) }

      # Initialize first row and column
      (0..str1.length).each { |i| matrix[i][0] = i }
      (0..str2.length).each { |j| matrix[0][j] = j }

      # Fill in the matrix
      (1..str1.length).each do |i|
        (1..str2.length).each do |j|
          cost = str1[i - 1] == str2[j - 1] ? 0 : 1

          matrix[i][j] = [
            matrix[i - 1][j] + 1,      # Deletion
            matrix[i][j - 1] + 1,      # Insertion
            matrix[i - 1][j - 1] + cost # Substitution
          ].min
        end
      end

      matrix[str1.length][str2.length]
    end

    # Normalize string for comparison (lowercase, remove accents)
    #
    # @param str [String] String to normalize
    # @return [String] Normalized string
    def self.normalize(str)
      # Convert to lowercase
      normalized = str.downcase

      # Remove common Spanish accents for better matching
      accent_map = {
        'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u',
        'ñ' => 'n', 'ü' => 'u',
        'Á' => 'a', 'É' => 'e', 'Í' => 'i', 'Ó' => 'o', 'Ú' => 'u',
        'Ñ' => 'n', 'Ü' => 'u'
      }

      accent_map.each { |accented, plain| normalized.gsub!(accented, plain) }

      normalized
    end

    private_class_method :similarity, :similar_enough?, :levenshtein_distance, :normalize
  end
end
