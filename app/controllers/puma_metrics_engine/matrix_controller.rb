# frozen_string_literal: true

module PumaMetricsEngine
  class MatrixController < ActionController::Base
    skip_before_action :verify_authenticity_token

    TTL_SECONDS = 300 # 5 minutes
    REQUESTS_KEY = "puma:request_timestamps"
    QUEUE_TIMES_KEY = "puma:queue_times"
    MAX_SAMPLES = 1000

    def show
      puma_stats = fetch_puma_stats
      queue_time_stats = calculate_aggregate_queue_times
      queue_time_windows = calculate_queue_time_windows
      requests_per_minute = calculate_requests_per_minute

      render json: {
        timestamp: Time.current,
        queue_time_ms: queue_time_stats,
        queue_time_windows: queue_time_windows,
        requests_per_minute: requests_per_minute,
        puma: puma_stats
      }
    end

    private

      def calculate_aggregate_queue_times
        # Fetch all queue times from Redis (already sorted by timestamp)
        # This includes queue times from ALL requests across all workers and dynos (aggregated in shared Redis)
        times = redis.zrange(QUEUE_TIMES_KEY, 0, -1).map(&:to_f)

        return { error: "No queue time data available", sample_count: 0 } if times.empty?

        sorted = times.sort
        {
          avg: times.sum / times.size.to_f,
          p50: percentile(sorted, 50),
          p95: percentile(sorted, 95),
          p99: percentile(sorted, 99),
          max: times.max,
          min: times.min,
          sample_count: times.size
        }.transform_values { |v| v.is_a?(Numeric) ? v.round(2) : v }
      rescue Redis::BaseError => e
        {
          error: "Failed to fetch queue time data: #{e.message}",
          sample_count: 0
        }
      end

      def calculate_queue_time_windows
        current_time = Time.now.to_f
        windows = {
          "10s" => current_time - 10,
          "20s" => current_time - 20,
          "30s" => current_time - 30
        }

        result = {}
        windows.each do |window_name, start_time|
          # Get queue times within the time window using Redis sorted set range query
          queue_times = redis.zrangebyscore(QUEUE_TIMES_KEY, start_time, current_time)
          times = queue_times.map(&:to_f)

          if times.empty?
            result[window_name] = {
              avg: 0,
              sample_count: 0
            }
          else
            result[window_name] = {
              avg: (times.sum / times.size.to_f).round(2),
              sample_count: times.size
            }
          end
        end

        result
      rescue Redis::BaseError => e
        {
          error: "Failed to calculate queue time windows: #{e.message}",
          "10s" => { avg: 0, sample_count: 0 },
          "20s" => { avg: 0, sample_count: 0 },
          "30s" => { avg: 0, sample_count: 0 }
        }
      end

      def calculate_requests_per_minute
        current_time = Time.now.to_f
        one_minute_ago = current_time - 60

        # Count requests in the last minute using Redis sorted set range query
        # This counts ALL requests across all workers and dynos (aggregated in shared Redis)
        request_count = redis.zcount(REQUESTS_KEY, one_minute_ago, current_time)

        {
          count: request_count,
          window_seconds: 60
        }
      rescue Redis::BaseError => e
        {
          error: "Failed to calculate requests per minute: #{e.message}",
          count: 0,
          window_seconds: 60
        }
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" })
      end

      def percentile(sorted_array, percentile)
        return 0 if sorted_array.empty?

        index = (percentile / 100.0 * sorted_array.size).ceil - 1
        sorted_array[[index, 0].max]
      end

      def fetch_puma_stats
        return { error: "Puma stats not available" } unless defined?(Puma)

        begin
          if Puma.respond_to?(:stats)
            stats = JSON.parse(Puma.stats, symbolize_names: true)
            format_puma_stats(stats)
          else
            get_basic_stats
          end
        rescue StandardError => e
          { error: "Failed to fetch Puma stats: #{e.message}" }
        end
      end

      def format_puma_stats(stats)
        formatted = {
          workers: stats[:workers] || 0,
          phase: stats[:phase] || 0,
          booted_workers: stats[:booted_workers] || 0,
          old_workers: stats[:old_workers] || 0,
          backlog: stats[:backlog] || 0,
          running: stats[:running] || 0,
          pool_capacity: stats[:pool_capacity] || 0,
          max_threads: stats[:max_threads] || 0
        }

        # Include worker status if available
        if stats[:worker_status].present?
          formatted[:worker_status] = stats[:worker_status].map do |worker|
            {
              pid: worker[:pid],
              index: worker[:index],
              phase: worker[:phase],
              booted: worker[:booted],
              last_status: worker[:last_status]
            }
          end
        end

        formatted
      end

      def get_basic_stats
        {
          threads: Thread.list.count,
          process_id: Process.pid,
          rails_env: Rails.env,
          note: "Running in single-threaded mode"
        }
      end
  end
end
