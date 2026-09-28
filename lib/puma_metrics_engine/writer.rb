# frozen_string_literal: true

require "securerandom"

module PumaMetricsEngine
  # Sends samples to Redis from one background thread, so a request never
  # waits on Redis and no thread is started per request.
  #
  # Each sample gets a random suffix in its sorted-set member. Members are
  # unique, so storing the bare value made equal values overwrite each other.
  # Readers parse members with String#to_f, which stops at the colon, so they
  # read "12.5:1a2b3c4d" as 12.5 without any change.
  class Writer
    # Samples waiting to be written. When Redis is unreachable the queue stops
    # growing here and new samples are dropped instead.
    MAX_PENDING = 10_000
    BATCH_SIZE = 500

    def initialize(queue_times_key:, requests_key:, redis_url:, after_write: nil)
      @queue_times_key = queue_times_key
      @requests_key = requests_key
      @redis_url = redis_url
      @after_write = after_write
      @queue = Thread::Queue.new
      @mutex = Mutex.new
      @thread = nil
      @pid = nil
    end

    # queue_time_ms is nil when the request carried no usable start time; the
    # request still counts towards requests per minute.
    def record(timestamp, queue_time_ms)
      ensure_thread
      return if @queue.size >= MAX_PENDING

      @queue << [timestamp, queue_time_ms]
    end

    private

      def ensure_thread
        return if running?

        @mutex.synchronize do
          next if running?

          # After a fork the thread and connection belong to the parent.
          if @pid != Process.pid
            @queue = Thread::Queue.new
            @redis = nil
          end
          @pid = Process.pid
          @thread = Thread.new { run }
          @thread.name = "puma_metrics_writer"
        end
      end

      def running?
        @pid == Process.pid && @thread&.alive?
      end

      def run
        loop do
          write(next_batch)
        rescue StandardError => e
          log_error(e)
          sleep(1)
        end
      end

      def next_batch
        batch = [@queue.pop]
        while batch.size < BATCH_SIZE
          sample = begin
            @queue.pop(true)
          rescue ThreadError
            break
          end
          batch << sample
        end
        batch
      end

      def write(batch)
        queue_times = []
        requests = []
        batch.each do |timestamp, queue_time_ms|
          id = SecureRandom.hex(4)
          queue_times << [timestamp, "#{queue_time_ms}:#{id}"] if queue_time_ms
          requests << [timestamp, "#{timestamp}:#{id}"]
        end

        redis.pipelined do |pipeline|
          pipeline.zadd(@queue_times_key, queue_times) if queue_times.any?
          pipeline.zadd(@requests_key, requests)
        end
        @after_write&.call(redis)
      end

      def redis
        @redis ||= Redis.new(url: @redis_url)
      end

      def log_error(error)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.error("[QueueTimeTracker] Failed to store metrics: #{error.class}: #{error.message}")
      end
  end
end
