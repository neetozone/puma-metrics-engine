# frozen_string_literal: true

require "rails_helper"

RSpec.describe PumaMetricsEngine::QueueTimeTracker do
  let(:app) { ->(env) { [200, {}, ["OK"]] } }
  let(:middleware) { described_class.new(app) }
  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" }) }
  let(:base_env) do
    {
      "REQUEST_METHOD" => "GET",
      "PATH_INFO" => "/test",
      "HTTP_HOST" => "example.com"
    }
  end

  before do
    redis.flushdb
  end

  describe "#call" do
    context "when X-Request-Start header is present" do
      context "with t= format (nginx style)" do
        it "extracts and stores queue time" do
          request_time = Time.now.to_f - 0.05 # 50ms ago
          env = base_env.merge("HTTP_X_REQUEST_START" => "t=#{request_time}")

          # Wait a bit to ensure different timestamps
          sleep(0.01)
          status, headers, body = middleware.call(env)

          expect(status).to eq(200)

          # Wait for async thread to complete
          sleep(0.1)

          queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
          expect(queue_times).not_to be_empty
          queue_time_ms = queue_times.first.to_f
          expect(queue_time_ms).to be > 0
          expect(queue_time_ms).to be < 100 # Should be around 50-60ms
        end
      end

      context "with direct timestamp format" do
        it "extracts and stores queue time" do
          request_time = Time.now.to_f - 0.1 # 100ms ago
          env = base_env.merge("HTTP_X_REQUEST_START" => request_time.to_s)

          sleep(0.01)
          status, headers, body = middleware.call(env)

          expect(status).to eq(200)

          sleep(0.1)

          queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
          expect(queue_times).not_to be_empty
          queue_time_ms = queue_times.first.to_f
          expect(queue_time_ms).to be > 90
          expect(queue_time_ms).to be < 120
        end
      end

      context "with microsecond timestamp (nginx default)" do
        it "converts microseconds to seconds" do
          request_time_seconds = Time.now.to_f - 0.05
          request_time_microseconds = (request_time_seconds * 1_000_000).to_i
          env = base_env.merge("HTTP_X_REQUEST_START" => "t=#{request_time_microseconds}")

          sleep(0.01)
          status, headers, body = middleware.call(env)

          expect(status).to eq(200)

          sleep(0.1)

          queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
          expect(queue_times).not_to be_empty
          queue_time_ms = queue_times.first.to_f
          expect(queue_time_ms).to be > 0
          expect(queue_time_ms).to be < 100
        end
      end

      context "with negative queue time (clock skew)" do
        it "does not store negative queue time" do
          future_time = Time.now.to_f + 1.0 # Future time
          env = base_env.merge("HTTP_X_REQUEST_START" => "t=#{future_time}")

          status, headers, body = middleware.call(env)

          expect(status).to eq(200)

          sleep(0.1)

          queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
          expect(queue_times).to be_empty

          # But should still store request timestamp
          request_timestamps = redis.zrange(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, 0, -1)
          expect(request_timestamps).not_to be_empty
        end
      end

      context "with unreasonably large queue time (> 1 hour)" do
        it "does not store the queue time" do
          old_time = Time.now.to_f - 4000 # More than 1 hour ago
          env = base_env.merge("HTTP_X_REQUEST_START" => "t=#{old_time}")

          status, headers, body = middleware.call(env)

          expect(status).to eq(200)

          sleep(0.1)

          queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
          expect(queue_times).to be_empty

          # But should still store request timestamp
          request_timestamps = redis.zrange(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, 0, -1)
          expect(request_timestamps).not_to be_empty
        end
      end

      context "with valid queue time" do
        it "stores both queue time and request timestamp" do
          request_time = Time.now.to_f - 0.025 # 25ms ago
          env = base_env.merge("HTTP_X_REQUEST_START" => "t=#{request_time}")

          process_start = Time.now.to_f
          sleep(0.01)
          status, headers, body = middleware.call(env)

          expect(status).to eq(200)

          sleep(0.1)

          # Check queue times
          queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
          expect(queue_times).not_to be_empty

          # Check request timestamps
          request_timestamps = redis.zrange(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, 0, -1)
          expect(request_timestamps).not_to be_empty
        end
      end
    end

    context "when X-Request-Start header is missing" do
      it "still stores request timestamp" do
        env = base_env

        status, headers, body = middleware.call(env)

        expect(status).to eq(200)

        sleep(0.1)

        queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
        expect(queue_times).to be_empty

        request_timestamps = redis.zrange(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, 0, -1)
        expect(request_timestamps).not_to be_empty
      end
    end

    context "when X-Request-Start header is malformed" do
      it "handles gracefully and still processes request" do
        env = base_env.merge("HTTP_X_REQUEST_START" => "invalid-format")

        status, headers, body = middleware.call(env)

        expect(status).to eq(200)

        sleep(0.1)

        queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
        expect(queue_times).to be_empty

        request_timestamps = redis.zrange(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, 0, -1)
        expect(request_timestamps).not_to be_empty
      end
    end

    context "when Redis connection fails" do
      it "does not break the request" do
        allow_any_instance_of(Redis).to receive(:zadd).and_raise(Redis::BaseError.new("Connection failed"))
        request_time = Time.now.to_f - 0.05
        env = base_env.merge("HTTP_X_REQUEST_START" => "t=#{request_time}")

        expect do
          status, headers, body = middleware.call(env)
          expect(status).to eq(200)
        end.not_to raise_error
      end
    end

    context "when app raises an error" do
      it "propagates the error" do
        failing_app = ->(_env) { raise StandardError, "App error" }
        middleware = described_class.new(failing_app)
        env = base_env

        expect do
          middleware.call(env)
        end.to raise_error(StandardError, "App error")
      end
    end
  end

  describe "#extract_request_start_time" do
    let(:tracker) { described_class.new(app) }

    context "with various header formats" do
      it "handles nginx format with t= prefix" do
        timestamp = Time.now.to_f
        env = { "HTTP_X_REQUEST_START" => "t=#{timestamp}" }
        result = tracker.send(:extract_request_start_time, env)
        expect(result).to be_within(0.001).of(timestamp)
      end

      it "handles direct timestamp format" do
        timestamp = Time.now.to_f
        env = { "HTTP_X_REQUEST_START" => timestamp.to_s }
        result = tracker.send(:extract_request_start_time, env)
        expect(result).to be_within(0.001).of(timestamp)
      end

      it "handles X-Request-Start key format" do
        timestamp = Time.now.to_f
        env = { "X-Request-Start" => "t=#{timestamp}" }
        result = tracker.send(:extract_request_start_time, env)
        expect(result).to be_within(0.001).of(timestamp)
      end

      it "converts microsecond timestamps" do
        timestamp_seconds = Time.now.to_f
        timestamp_microseconds = (timestamp_seconds * 1_000_000).to_i
        env = { "HTTP_X_REQUEST_START" => timestamp_microseconds.to_s }
        result = tracker.send(:extract_request_start_time, env)
        expect(result).to be_within(0.001).of(timestamp_seconds)
      end

      it "returns nil for missing header" do
        env = {}
        result = tracker.send(:extract_request_start_time, env)
        expect(result).to be_nil
      end

      it "returns nil for invalid format" do
        env = { "HTTP_X_REQUEST_START" => "not-a-timestamp" }
        result = tracker.send(:extract_request_start_time, env)
        expect(result).to be_nil
      end

      it "handles empty string" do
        env = { "HTTP_X_REQUEST_START" => "" }
        result = tracker.send(:extract_request_start_time, env)
        expect(result).to be_nil
      end
    end
  end

  describe "cleanup_old_data" do
    it "removes data older than TTL" do
      tracker = described_class.new(app)
      redis_client = redis

      # Add old data
      old_timestamp = Time.now.to_f - 400 # 400 seconds ago
      redis_client.zadd(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, old_timestamp, 10.5)
      redis_client.zadd(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, old_timestamp, old_timestamp)

      # Add recent data
      recent_timestamp = Time.now.to_f - 10 # 10 seconds ago
      redis_client.zadd(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, recent_timestamp, 5.2)
      redis_client.zadd(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, recent_timestamp, recent_timestamp)

      # Force cleanup (bypassing the 10% random check)
      allow(tracker).to receive(:rand).and_return(0.05) # Less than 0.1
      tracker.send(:cleanup_old_data, redis_client)

      # Old data should be removed
      queue_times = redis_client.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
      expect(queue_times).to eq(["5.2"])

      request_timestamps = redis_client.zrange(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, 0, -1)
      expect(request_timestamps.size).to eq(1)
    end

    it "only runs cleanup 10% of the time" do
      tracker = described_class.new(app)
      redis_client = redis

      # Mock rand to return > 0.1 (should skip cleanup)
      allow(tracker).to receive(:rand).and_return(0.5)
      expect(redis_client).not_to receive(:zremrangebyscore)

      tracker.send(:cleanup_old_data, redis_client)
    end
  end

  describe "multiple requests" do
    it "aggregates data from multiple requests" do
      request_time1 = Time.now.to_f - 0.05
      request_time2 = Time.now.to_f - 0.03
      request_time3 = Time.now.to_f - 0.01

      env1 = base_env.merge("HTTP_X_REQUEST_START" => "t=#{request_time1}")
      env2 = base_env.merge("HTTP_X_REQUEST_START" => "t=#{request_time2}")
      env3 = base_env.merge("HTTP_X_REQUEST_START" => "t=#{request_time3}")

      middleware.call(env1)
      sleep(0.01)
      middleware.call(env2)
      sleep(0.01)
      middleware.call(env3)

      sleep(0.2) # Wait for all async threads

      queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
      expect(queue_times.size).to eq(3)

      request_timestamps = redis.zrange(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, 0, -1)
      expect(request_timestamps.size).to eq(3)
    end
  end
end

