# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Queue Time Tracking Integration", type: :request do
  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" }) }

  before do
    redis.flushdb
  end

  describe "end-to-end queue time tracking" do
    it "tracks queue times and serves them via /matrix endpoint" do
      # Simulate requests with X-Request-Start header
      base_time = Time.now.to_f

      # Make requests with different queue times
      5.times do |i|
        request_time = base_time - (0.05 - (i * 0.01)) # 50ms, 40ms, 30ms, 20ms, 10ms ago
        env = {
          "HTTP_X_REQUEST_START" => "t=#{request_time}",
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/test",
          "HTTP_HOST" => "example.com"
        }

        # Simulate middleware processing
        tracker = PumaMetricsEngine::QueueTimeTracker.new(->(_env) { [200, {}, ["OK"]] })
        tracker.call(env)
        sleep(0.01) # Small delay between requests
      end

      # Wait for async threads to complete
      sleep(0.2)

      # Check that data was stored
      queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
      expect(queue_times.size).to eq(5)

      # Request the matrix endpoint
      get "/puma_metrics_engine/matrix"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json["queue_time_ms"]["sample_count"]).to eq(5)
      expect(json["queue_time_ms"]["min"]).to be > 0
      expect(json["queue_time_ms"]["max"]).to be < 100
      expect(json["queue_time_windows"]["10s"]["sample_count"]).to be > 0
      expect(json["requests_per_minute"]["count"]).to eq(5)
    end

    it "handles requests without X-Request-Start header" do
      # Make requests without header
      3.times do
        env = {
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/test",
          "HTTP_HOST" => "example.com"
        }

        tracker = PumaMetricsEngine::QueueTimeTracker.new(->(_env) { [200, {}, ["OK"]] })
        tracker.call(env)
        sleep(0.01)
      end

      sleep(0.2)

      # Queue times should be empty
      queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
      expect(queue_times).to be_empty

      # But request timestamps should be present
      request_timestamps = redis.zrange(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, 0, -1)
      expect(request_timestamps.size).to eq(3)

      # Matrix endpoint should reflect this
      get "/puma_metrics_engine/matrix"

      json = JSON.parse(response.body)
      expect(json["queue_time_ms"]["sample_count"]).to eq(0)
      expect(json["requests_per_minute"]["count"]).to eq(3)
    end

    it "aggregates data across multiple workers" do
      base_time = Time.now.to_f

      # Simulate requests from different workers/processes
      worker1_times = [10.5, 15.2, 20.1]
      worker2_times = [12.3, 18.7, 22.4]

      worker1_times.each do |qt|
        request_time = base_time - (qt / 1000.0)
        env = {
          "HTTP_X_REQUEST_START" => "t=#{request_time}",
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/test",
          "HTTP_HOST" => "example.com"
        }
        tracker = PumaMetricsEngine::QueueTimeTracker.new(->(_env) { [200, {}, ["OK"]] })
        tracker.call(env)
        sleep(0.01)
      end

      worker2_times.each do |qt|
        request_time = base_time - (qt / 1000.0)
        env = {
          "HTTP_X_REQUEST_START" => "t=#{request_time}",
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/test",
          "HTTP_HOST" => "example.com"
        }
        tracker = PumaMetricsEngine::QueueTimeTracker.new(->(_env) { [200, {}, ["OK"]] })
        tracker.call(env)
        sleep(0.01)
      end

      sleep(0.2)

      # All data should be aggregated
      queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
      expect(queue_times.size).to eq(6)

      get "/puma_metrics_engine/matrix"

      json = JSON.parse(response.body)
      expect(json["queue_time_ms"]["sample_count"]).to eq(6)
      expect(json["queue_time_ms"]["min"]).to be <= 10.5
      expect(json["queue_time_ms"]["max"]).to be >= 22.4
    end

    it "respects TTL and cleans up old data" do
      base_time = Time.now.to_f

      # Add old data (older than 5 minutes)
      old_timestamp = base_time - 400
      redis.zadd(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, old_timestamp, 100.0)
      redis.zadd(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, old_timestamp, old_timestamp)

      # Add recent data
      recent_timestamp = base_time - 10
      redis.zadd(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, recent_timestamp, 10.0)
      redis.zadd(PumaMetricsEngine::QueueTimeTracker::REQUESTS_KEY, recent_timestamp, recent_timestamp)

      # Force cleanup by making a request and allowing cleanup to run
      Timecop.freeze(Time.now + 1) do
        env = {
          "HTTP_X_REQUEST_START" => "t=#{Time.now.to_f - 0.05}",
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/test",
          "HTTP_HOST" => "example.com"
        }
        tracker = PumaMetricsEngine::QueueTimeTracker.new(->(_env) { [200, {}, ["OK"]] })
        # Force cleanup by mocking rand
        allow(tracker).to receive(:rand).and_return(0.05)
        tracker.call(env)
        sleep(0.2)
      end

      # Old data should be removed
      queue_times = redis.zrange(PumaMetricsEngine::QueueTimeTracker::QUEUE_TIMES_KEY, 0, -1)
      # Should only have recent data (and possibly the new one)
      expect(queue_times.size).to be <= 2
    end
  end

  describe "matrix endpoint response format" do
    before do
      # Add some test data
      base_time = Time.now.to_f
      [10.5, 15.2, 20.1, 25.8, 30.3].each_with_index do |qt, i|
        timestamp = base_time - (5 - i)
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, timestamp, qt)
        redis.zadd(PumaMetricsEngine::MatrixController::REQUESTS_KEY, timestamp, timestamp)
      end
    end

    it "returns all required fields" do
      get "/puma_metrics_engine/matrix"

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json).to have_key("timestamp")
      expect(json).to have_key("queue_time_ms")
      expect(json).to have_key("queue_time_windows")
      expect(json).to have_key("requests_per_minute")
      expect(json).to have_key("puma")

      expect(json["queue_time_ms"]).to be_a(Hash)
      expect(json["queue_time_windows"]).to be_a(Hash)
      expect(json["requests_per_minute"]).to be_a(Hash)
      expect(json["puma"]).to be_a(Hash)
    end

    it "returns valid JSON structure" do
      get "/puma_metrics_engine/matrix"

      expect(response.content_type).to include("application/json")
      expect { JSON.parse(response.body) }.not_to raise_error
    end
  end
end

