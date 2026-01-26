# frozen_string_literal: true

require 'test_helper'
require 'checkend/integrations/rails/csrf_subscriber'

class CsrfSubscriberTest < Minitest::Test
  include CheckendTestHelper

  def setup
    super
    @subscriber = Checkend::Integrations::Rails::CsrfSubscriber.new
  end

  # ========== Configuration Tests ==========

  def test_capture_csrf_events_default_is_false
    refute Checkend.configuration.capture_csrf_events
  end

  def test_capture_csrf_events_can_be_set_to_blocked
    configure_checkend(capture_csrf_events: :blocked)

    assert_equal :blocked, Checkend.configuration.capture_csrf_events
  end

  def test_capture_csrf_events_can_be_set_to_all
    configure_checkend(capture_csrf_events: :all)

    assert_equal :all, Checkend.configuration.capture_csrf_events
  end

  # ========== should_capture? Tests ==========

  def test_should_capture_returns_false_when_disabled
    configure_checkend(capture_csrf_events: false)

    refute @subscriber.send(:should_capture?, :fallback)
    refute @subscriber.send(:should_capture?, :blocked)
  end

  def test_should_capture_returns_true_for_all_levels_when_all
    configure_checkend(capture_csrf_events: :all)

    assert @subscriber.send(:should_capture?, :fallback)
    assert @subscriber.send(:should_capture?, :blocked)
  end

  def test_should_capture_only_blocked_when_blocked
    configure_checkend(capture_csrf_events: :blocked)

    refute @subscriber.send(:should_capture?, :fallback)
    assert @subscriber.send(:should_capture?, :blocked)
  end

  def test_should_capture_handles_string_setting
    Checkend.configure do |config|
      config.api_key = VALID_API_KEY
      config.endpoint = TEST_ENDPOINT
      config.environment = 'test'
      config.enabled = true
      config.async = false
      config.capture_csrf_events = 'all'
    end

    assert @subscriber.send(:should_capture?, :fallback)
    assert @subscriber.send(:should_capture?, :blocked)
  end

  # ========== Event Handling Tests ==========

  def test_handle_event_does_nothing_when_disabled
    configure_checkend(capture_csrf_events: false)
    stub_ingest_api

    payload = build_payload

    @subscriber.handle_event('csrf_request_blocked.action_controller', :blocked, payload)

    assert_not_requested :post, "#{TEST_ENDPOINT}/ingest/v1/errors"
  end

  def test_handle_event_captures_blocked_event
    configure_checkend(capture_csrf_events: :blocked)
    stub = stub_ingest_api

    payload = build_payload(message: 'CSRF token verification failed')

    @subscriber.handle_event('csrf_request_blocked.action_controller', :blocked, payload)

    assert_requested stub
  end

  def test_handle_event_captures_javascript_blocked_event
    configure_checkend(capture_csrf_events: :blocked)
    stub = stub_ingest_api

    payload = build_payload(message: 'Cross-origin JavaScript blocked')

    @subscriber.handle_event('csrf_javascript_blocked.action_controller', :blocked, payload)

    assert_requested stub
  end

  def test_handle_event_skips_fallback_when_blocked_setting
    configure_checkend(capture_csrf_events: :blocked)
    stub_ingest_api

    payload = build_payload

    @subscriber.handle_event('csrf_token_fallback.action_controller', :fallback, payload)

    assert_not_requested :post, "#{TEST_ENDPOINT}/ingest/v1/errors"
  end

  def test_handle_event_captures_fallback_when_all_setting
    configure_checkend(capture_csrf_events: :all)
    stub = stub_ingest_api

    payload = build_payload(message: 'Falling back to session CSRF token')

    @subscriber.handle_event('csrf_token_fallback.action_controller', :fallback, payload)

    assert_requested stub
  end

  # ========== Notice Building Tests ==========

  def test_build_notice_creates_proper_structure
    configure_checkend(capture_csrf_events: :blocked)

    payload = build_payload(
      controller: 'SessionsController',
      action: 'create',
      message: 'CSRF verification failed',
      sec_fetch_site: 'cross-site'
    )

    notice = @subscriber.send(:build_notice, 'csrf_request_blocked.action_controller', payload)

    assert_equal 'Checkend::Security::CsrfRequestBlocked', notice.error_class
    assert_equal 'CSRF verification failed', notice.message
    assert_includes notice.tags, 'csrf'
    assert_includes notice.tags, 'security_event'
    assert_equal 'csrf:csrf_request_blocked:SessionsController:create', notice.fingerprint
    assert_equal 'SessionsController', notice.context[:controller]
    assert_equal 'create', notice.context[:action]
    assert_equal 'cross-site', notice.context[:sec_fetch_site]
  end

  def test_build_notice_for_fallback_event
    configure_checkend(capture_csrf_events: :all)

    payload = build_payload(message: 'Falling back to session token')

    notice = @subscriber.send(:build_notice, 'csrf_token_fallback.action_controller', payload)

    assert_equal 'Checkend::Security::CsrfTokenFallback', notice.error_class
  end

  def test_build_notice_for_javascript_blocked_event
    configure_checkend(capture_csrf_events: :blocked)

    payload = build_payload(message: 'Cross-origin JavaScript blocked')

    notice = @subscriber.send(:build_notice, 'csrf_javascript_blocked.action_controller', payload)

    assert_equal 'Checkend::Security::CsrfJavascriptBlocked', notice.error_class
  end

  def test_build_notice_handles_missing_message
    configure_checkend(capture_csrf_events: :blocked)

    payload = build_payload(message: nil)

    notice = @subscriber.send(:build_notice, 'csrf_request_blocked.action_controller', payload)

    assert_equal 'CSRF security event', notice.message
  end

  def test_build_notice_handles_missing_controller_and_action
    configure_checkend(capture_csrf_events: :blocked)

    payload = { message: 'Test' }

    notice = @subscriber.send(:build_notice, 'csrf_request_blocked.action_controller', payload)

    assert_equal 'csrf:csrf_request_blocked:unknown:unknown', notice.fingerprint
  end

  # ========== Request Data Tests ==========

  def test_build_request_data_extracts_request_info
    configure_checkend(capture_csrf_events: :blocked)

    mock_request = MockRequest.new(
      original_url: 'https://example.com/login',
      request_method: 'POST',
      remote_ip: '192.168.1.1',
      user_agent: 'Mozilla/5.0'
    )

    payload = build_payload(request: mock_request)

    request_data = @subscriber.send(:build_request_data, payload)

    assert_equal 'https://example.com/login', request_data[:url]
    assert_equal 'POST', request_data[:method]
    assert_equal '192.168.1.1', request_data[:remote_ip]
    assert_equal 'Mozilla/5.0', request_data[:user_agent]
  end

  def test_build_request_data_handles_missing_request
    configure_checkend(capture_csrf_events: :blocked)

    payload = build_payload(request: nil)

    request_data = @subscriber.send(:build_request_data, payload)

    assert_empty(request_data)
  end

  def test_build_request_data_handles_request_errors
    configure_checkend(capture_csrf_events: :blocked)

    mock_request = Object.new
    def mock_request.original_url
      raise StandardError, 'Cannot get URL'
    end

    payload = build_payload(request: mock_request)

    request_data = @subscriber.send(:build_request_data, payload)

    # Should not raise, and should have nil for URL
    assert_nil request_data[:url]
  end

  # ========== Rails Version Check Tests ==========

  def test_rails_supports_csrf_events_returns_false_without_rails
    # Remove Rails constant temporarily if it exists
    original_rails = Object.const_defined?(:Rails) ? Object.send(:remove_const, :Rails) : nil

    refute_predicate Checkend::Integrations::Rails::CsrfSubscriber, :rails_supports_csrf_events?
  ensure
    Object.const_set(:Rails, original_rails) if original_rails
  end

  def test_rails_supports_csrf_events_returns_false_for_old_rails
    mock_rails_version('7.1.0')

    refute_predicate Checkend::Integrations::Rails::CsrfSubscriber, :rails_supports_csrf_events?
  ensure
    remove_mock_rails
  end

  def test_rails_supports_csrf_events_returns_true_for_rails_eight_two
    mock_rails_version('8.2.0')

    assert_predicate Checkend::Integrations::Rails::CsrfSubscriber, :rails_supports_csrf_events?
  ensure
    remove_mock_rails
  end

  def test_rails_supports_csrf_events_returns_true_for_rails_above_eight_two
    mock_rails_version('9.0.0')

    assert_predicate Checkend::Integrations::Rails::CsrfSubscriber, :rails_supports_csrf_events?
  ensure
    remove_mock_rails
  end

  # ========== before_notify Callback Tests ==========

  def test_before_notify_can_prevent_sending
    configure_checkend(capture_csrf_events: :blocked)
    Checkend.configuration.before_notify << ->(_notice) { false }

    stub_ingest_api

    payload = build_payload

    @subscriber.handle_event('csrf_request_blocked.action_controller', :blocked, payload)

    assert_not_requested :post, "#{TEST_ENDPOINT}/ingest/v1/errors"
  end

  def test_before_notify_can_modify_notice
    configure_checkend(capture_csrf_events: :blocked)

    modified_tags = nil
    Checkend.configuration.before_notify << lambda { |notice|
      notice.tags << 'modified'
      modified_tags = notice.tags.dup
      true
    }

    stub_ingest_api

    payload = build_payload

    @subscriber.handle_event('csrf_request_blocked.action_controller', :blocked, payload)

    assert_includes modified_tags, 'modified'
    assert_includes modified_tags, 'csrf'
  end

  # ========== Error Handling Tests ==========

  def test_handle_event_catches_exceptions
    configure_checkend(capture_csrf_events: :blocked)

    # Make build_notice raise an error
    @subscriber.stub(:build_notice, ->(*) { raise 'Test error' }) do
      # Should not raise
      @subscriber.handle_event('csrf_request_blocked.action_controller', :blocked, {})
    end
  end

  # ========== Constants Tests ==========

  def test_events_constant_contains_expected_events
    events = Checkend::Integrations::Rails::CsrfSubscriber::EVENTS

    assert_equal :fallback, events['csrf_token_fallback.action_controller']
    assert_equal :blocked, events['csrf_request_blocked.action_controller']
    assert_equal :blocked, events['csrf_javascript_blocked.action_controller']
  end

  def test_error_classes_constant_contains_expected_classes
    classes = Checkend::Integrations::Rails::CsrfSubscriber::ERROR_CLASSES

    assert_equal 'Checkend::Security::CsrfTokenFallback',
                 classes['csrf_token_fallback.action_controller']
    assert_equal 'Checkend::Security::CsrfRequestBlocked',
                 classes['csrf_request_blocked.action_controller']
    assert_equal 'Checkend::Security::CsrfJavascriptBlocked',
                 classes['csrf_javascript_blocked.action_controller']
  end

  private

  def build_payload(controller: 'TestController', action: 'test', message: 'Test message',
                    sec_fetch_site: 'same-origin', request: nil)
    {
      controller: controller,
      action: action,
      message: message,
      sec_fetch_site: sec_fetch_site,
      request: request
    }
  end

  def mock_rails_version(version)
    remove_mock_rails

    mock_version = Module.new
    mock_version.const_set(:STRING, version)

    mock_rails = Module.new
    mock_rails.const_set(:VERSION, mock_version)

    Object.const_set(:Rails, mock_rails)
  end

  def remove_mock_rails
    Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails)
  end

  # Mock request object for testing
  class MockRequest
    attr_reader :original_url, :request_method, :remote_ip, :user_agent

    def initialize(original_url: nil, request_method: nil, remote_ip: nil, user_agent: nil)
      @original_url = original_url
      @request_method = request_method
      @remote_ip = remote_ip
      @user_agent = user_agent
    end
  end
end
