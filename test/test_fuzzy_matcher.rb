# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/smartsuite/fuzzy_matcher'

class TestFuzzyMatcher < Minitest::Test
  # Test exact matches
  def test_exact_match
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos de software', 'Desarrollos de software')
    assert SmartSuite::FuzzyMatcher.match?('Test', 'Test')
  end

  # Test case insensitive matching
  def test_case_insensitive
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos de software', 'desarrollos de software')
    assert SmartSuite::FuzzyMatcher.match?('GESTIÓN', 'gestion')
  end

  # Test partial substring matching
  def test_substring_match
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos de software', 'desarrollo')
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos de software', 'software')
    assert SmartSuite::FuzzyMatcher.match?('Gestión de Proyectos', 'proyectos')
  end

  # Test accent normalization
  def test_accent_normalization
    assert SmartSuite::FuzzyMatcher.match?('Gestión', 'gestion')
    assert SmartSuite::FuzzyMatcher.match?('Contraloría', 'contraloria')
    assert SmartSuite::FuzzyMatcher.match?('Transformación Digital', 'transformacion')
  end

  # Test typo tolerance (1 character difference)
  def test_single_typo_tolerance
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos', 'desarollos')  # extra 'l'
    assert SmartSuite::FuzzyMatcher.match?('Finanzas', 'finanzs')        # missing 'a'
    assert SmartSuite::FuzzyMatcher.match?('Proyectos', 'proyetos')      # 'c' -> 't'
  end

  # Test typo tolerance (2 character difference)
  def test_double_typo_tolerance
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos', 'desarolos')  # missing 'l' twice
  end

  # Test multi-word queries
  def test_multi_word_query
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos de software', 'desarrollo software')
    assert SmartSuite::FuzzyMatcher.match?('Gestión de Proyectos', 'gestion proyectos')
  end

  # Test non-matches
  def test_non_matches
    refute SmartSuite::FuzzyMatcher.match?('Desarrollos de software', 'finanzas')
    refute SmartSuite::FuzzyMatcher.match?('Gestión de Proyectos', 'marketing')
    refute SmartSuite::FuzzyMatcher.match?('System', 'completely different')
  end

  # Test empty query (should match everything)
  def test_empty_query
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos de software', '')
    assert SmartSuite::FuzzyMatcher.match?('Anything', nil)
  end

  # Test empty target (should not match)
  def test_empty_target
    refute SmartSuite::FuzzyMatcher.match?('', 'query')
    refute SmartSuite::FuzzyMatcher.match?(nil, 'query')
  end

  # Test very short strings (allows 1 typo)
  def test_short_strings
    assert SmartSuite::FuzzyMatcher.match?('IT', 'it')
    assert SmartSuite::FuzzyMatcher.match?('TD', 'td')
    assert SmartSuite::FuzzyMatcher.match?('IT', 'at')  # 1 character difference allowed
    refute SmartSuite::FuzzyMatcher.match?('IT', 'xy')  # Completely different
  end

  # Test Spanish solution names from actual data
  def test_real_spanish_solution_names
    assert SmartSuite::FuzzyMatcher.match?('Desarrollos de software', 'desarollo')
    assert SmartSuite::FuzzyMatcher.match?('Gestión de Iniciativas', 'gestion')
    assert SmartSuite::FuzzyMatcher.match?('Transformación Digital', 'transformacion digital')
    assert SmartSuite::FuzzyMatcher.match?('Contraloría', 'contraloria')
    assert SmartSuite::FuzzyMatcher.match?('Finanzas', 'finanza')
  end

  # Test word-by-word matching
  def test_word_by_word_matching
    assert SmartSuite::FuzzyMatcher.match?('Gestión de Iniciativas', 'iniciativas')
    assert SmartSuite::FuzzyMatcher.match?('Portal de Servicios de Contraloría', 'servicios')
    assert SmartSuite::FuzzyMatcher.match?('OneHR', 'onehr')
  end
end
