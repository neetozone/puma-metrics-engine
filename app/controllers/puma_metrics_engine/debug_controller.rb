# frozen_string_literal: true

module PumaMetricsEngine
  class DebugController < ActionController::Base
    skip_before_action :verify_authenticity_token

    def show
      render json: {
        timestamp: Time.current,
        middleware: middleware_status,
        redis: redis_status,
        headers: sample_headers,
        data: redis_data_summary,
        environment: environment_info
      }
    end

    private

      def middleware_status
        middleware_stack = Rails.application.middleware.to_a.map(&:klass).map(&:name)
        is_registered = middleware_stack.include?("PumaMetricsEngine::QueueTimeTracker")

        {
          registered: is_registered,
          middleware_stack: middleware_stack,
          note: is_registered ? "Middleware is registered" : "Middleware NOT found in stack"
        }
      rescue StandardError => e
        { error: e.message }
      end

      def redis_status
        client = redis
        client.ping
        {
          connected: true,
          url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" },
          keys: {
            queue_times: client.exists?(MatrixController::QUEUE_TIMES_KEY),
            request_timestamps: client.exists?(MatrixController::REQUESTS_KEY)
          }
        }
      rescue StandardError => e
        {
          connected: false,
          error: e.message,
          url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" }
        }
      end

      def redis_data_summary
        client = redis
        {
          queue_times_count: client.zcard(MatrixController::QUEUE_TIMES_KEY),
          request_timestamps_count: client.zcard(MatrixController::REQUESTS_KEY),
          recent_queue_times: client.zrange(MatrixController::QUEUE_TIMES_KEY, -10, -1),
          recent_timestamps: client.zrange(MatrixController::REQUESTS_KEY, -10, -1)
        }
      rescue StandardError => e
        { error: e.message }
      end

      def sample_headers
        # Show what headers we're looking for
        {
          x_request_start: request.headers["X-Request-Start"],
          http_x_request_start: request.headers["HTTP_X_REQUEST_START"],
          all_x_headers: request.headers.select { |k, _| k.to_s.upcase.include?("X-REQUEST") },
          note: "Check if X-Request-Start header is being sent by your load balancer"
        }
      end

      def environment_info
        {
          rails_env: Rails.env,
          redis_url_set: ENV.key?("REDIS_URL"),
          puma_defined: defined?(Puma)
        }
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" })
      end
  end
end

