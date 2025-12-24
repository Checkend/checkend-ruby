# frozen_string_literal: true

require 'test_helper'

class NoticeTest < Minitest::Test
  def test_default_values
    notice = Checkend::Notice.new

    assert_empty notice.backtrace
    assert_empty notice.tags
    assert_empty(notice.context)
    assert_empty(notice.request)
    assert_empty(notice.user)
    assert_empty notice.breadcrumbs
    refute_nil notice.occurred_at
  end

  def test_occurred_at_is_iso8601
    notice = Checkend::Notice.new

    # Should be a valid ISO8601 timestamp
    assert_match(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, notice.occurred_at)
  end

  def test_to_h_includes_error_payload
    notice = Checkend::Notice.new
    notice.error_class = 'NoMethodError'
    notice.message = 'undefined method'
    notice.backtrace = ['app/models/user.rb:42']

    hash = notice.to_h

    assert_equal 'NoMethodError', hash[:error][:class]
    assert_equal 'undefined method', hash[:error][:message]
    assert_equal ['app/models/user.rb:42'], hash[:error][:backtrace]
  end

  def test_to_h_includes_fingerprint_when_set
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.fingerprint = 'custom-fingerprint'

    hash = notice.to_h

    assert_equal 'custom-fingerprint', hash[:error][:fingerprint]
  end

  def test_to_h_excludes_fingerprint_when_nil
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'

    hash = notice.to_h

    refute hash[:error].key?(:fingerprint)
  end

  def test_to_h_includes_tags_when_set
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.tags = %w[checkout payment]

    hash = notice.to_h

    assert_equal %w[checkout payment], hash[:error][:tags]
  end

  def test_to_h_excludes_tags_when_empty
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.tags = []

    hash = notice.to_h

    refute hash[:error].key?(:tags)
  end

  def test_to_h_includes_context
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.context = { user_id: 123, feature: 'checkout' }

    hash = notice.to_h

    assert_equal 123, hash[:context][:user_id]
    assert_equal 'checkout', hash[:context][:feature]
  end

  def test_to_h_includes_environment_in_context
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.environment = 'production'
    notice.context = { user_id: 123 }

    hash = notice.to_h

    assert_equal 'production', hash[:context][:environment]
    assert_equal 123, hash[:context][:user_id]
  end

  def test_to_h_includes_request
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.request = { url: 'https://example.com', method: 'POST' }

    hash = notice.to_h

    assert_equal 'https://example.com', hash[:request][:url]
    assert_equal 'POST', hash[:request][:method]
  end

  def test_to_h_includes_user
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.user = { id: 456, email: 'test@example.com' }

    hash = notice.to_h

    assert_equal 456, hash[:user][:id]
    assert_equal 'test@example.com', hash[:user][:email]
  end

  def test_to_h_includes_breadcrumbs
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.breadcrumbs = [
      { message: 'User clicked', category: 'ui', timestamp: '2025-01-01T00:00:00Z' }
    ]

    hash = notice.to_h

    assert_equal 1, hash[:breadcrumbs].length
    assert_equal 'User clicked', hash[:breadcrumbs][0][:message]
  end

  def test_to_h_includes_notifier
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'

    hash = notice.to_h

    assert_equal 'checkend-ruby', hash[:notifier][:name]
    assert_equal Checkend::VERSION, hash[:notifier][:version]
    assert_equal 'ruby', hash[:notifier][:language]
    assert_equal RUBY_VERSION, hash[:notifier][:language_version]
  end

  def test_to_json_returns_valid_json
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'
    notice.message = 'Test message'

    json = notice.to_json
    parsed = JSON.parse(json)

    assert_equal 'TestError', parsed['error']['class']
    assert_equal 'Test message', parsed['error']['message']
  end
end
