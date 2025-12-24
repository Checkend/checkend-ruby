# frozen_string_literal: true

require 'test_helper'
require 'checkend/testing'

class TestingModuleTest < Minitest::Test
  include CheckendTestHelper

  def teardown
    super
    # Ensure we always clean up
    Checkend::Testing.teardown! if defined?(Checkend::Testing)
  end

  def test_setup_disables_async
    configure_checkend(async: true)

    Checkend::Testing.setup!

    refute Checkend.configuration.async
  end

  def test_setup_replaces_client_with_fake
    configure_checkend

    Checkend::Testing.setup!

    client = Checkend.instance_variable_get(:@client)

    assert_instance_of Checkend::Testing::FakeClient, client
  end

  def test_teardown_restores_async
    configure_checkend(async: true)
    original_async = Checkend.configuration.async

    Checkend::Testing.setup!
    Checkend::Testing.teardown!

    assert_equal original_async, Checkend.configuration.async
  end

  def test_notices_returns_captured_notices
    configure_checkend
    Checkend::Testing.setup!

    exception = sample_exception
    Checkend.notify(exception)

    assert_equal 1, Checkend::Testing.notices.size
  end

  def test_last_notice_returns_most_recent
    configure_checkend
    Checkend::Testing.setup!

    Checkend.notify(StandardError.new('First'))
    Checkend.notify(StandardError.new('Second'))
    Checkend.notify(StandardError.new('Third'))

    assert_equal 'Third', Checkend::Testing.last_notice.message
  end

  def test_first_notice_returns_oldest
    configure_checkend
    Checkend::Testing.setup!

    Checkend.notify(StandardError.new('First'))
    Checkend.notify(StandardError.new('Second'))

    assert_equal 'First', Checkend::Testing.first_notice.message
  end

  def test_clear_notices_removes_all
    configure_checkend
    Checkend::Testing.setup!

    Checkend.notify(sample_exception)
    Checkend.notify(sample_exception)

    assert_equal 2, Checkend::Testing.notice_count

    Checkend::Testing.clear_notices!

    assert_equal 0, Checkend::Testing.notice_count
  end

  def test_notices_predicate_returns_true_when_notices_exist
    configure_checkend
    Checkend::Testing.setup!

    refute_predicate Checkend::Testing, :notices?

    Checkend.notify(sample_exception)

    assert_predicate Checkend::Testing, :notices?
  end

  def test_notice_count_returns_count
    configure_checkend
    Checkend::Testing.setup!

    assert_equal 0, Checkend::Testing.notice_count

    Checkend.notify(sample_exception)
    Checkend.notify(sample_exception)
    Checkend.notify(sample_exception)

    assert_equal 3, Checkend::Testing.notice_count
  end

  def test_captured_notice_has_correct_error_class
    configure_checkend
    Checkend::Testing.setup!

    begin
      raise ArgumentError, 'Invalid argument'
    rescue StandardError => e
      Checkend.notify(e)
    end

    assert_equal 'ArgumentError', Checkend::Testing.last_notice.error_class
  end

  def test_captured_notice_has_correct_message
    configure_checkend
    Checkend::Testing.setup!

    begin
      raise StandardError, 'Test error message'
    rescue StandardError => e
      Checkend.notify(e)
    end

    assert_equal 'Test error message', Checkend::Testing.last_notice.message
  end

  def test_captured_notice_includes_context
    configure_checkend
    Checkend::Testing.setup!
    Checkend.set_context(order_id: 123)

    Checkend.notify(sample_exception)

    assert_equal 123, Checkend::Testing.last_notice.context[:order_id]
  end

  def test_captured_notice_includes_tags
    configure_checkend
    Checkend::Testing.setup!

    Checkend.notify(sample_exception, tags: %w[checkout payment])

    assert_equal %w[checkout payment], Checkend::Testing.last_notice.tags
  end

  def test_send_notice_returns_fake_response
    configure_checkend
    Checkend::Testing.setup!

    result = Checkend.notify(sample_exception)

    assert_equal 1, result['id']
    assert_equal 1, result['problem_id']
  end

  def test_multiple_setup_teardown_cycles
    configure_checkend

    # First cycle
    Checkend::Testing.setup!
    Checkend.notify(sample_exception)

    assert_equal 1, Checkend::Testing.notice_count
    Checkend::Testing.teardown!

    # Second cycle
    Checkend::Testing.setup!

    assert_equal 0, Checkend::Testing.notice_count
    Checkend.notify(sample_exception)

    assert_equal 1, Checkend::Testing.notice_count
    Checkend::Testing.teardown!
  end
end

class FakeClientTest < Minitest::Test
  def setup
    @client = Checkend::Testing::FakeClient.new
  end

  def test_send_notice_captures_notice
    notice = Checkend::Notice.new
    notice.error_class = 'TestError'

    @client.send_notice(notice)

    assert_equal 1, @client.notices.size
    assert_equal 'TestError', @client.notices.first.error_class
  end

  def test_send_notice_returns_response
    notice = Checkend::Notice.new

    response = @client.send_notice(notice)

    assert_equal 1, response['id']
    assert_equal 1, response['problem_id']
  end

  def test_send_notice_increments_ids
    notice1 = Checkend::Notice.new
    notice2 = Checkend::Notice.new

    response1 = @client.send_notice(notice1)
    response2 = @client.send_notice(notice2)

    assert_equal 1, response1['id']
    assert_equal 2, response2['id']
  end

  def test_clear_removes_all_notices
    @client.send_notice(Checkend::Notice.new)
    @client.send_notice(Checkend::Notice.new)

    @client.clear!

    assert_empty @client.notices
  end

  def test_thread_safety
    threads = 10.times.map do
      Thread.new do
        10.times do
          notice = Checkend::Notice.new
          @client.send_notice(notice)
        end
      end
    end

    threads.each(&:join)

    assert_equal 100, @client.notices.size
  end
end
