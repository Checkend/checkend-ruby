# frozen_string_literal: true

require 'test_helper'

class NoticeBuilderTest < Minitest::Test
  include CheckendTestHelper

  def setup
    super
    configure_checkend
  end

  def test_builds_notice_from_exception
    exception = sample_exception

    notice = Checkend::NoticeBuilder.build(exception: exception)

    assert_equal 'StandardError', notice.error_class
    assert_equal 'Test error message', notice.message
  end

  def test_builds_notice_with_backtrace
    exception = sample_exception_with_backtrace

    notice = Checkend::NoticeBuilder.build(exception: exception)

    assert_instance_of Array, notice.backtrace
    refute_empty notice.backtrace
    assert_includes notice.backtrace.first, 'inner_method'
  end

  def test_limits_backtrace_to_max_lines
    # Create exception with huge backtrace
    exception = sample_exception
    long_backtrace = (1..200).map { |i| "file#{i}.rb:#{i}:in `method#{i}'" }
    exception.set_backtrace(long_backtrace)

    notice = Checkend::NoticeBuilder.build(exception: exception)

    assert_equal 100, notice.backtrace.length
  end

  def test_truncates_long_messages
    long_message = 'a' * 15_000
    exception = StandardError.new(long_message)

    notice = Checkend::NoticeBuilder.build(exception: exception)

    assert_equal 10_000, notice.message.length
    assert notice.message.end_with?('...')
  end

  def test_handles_nil_message
    exception = StandardError.new(nil)

    notice = Checkend::NoticeBuilder.build(exception: exception)

    # Ruby 3.x returns class name when nil is passed, we just ensure it doesn't crash
    refute_nil notice.message
  end

  def test_includes_context
    exception = sample_exception
    context = { order_id: 123, source: 'checkout' }

    notice = Checkend::NoticeBuilder.build(exception: exception, context: context)

    assert_equal 123, notice.context[:order_id]
    assert_equal 'checkout', notice.context[:source]
  end

  def test_includes_request
    exception = sample_exception
    request = { url: 'https://example.com/orders', method: 'POST' }

    notice = Checkend::NoticeBuilder.build(exception: exception, request: request)

    assert_equal 'https://example.com/orders', notice.request[:url]
    assert_equal 'POST', notice.request[:method]
  end

  def test_includes_user
    exception = sample_exception
    user = { id: 456, email: 'user@example.com' }

    notice = Checkend::NoticeBuilder.build(exception: exception, user: user)

    assert_equal 456, notice.user[:id]
    assert_equal 'user@example.com', notice.user[:email]
  end

  def test_includes_fingerprint
    exception = sample_exception

    notice = Checkend::NoticeBuilder.build(exception: exception, fingerprint: 'custom-fp')

    assert_equal 'custom-fp', notice.fingerprint
  end

  def test_includes_tags
    exception = sample_exception

    notice = Checkend::NoticeBuilder.build(exception: exception, tags: %w[urgent payment])

    assert_equal %w[urgent payment], notice.tags
  end

  def test_converts_single_tag_to_array
    exception = sample_exception

    notice = Checkend::NoticeBuilder.build(exception: exception, tags: 'single')

    assert_equal ['single'], notice.tags
  end

  def test_includes_environment
    exception = sample_exception

    notice = Checkend::NoticeBuilder.build(exception: exception)

    assert_equal 'test', notice.environment
  end

  def test_merges_thread_local_context
    exception = sample_exception
    Thread.current[:checkend_context] = { existing_key: 'value' }

    notice = Checkend::NoticeBuilder.build(exception: exception, context: { new_key: 'new' })

    assert_equal 'value', notice.context[:existing_key]
    assert_equal 'new', notice.context[:new_key]
  ensure
    Thread.current[:checkend_context] = nil
  end

  def test_provided_context_overrides_thread_local
    exception = sample_exception
    Thread.current[:checkend_context] = { key: 'thread_value' }

    notice = Checkend::NoticeBuilder.build(exception: exception, context: { key: 'provided_value' })

    assert_equal 'provided_value', notice.context[:key]
  ensure
    Thread.current[:checkend_context] = nil
  end

  def test_cleans_backtrace_with_root_path
    Checkend.configuration.root_path = '/app/myproject'
    exception = sample_exception
    exception.set_backtrace(['/app/myproject/lib/foo.rb:10:in `bar`'])

    notice = Checkend::NoticeBuilder.build(exception: exception)

    assert_equal ['[PROJECT_ROOT]/lib/foo.rb:10:in `bar`'], notice.backtrace
  end

  def test_handles_nil_backtrace
    exception = StandardError.new('test')
    # Don't set a backtrace

    notice = Checkend::NoticeBuilder.build(exception: exception)

    assert_empty notice.backtrace
  end
end
