# frozen_string_literal: true

module Checkend
  # Testing utilities for Checkend SDK.
  #
  # Use this module in your test suite to capture and inspect notices
  # without actually sending them to the server.
  #
  # @example RSpec setup
  #   RSpec.configure do |config|
  #     config.before(:each) do
  #       Checkend::Testing.setup!
  #     end
  #
  #     config.after(:each) do
  #       Checkend::Testing.teardown!
  #     end
  #   end
  #
  # @example Minitest setup
  #   class ActiveSupport::TestCase
  #     setup do
  #       Checkend::Testing.setup!
  #     end
  #
  #     teardown do
  #       Checkend::Testing.teardown!
  #     end
  #   end
  #
  # @example Asserting on captured notices
  #   def test_error_is_reported
  #     begin
  #       raise StandardError, 'Test error'
  #     rescue => e
  #       Checkend.notify(e)
  #     end
  #
  #     assert_equal 1, Checkend::Testing.notices.size
  #     assert_equal 'StandardError', Checkend::Testing.last_notice.error_class
  #   end
  #
  module Testing
    class << self
      # Set up test mode - disables async sending and captures notices
      #
      # @return [void]
      def setup!
        @original_async = Checkend.configuration.async
        @original_client = Checkend.instance_variable_get(:@client)

        # Disable async to make tests deterministic
        Checkend.configuration.async = false

        # Replace client with fake client
        @fake_client = FakeClient.new
        Checkend.instance_variable_set(:@client, @fake_client)

        # Ensure SDK is started
        Checkend.instance_variable_set(:@started, true)

        # Clear any existing context
        Checkend.clear!
      end

      # Tear down test mode - restores original configuration
      #
      # @return [void]
      def teardown!
        # Restore original settings
        Checkend.configuration.async = @original_async if defined?(@original_async)
        Checkend.instance_variable_set(:@client, @original_client) if defined?(@original_client)

        # Clear captured notices
        clear_notices!

        # Clear context
        Checkend.clear!

        # Remove instance variables
        remove_instance_variable(:@original_async) if defined?(@original_async)
        remove_instance_variable(:@original_client) if defined?(@original_client)
        remove_instance_variable(:@fake_client) if defined?(@fake_client)
      end

      # Get all captured notices
      #
      # @return [Array<Notice>] array of captured notices
      def notices
        return [] unless @fake_client

        @fake_client.notices
      end

      # Get the last captured notice
      #
      # @return [Notice, nil] the last notice or nil if none
      def last_notice
        notices.last
      end

      # Get the first captured notice
      #
      # @return [Notice, nil] the first notice or nil if none
      def first_notice
        notices.first
      end

      # Clear all captured notices
      #
      # @return [void]
      def clear_notices!
        @fake_client&.clear!
      end

      # Check if any notices were captured
      #
      # @return [Boolean]
      def notices?
        !notices.empty?
      end

      # Get the number of captured notices
      #
      # @return [Integer]
      def notice_count
        notices.size
      end
    end

    # Fake client that captures notices instead of sending them
    class FakeClient
      attr_reader :notices

      def initialize
        @notices = []
        @mutex = Mutex.new
      end

      # Capture a notice instead of sending it
      #
      # @param notice [Notice] the notice to capture
      # @return [Hash] fake response
      def send_notice(notice)
        @mutex.synchronize do
          @notices << notice
        end

        # Return a fake successful response
        {
          'id' => @notices.size,
          'problem_id' => @notices.size
        }
      end

      # Clear all captured notices
      #
      # @return [void]
      def clear!
        @mutex.synchronize do
          @notices.clear
        end
      end
    end
  end
end
