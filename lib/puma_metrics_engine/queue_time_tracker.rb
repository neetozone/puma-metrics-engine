# frozen_string_literal: true

module PumaMetricsEngine
  class QueueTimeTracker
    TTL_SECONDS = 300 # 5 minutes
    REQUESTS_KEY = "puma:request_timestamps"
    QUEUE_TIMES_KEY = "puma:queue_times"

    def initialize(app)
      @app = app
    end

    def call(env)
      request_start_time = extract_request_start_time(env)
      process_start_time = Time.now.to_f

      status, headers, response = @app.call(env)

      # Calculate queue time if we have request start time
      begin
        if request_start_time
          queue_time_ms = ((process_start_time - request_start_time) * 1000).round(2)
          
          # Only store if queue time is reasonable (positive and less than 1 hour)
          # Negative values indicate clock skew, very large values are likely errors
          if queue_time_ms >= 0 && queue_time_ms < 3_600_000
            timestamp = process_start_time
            # Store in Redis asynchronously to avoid blocking the request
            store_metrics_async(timestamp, queue_time_ms)
          else
            # Still track request timestamp even if queue time is invalid
            store_request_timestamp_async(process_start_time)
          end
        else
          # Still track request timestamp even without queue time
          store_request_timestamp_async(process_start_time)
        end
      rescue StandardError => e
        # Don't let tracking errors break the request
        Rails.logger.error("QueueTimeTracker error: #{e.message}") if defined?(Rails)
      end

      [status, headers, response]
    end

    private

      def extract_request_start_time(env)
        # Try X-Request-Start header (common in nginx, HAProxy, etc.)
        # Format: "t=1234567890.123" or "1234567890.123" or Unix timestamp in microseconds
        header_value = env["HTTP_X_REQUEST_START"] || env["X-Request-Start"]

        return nil unless header_value

        # Handle different formats
        # Format 1: "t=1234567890.123"
        if header_value =~ /t=([\d.]+)/
          timestamp_str = $1
        # Format 2: "1234567890.123" (direct timestamp)
        elsif header_value =~ /^[\d.]+$/
          timestamp_str = header_value
        else
          return nil
        end

        timestamp = timestamp_str.to_f

        # If timestamp is in microseconds (common with nginx), convert to seconds
        # Timestamps > year 2100 are likely in microseconds
        if timestamp > 4_102_444_800 # Year 2100 in seconds
          timestamp = timestamp / 1_000_000.0
        end

        timestamp
      rescue StandardError
        nil
      end

      def store_metrics_async(timestamp, queue_time_ms)
        # Use a thread pool or async job, but for simplicity, we'll do it synchronously
        # In production, you might want to use a background job
        Thread.new do
          begin
            redis_client = redis
            # Store queue time with timestamp as score
            redis_client.zadd(QUEUE_TIMES_KEY, timestamp, queue_time_ms)
            # Store request timestamp
            redis_client.zadd(REQUESTS_KEY, timestamp, timestamp)
            # Cleanup old data (older than TTL)
            cleanup_old_data(redis_client)
          rescue StandardError => e
            Rails.logger.error("Failed to store queue time metrics: #{e.message}") if defined?(Rails)
          end
        end
      end

      def store_request_timestamp_async(timestamp)
        Thread.new do
          begin
            redis_client = redis
            redis_client.zadd(REQUESTS_KEY, timestamp, timestamp)
            cleanup_old_data(redis_client)
          rescue StandardError => e
            Rails.logger.error("Failed to store request timestamp: #{e.message}") if defined?(Rails)
          end
        end
      end

      def cleanup_old_data(redis_client)
        # Only cleanup occasionally to avoid overhead (10% chance)
        return unless rand < 0.1

        cutoff_time = Time.now.to_f - TTL_SECONDS
        # Remove old entries from both sorted sets
        redis_client.zremrangebyscore(QUEUE_TIMES_KEY, "-inf", cutoff_time)
        redis_client.zremrangebyscore(REQUESTS_KEY, "-inf", cutoff_time)
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" })
      end
  end
end

