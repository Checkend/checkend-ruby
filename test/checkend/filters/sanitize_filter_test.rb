# frozen_string_literal: true

require 'test_helper'

class SanitizeFilterTest < Minitest::Test
  def setup
    @config = Checkend::Configuration.new
    @config.filter_keys = %w[password secret token api_key]
    @filter = Checkend::Filters::SanitizeFilter.new(@config)
  end

  def test_filters_password_key
    data = { username: 'john', password: 'secret123' }
    result = @filter.call(data)

    assert_equal 'john', result[:username]
    assert_equal '[FILTERED]', result[:password]
  end

  def test_filters_nested_keys
    data = {
      user: {
        name: 'John',
        credentials: {
          password: 'secret123',
          token: 'abc123'
        }
      }
    }
    result = @filter.call(data)

    assert_equal 'John', result[:user][:name]
    assert_equal '[FILTERED]', result[:user][:credentials][:password]
    assert_equal '[FILTERED]', result[:user][:credentials][:token]
  end

  def test_filters_keys_case_insensitively
    data = { PASSWORD: 'secret', Password: 'secret2', pAsSwOrD: 'secret3' }
    result = @filter.call(data)

    assert_equal '[FILTERED]', result[:PASSWORD]
    assert_equal '[FILTERED]', result[:Password]
    assert_equal '[FILTERED]', result[:pAsSwOrD]
  end

  def test_filters_partial_key_matches
    data = { user_password: 'secret', password_hash: 'hash', my_secret_key: 'value' }
    result = @filter.call(data)

    assert_equal '[FILTERED]', result[:user_password]
    assert_equal '[FILTERED]', result[:password_hash]
    assert_equal '[FILTERED]', result[:my_secret_key]
  end

  def test_filters_string_keys
    data = { 'password' => 'secret', 'username' => 'john' }
    result = @filter.call(data)

    assert_equal '[FILTERED]', result['password']
    assert_equal 'john', result['username']
  end

  def test_filters_in_arrays
    data = {
      users: [
        { name: 'John', password: 'pass1' },
        { name: 'Jane', password: 'pass2' }
      ]
    }
    result = @filter.call(data)

    assert_equal 'John', result[:users][0][:name]
    assert_equal '[FILTERED]', result[:users][0][:password]
    assert_equal 'Jane', result[:users][1][:name]
    assert_equal '[FILTERED]', result[:users][1][:password]
  end

  def test_truncates_long_strings
    long_string = 'a' * 15_000
    data = { message: long_string }
    result = @filter.call(data)

    assert_operator result[:message].length, :<, long_string.length
    assert result[:message].end_with?('[TRUNCATED]')
  end

  def test_does_not_modify_original_data
    original = { password: 'secret', name: 'John' }
    original_password = original[:password]

    @filter.call(original)

    assert_equal original_password, original[:password]
  end

  def test_handles_nil_values
    data = { password: nil, name: 'John' }
    result = @filter.call(data)

    assert_equal '[FILTERED]', result[:password]
    assert_equal 'John', result[:name]
  end

  def test_handles_empty_hash
    data = {}
    result = @filter.call(data)

    assert_empty result
  end

  def test_handles_deeply_nested_structures
    data = { a: { b: { c: { d: { e: { f: { g: { h: { i: { j: { k: 'deep' } } } } } } } } } } }
    result = @filter.call(data)

    # Should hit max depth and return [FILTERED]
    assert_kind_of Hash, result
  end

  def test_preserves_non_sensitive_data
    data = {
      id: 123,
      name: 'Product',
      price: 99.99,
      active: true,
      tags: %w[sale featured]
    }
    result = @filter.call(data)

    assert_equal 123, result[:id]
    assert_equal 'Product', result[:name]
    assert_in_delta(99.99, result[:price])
    assert result[:active]
    assert_equal %w[sale featured], result[:tags]
  end

  def test_handles_empty_filter_keys
    @config.filter_keys = []
    filter = Checkend::Filters::SanitizeFilter.new(@config)

    data = { password: 'secret' }
    result = filter.call(data)

    assert_equal 'secret', result[:password]
  end

  def test_filters_api_key
    data = { api_key: 'sk_live_123', endpoint: 'https://api.example.com' }
    result = @filter.call(data)

    assert_equal '[FILTERED]', result[:api_key]
    assert_equal 'https://api.example.com', result[:endpoint]
  end
end
