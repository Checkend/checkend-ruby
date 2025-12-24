# frozen_string_literal: true

require 'test_helper'

# Custom exceptions for testing
class CustomNotFoundError < StandardError; end
class AnotherCustomError < StandardError; end

class IgnoreFilterTest < Minitest::Test
  def test_ignores_by_exact_class_name
    config = Checkend::Configuration.new
    config.ignored_exceptions = ['CustomNotFoundError']
    filter = Checkend::Filters::IgnoreFilter.new(config)

    exception = CustomNotFoundError.new('Not found')

    assert filter.ignore?(exception)
  end

  def test_does_not_ignore_different_class
    config = Checkend::Configuration.new
    config.ignored_exceptions = ['CustomNotFoundError']
    filter = Checkend::Filters::IgnoreFilter.new(config)

    exception = AnotherCustomError.new('Other error')

    refute filter.ignore?(exception)
  end

  def test_ignores_by_ancestor_class_name
    config = Checkend::Configuration.new
    config.ignored_exceptions = ['StandardError']
    filter = Checkend::Filters::IgnoreFilter.new(config)

    exception = CustomNotFoundError.new('Not found')

    assert filter.ignore?(exception)
  end

  def test_ignores_by_class_object
    config = Checkend::Configuration.new
    config.ignored_exceptions = [CustomNotFoundError]
    filter = Checkend::Filters::IgnoreFilter.new(config)

    exception = CustomNotFoundError.new('Not found')

    assert filter.ignore?(exception)
  end

  def test_ignores_by_regexp
    config = Checkend::Configuration.new
    config.ignored_exceptions = [/NotFound/]
    filter = Checkend::Filters::IgnoreFilter.new(config)

    exception = CustomNotFoundError.new('Not found')

    assert filter.ignore?(exception)
  end

  def test_regexp_does_not_match_different_class
    config = Checkend::Configuration.new
    config.ignored_exceptions = [/NotFound/]
    filter = Checkend::Filters::IgnoreFilter.new(config)

    exception = AnotherCustomError.new('Other error')

    refute filter.ignore?(exception)
  end

  def test_ignores_with_multiple_patterns
    config = Checkend::Configuration.new
    config.ignored_exceptions = ['AnotherCustomError', /NotFound/]
    filter = Checkend::Filters::IgnoreFilter.new(config)

    assert filter.ignore?(CustomNotFoundError.new('test'))
    assert filter.ignore?(AnotherCustomError.new('test'))
    refute filter.ignore?(RuntimeError.new('test'))
  end

  def test_empty_ignored_exceptions_ignores_nothing
    config = Checkend::Configuration.new
    config.ignored_exceptions = []
    filter = Checkend::Filters::IgnoreFilter.new(config)

    exception = StandardError.new('test')

    refute filter.ignore?(exception)
  end

  def test_ignores_subclass_when_parent_is_ignored
    config = Checkend::Configuration.new
    config.ignored_exceptions = [StandardError]
    filter = Checkend::Filters::IgnoreFilter.new(config)

    # RuntimeError is a subclass of StandardError
    exception = RuntimeError.new('test')

    assert filter.ignore?(exception)
  end

  def test_does_not_ignore_parent_when_child_is_ignored
    config = Checkend::Configuration.new
    config.ignored_exceptions = [RuntimeError]
    filter = Checkend::Filters::IgnoreFilter.new(config)

    # StandardError is a parent of RuntimeError
    exception = StandardError.new('test')

    refute filter.ignore?(exception)
  end
end
