# frozen_string_literal: true

module Checkend
  # Worker handles async sending of notices via a background thread.
  #
  # It maintains a queue of notices and sends them in the background,
  # implementing throttling on errors and graceful shutdown.
  #
  class Worker
    SHUTDOWN = Object.new.freeze
    FLUSH = Object.new.freeze

    # Exponential backoff base for throttling
    BASE_THROTTLE = 1.05
    MAX_THROTTLE = 100

    def initialize(config)
      @config = config
      @queue = Queue.new
      @mutex = Mutex.new
      @shutdown = false
      @throttle = 0
      @client = Client.new(config)
      @thread = start_thread
    end

    # Push a notice onto the queue for async sending
    #
    # @param notice [Notice] the notice to send
    # @return [Boolean] true if queued, false if rejected
    def push(notice)
      return false if @shutdown
      return false if @queue.size >= @config.max_queue_size

      @queue.push(notice)
      true
    end

    # Shutdown the worker, waiting for pending notices
    #
    # @param timeout [Integer] seconds to wait (default from config)
    def shutdown(timeout: nil)
      timeout ||= @config.shutdown_timeout

      @mutex.synchronize do
        return if @shutdown

        @shutdown = true
        @queue.push(SHUTDOWN)
      end

      @thread&.join(timeout)
    end

    # Flush the queue, blocking until all current notices are sent
    #
    # @param timeout [Integer] seconds to wait
    def flush(timeout: nil)
      timeout ||= @config.timeout

      cv = ConditionVariable.new
      @mutex.synchronize do
        @queue.push(cv)
        cv.wait(@mutex, timeout)
      end
    end

    # Check if the worker is running
    #
    # @return [Boolean]
    def running?
      @thread&.alive? && !@shutdown
    end

    # Get the current queue size
    #
    # @return [Integer]
    def queue_size
      @queue.size
    end

    private

    def start_thread
      Thread.new do
        Thread.current.name = 'checkend-worker'
        Thread.current.abort_on_exception = false
        run
      end
    end

    def run
      loop do
        msg = @queue.pop

        case msg
        when SHUTDOWN
          break
        when ConditionVariable
          @mutex.synchronize { msg.signal }
        when Notice
          send_with_throttle(msg)
        end
      end

      # Drain remaining notices on shutdown
      drain_queue
    rescue StandardError => e
      log_error("Worker crashed: #{e.class} - #{e.message}")
    end

    def send_with_throttle(notice)
      sleep(throttle_delay) if @throttle.positive?

      result = @client.send_notice(notice)

      if result.nil?
        inc_throttle
      else
        dec_throttle
      end
    end

    def throttle_delay
      ((BASE_THROTTLE**@throttle) - 1).round(3)
    end

    def inc_throttle
      @throttle = [@throttle + 1, MAX_THROTTLE].min
    end

    def dec_throttle
      @throttle = [@throttle - 1, 0].max
    end

    def drain_queue
      loop do
        msg = @queue.pop(true)
        @client.send_notice(msg) if msg.is_a?(Notice)
      rescue ThreadError
        # Queue is empty
        break
      end
    end

    def log_error(message)
      @config.resolved_logger.error("[Checkend] #{message}")
    end
  end
end
