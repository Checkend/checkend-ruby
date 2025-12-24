# frozen_string_literal: true

require 'test_helper'

class ConfigurationTest < Minitest::Test
  def setup
    # Clear environment variables
    ENV.delete('CHECKEND_API_KEY')
    ENV.delete('CHECKEND_ENDPOINT')
    ENV.delete('CHECKEND_ENVIRONMENT')
    ENV.delete('CHECKEND_DEBUG')
    ENV.delete('RAILS_ENV')
    ENV.delete('RACK_ENV')
  end

  def test_default_values
    config = Checkend::Configuration.new

    assert_nil config.api_key
    assert_equal 'https://app.checkend.io', config.endpoint
    assert_equal 'development', config.environment
    assert_equal 15, config.timeout
    assert_equal 5, config.open_timeout
    assert config.ssl_verify
    assert config.send_request_data
    assert config.async
    assert_equal 1000, config.max_queue_size
    refute config.debug
  end

  def test_api_key_from_env
    ENV['CHECKEND_API_KEY'] = 'env_api_key'
    config = Checkend::Configuration.new

    assert_equal 'env_api_key', config.api_key
  end

  def test_endpoint_from_env
    ENV['CHECKEND_ENDPOINT'] = 'https://custom.checkend.io'
    config = Checkend::Configuration.new

    assert_equal 'https://custom.checkend.io', config.endpoint
  end

  def test_environment_from_checkend_env
    ENV['CHECKEND_ENVIRONMENT'] = 'staging'
    config = Checkend::Configuration.new

    assert_equal 'staging', config.environment
  end

  def test_environment_from_rails_env
    ENV['RAILS_ENV'] = 'production'
    config = Checkend::Configuration.new

    assert_equal 'production', config.environment
  end

  def test_environment_from_rack_env
    ENV['RACK_ENV'] = 'test'
    config = Checkend::Configuration.new

    assert_equal 'test', config.environment
  end

  def test_checkend_environment_takes_precedence
    ENV['CHECKEND_ENVIRONMENT'] = 'staging'
    ENV['RAILS_ENV'] = 'production'
    ENV['RACK_ENV'] = 'test'
    config = Checkend::Configuration.new

    assert_equal 'staging', config.environment
  end

  def test_valid_with_api_key_and_endpoint
    config = Checkend::Configuration.new
    config.api_key = 'test_key'
    config.endpoint = 'https://example.com'

    assert_predicate config, :valid?
  end

  def test_invalid_without_api_key
    config = Checkend::Configuration.new
    config.endpoint = 'https://example.com'

    refute_predicate config, :valid?
  end

  def test_invalid_with_empty_api_key
    config = Checkend::Configuration.new
    config.api_key = ''
    config.endpoint = 'https://example.com'

    refute_predicate config, :valid?
  end

  def test_enabled_true_in_production
    config = Checkend::Configuration.new
    config.environment = 'production'

    assert_predicate config, :enabled?
  end

  def test_enabled_true_in_staging
    config = Checkend::Configuration.new
    config.environment = 'staging'

    assert_predicate config, :enabled?
  end

  def test_enabled_false_in_development
    config = Checkend::Configuration.new
    config.environment = 'development'

    refute_predicate config, :enabled?
  end

  def test_enabled_false_in_test
    config = Checkend::Configuration.new
    config.environment = 'test'

    refute_predicate config, :enabled?
  end

  def test_explicit_enabled_overrides_environment
    config = Checkend::Configuration.new
    config.environment = 'development'
    config.enabled = true

    assert_predicate config, :enabled?
  end

  def test_explicit_disabled_overrides_environment
    config = Checkend::Configuration.new
    config.environment = 'production'
    config.enabled = false

    refute_predicate config, :enabled?
  end

  def test_ignore_exception_by_class_name
    config = Checkend::Configuration.new
    config.ignored_exceptions = ['StandardError']

    exception = StandardError.new('test')

    assert config.ignore_exception?(exception)
  end

  def test_ignore_exception_by_ancestor_class_name
    config = Checkend::Configuration.new
    config.ignored_exceptions = ['StandardError']

    exception = RuntimeError.new('test')

    assert config.ignore_exception?(exception)
  end

  def test_ignore_exception_by_class
    config = Checkend::Configuration.new
    config.ignored_exceptions = [StandardError]

    exception = StandardError.new('test')

    assert config.ignore_exception?(exception)
  end

  def test_ignore_exception_by_regexp
    config = Checkend::Configuration.new
    config.ignored_exceptions = [/NotFound/]

    # Create a custom exception class
    not_found_class = Class.new(StandardError)
    Object.const_set(:RecordNotFoundError, not_found_class) unless defined?(RecordNotFoundError)

    exception = RecordNotFoundError.new('test')

    assert config.ignore_exception?(exception)
  end

  def test_does_not_ignore_unknown_exception
    config = Checkend::Configuration.new
    config.ignored_exceptions = ['SomeOtherError']

    exception = StandardError.new('test')

    refute config.ignore_exception?(exception)
  end

  def test_default_filter_keys
    config = Checkend::Configuration.new

    assert_includes config.filter_keys, 'password'
    assert_includes config.filter_keys, 'secret'
    assert_includes config.filter_keys, 'token'
    assert_includes config.filter_keys, 'api_key'
    assert_includes config.filter_keys, 'credit_card'
  end

  def test_default_ignored_exceptions
    config = Checkend::Configuration.new

    assert_includes config.ignored_exceptions, 'ActiveRecord::RecordNotFound'
    assert_includes config.ignored_exceptions, 'ActionController::RoutingError'
  end

  def test_debug_from_env
    ENV['CHECKEND_DEBUG'] = 'true'
    config = Checkend::Configuration.new

    assert config.debug
  end

  def test_resolved_logger_returns_default_when_not_set
    config = Checkend::Configuration.new

    assert_instance_of Logger, config.resolved_logger
  end

  def test_resolved_logger_returns_custom_when_set
    config = Checkend::Configuration.new
    custom_logger = Logger.new($stderr)
    config.logger = custom_logger

    assert_same custom_logger, config.resolved_logger
  end
end
