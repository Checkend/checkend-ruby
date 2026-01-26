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

  # ========== build_from_message tests ==========

  def test_build_from_message_creates_notice
    notice = Checkend::NoticeBuilder.build_from_message('Something went wrong')

    assert_equal 'Checkend::Notice', notice.error_class
    assert_equal 'Something went wrong', notice.message
    assert_empty notice.backtrace
  end

  def test_build_from_message_with_custom_error_class
    notice = Checkend::NoticeBuilder.build_from_message(
      'Rate limit exceeded',
      error_class: 'RateLimitError'
    )

    assert_equal 'RateLimitError', notice.error_class
    assert_equal 'Rate limit exceeded', notice.message
  end

  def test_build_from_message_with_context
    notice = Checkend::NoticeBuilder.build_from_message(
      'Alert message',
      context: { severity: 'high', source: 'api' }
    )

    assert_equal 'high', notice.context[:severity]
    assert_equal 'api', notice.context[:source]
  end

  def test_build_from_message_with_user
    notice = Checkend::NoticeBuilder.build_from_message(
      'User alert',
      user: { id: 123, email: 'test@example.com' }
    )

    assert_equal 123, notice.user[:id]
    assert_equal 'test@example.com', notice.user[:email]
  end

  def test_build_from_message_with_tags
    notice = Checkend::NoticeBuilder.build_from_message(
      'Tagged alert',
      tags: %w[urgent security]
    )

    assert_equal %w[urgent security], notice.tags
  end

  def test_build_from_message_with_fingerprint
    notice = Checkend::NoticeBuilder.build_from_message(
      'Custom fingerprint',
      fingerprint: 'my-custom-fp'
    )

    assert_equal 'my-custom-fp', notice.fingerprint
  end

  def test_build_from_message_includes_environment
    notice = Checkend::NoticeBuilder.build_from_message('Test')

    assert_equal 'test', notice.environment
  end

  def test_build_from_message_truncates_long_messages
    long_message = 'a' * 15_000

    notice = Checkend::NoticeBuilder.build_from_message(long_message)

    assert_equal 10_000, notice.message.length
    assert notice.message.end_with?('...')
  end

  def test_build_from_message_merges_thread_local_context
    Thread.current[:checkend_context] = { existing: 'value' }

    notice = Checkend::NoticeBuilder.build_from_message('Test', context: { new_key: 'new' })

    assert_equal 'value', notice.context[:existing]
    assert_equal 'new', notice.context[:new_key]
  ensure
    Thread.current[:checkend_context] = nil
  end

  # ========== build_from_hash tests ==========

  def test_build_from_hash_creates_notice
    notice = Checkend::NoticeBuilder.build_from_hash(
      { error_class: 'CustomError', message: 'Something happened' }
    )

    assert_equal 'CustomError', notice.error_class
    assert_equal 'Something happened', notice.message
  end

  def test_build_from_hash_with_string_keys
    notice = Checkend::NoticeBuilder.build_from_hash(
      { 'error_class' => 'StringKeyError', 'message' => 'Using string keys' }
    )

    assert_equal 'StringKeyError', notice.error_class
    assert_equal 'Using string keys', notice.message
  end

  def test_build_from_hash_defaults_error_class
    notice = Checkend::NoticeBuilder.build_from_hash({ message: 'Just a message' })

    assert_equal 'Checkend::Notice', notice.error_class
  end

  def test_build_from_hash_with_backtrace
    notice = Checkend::NoticeBuilder.build_from_hash(
      {
        error_class: 'CustomError',
        message: 'With backtrace',
        backtrace: ['file.rb:10:in `method`', 'file.rb:20:in `caller`']
      }
    )

    assert_equal 2, notice.backtrace.length
    assert_includes notice.backtrace.first, 'file.rb:10'
  end

  def test_build_from_hash_with_fingerprint_in_hash
    notice = Checkend::NoticeBuilder.build_from_hash(
      { error_class: 'CustomError', message: 'Test', fingerprint: 'hash-fingerprint' }
    )

    assert_equal 'hash-fingerprint', notice.fingerprint
  end

  def test_build_from_hash_option_fingerprint_overrides_hash
    notice = Checkend::NoticeBuilder.build_from_hash(
      { error_class: 'CustomError', fingerprint: 'hash-fp' },
      fingerprint: 'option-fp'
    )

    assert_equal 'option-fp', notice.fingerprint
  end

  def test_build_from_hash_with_tags_in_hash
    notice = Checkend::NoticeBuilder.build_from_hash(
      { error_class: 'CustomError', message: 'Test', tags: %w[from hash] }
    )

    assert_equal %w[from hash], notice.tags
  end

  def test_build_from_hash_option_tags_overrides_hash
    notice = Checkend::NoticeBuilder.build_from_hash(
      { error_class: 'CustomError', tags: %w[from hash] },
      tags: %w[from options]
    )

    assert_equal %w[from options], notice.tags
  end

  def test_build_from_hash_with_context
    notice = Checkend::NoticeBuilder.build_from_hash(
      { error_class: 'CustomError' },
      context: { key: 'value' }
    )

    assert_equal 'value', notice.context[:key]
  end
end
