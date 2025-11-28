# frozen_string_literal: true

require "rails_helper"

RSpec.describe PumaMetricsEngine::MatrixController, type: :controller do
  let(:redis) { Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" }) }

  before do
    redis.flushdb
  end

  describe "GET #show" do
    context "with queue time data" do
      before do
        # Add queue time data
        base_time = Time.now.to_f
        queue_times = [10.5, 15.2, 20.1, 25.8, 30.3, 35.7, 40.2, 45.9, 50.1, 55.6]
        queue_times.each_with_index do |qt, i|
          timestamp = base_time - (10 - i)
          redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, timestamp, qt)
          redis.zadd(PumaMetricsEngine::MatrixController::REQUESTS_KEY, timestamp, timestamp)
        end
      end

      it "returns queue time statistics" do
        get :show

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json["queue_time_ms"]).to include(
          "avg" => be_a(Numeric),
          "p50" => be_a(Numeric),
          "p95" => be_a(Numeric),
          "p99" => be_a(Numeric),
          "max" => be_a(Numeric),
          "min" => be_a(Numeric),
          "sample_count" => 10
        )

        expect(json["queue_time_ms"]["min"]).to eq(10.5)
        expect(json["queue_time_ms"]["max"]).to eq(55.6)
        expect(json["queue_time_ms"]["sample_count"]).to eq(10)
      end

      it "returns queue time windows" do
        get :show

        json = JSON.parse(response.body)

        expect(json["queue_time_windows"]).to have_key("10s")
        expect(json["queue_time_windows"]).to have_key("20s")
        expect(json["queue_time_windows"]).to have_key("30s")

        json["queue_time_windows"].each_value do |window|
          expect(window).to include("avg", "sample_count")
          expect(window["avg"]).to be_a(Numeric)
          expect(window["sample_count"]).to be_a(Integer)
        end
      end

      it "returns requests per minute" do
        get :show

        json = JSON.parse(response.body)

        expect(json["requests_per_minute"]).to include(
          "count" => be_a(Integer),
          "window_seconds" => 60
        )
      end

      it "returns timestamp" do
        get :show

        json = JSON.parse(response.body)
        expect(json["timestamp"]).to be_present
      end
    end

    context "without queue time data" do
      it "returns error message for queue time" do
        get :show

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json["queue_time_ms"]).to eq(
          "error" => "No queue time data available",
          "sample_count" => 0
        )
      end

      it "returns zero for queue time windows" do
        get :show

        json = JSON.parse(response.body)

        expect(json["queue_time_windows"]["10s"]).to eq("avg" => 0, "sample_count" => 0)
        expect(json["queue_time_windows"]["20s"]).to eq("avg" => 0, "sample_count" => 0)
        expect(json["queue_time_windows"]["30s"]).to eq("avg" => 0, "sample_count" => 0)
      end

      it "returns zero for requests per minute" do
        get :show

        json = JSON.parse(response.body)

        expect(json["requests_per_minute"]).to eq(
          "count" => 0,
          "window_seconds" => 60
        )
      end
    end

    context "with queue time windows" do
      it "calculates correct averages for 10s window" do
        base_time = Time.now.to_f
        # Add data within last 10 seconds
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 5, 10.0)
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 3, 20.0)
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 1, 30.0)

        get :show

        json = JSON.parse(response.body)
        expect(json["queue_time_windows"]["10s"]["avg"]).to eq(20.0)
        expect(json["queue_time_windows"]["10s"]["sample_count"]).to eq(3)
      end

      it "excludes data older than window" do
        base_time = Time.now.to_f
        # Add data within last 10 seconds
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 5, 10.0)
        # Add data older than 10 seconds
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 15, 100.0)

        get :show

        json = JSON.parse(response.body)
        expect(json["queue_time_windows"]["10s"]["avg"]).to eq(10.0)
        expect(json["queue_time_windows"]["10s"]["sample_count"]).to eq(1)
      end

      it "calculates correct averages for 20s window" do
        base_time = Time.now.to_f
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 15, 15.0)
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 10, 25.0)
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 5, 35.0)

        get :show

        json = JSON.parse(response.body)
        expect(json["queue_time_windows"]["20s"]["avg"]).to eq(25.0)
        expect(json["queue_time_windows"]["20s"]["sample_count"]).to eq(3)
      end

      it "calculates correct averages for 30s window" do
        base_time = Time.now.to_f
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 25, 20.0)
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 15, 30.0)
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time - 5, 40.0)

        get :show

        json = JSON.parse(response.body)
        expect(json["queue_time_windows"]["30s"]["avg"]).to eq(30.0)
        expect(json["queue_time_windows"]["30s"]["sample_count"]).to eq(3)
      end
    end

    context "with requests per minute" do
      it "counts requests in the last minute" do
        base_time = Time.now.to_f
        # Add requests within last minute
        redis.zadd(PumaMetricsEngine::MatrixController::REQUESTS_KEY, base_time - 30, base_time - 30)
        redis.zadd(PumaMetricsEngine::MatrixController::REQUESTS_KEY, base_time - 20, base_time - 20)
        redis.zadd(PumaMetricsEngine::MatrixController::REQUESTS_KEY, base_time - 10, base_time - 10)
        # Add request older than 1 minute
        redis.zadd(PumaMetricsEngine::MatrixController::REQUESTS_KEY, base_time - 70, base_time - 70)

        get :show

        json = JSON.parse(response.body)
        expect(json["requests_per_minute"]["count"]).to eq(3)
      end

      it "returns zero when no requests in last minute" do
        base_time = Time.now.to_f
        # Add request older than 1 minute
        redis.zadd(PumaMetricsEngine::MatrixController::REQUESTS_KEY, base_time - 70, base_time - 70)

        get :show

        json = JSON.parse(response.body)
        expect(json["requests_per_minute"]["count"]).to eq(0)
      end
    end

    context "when Redis connection fails" do
      before do
        allow_any_instance_of(Redis).to receive(:zrange).and_raise(Redis::BaseError.new("Connection failed"))
      end

      it "returns error for queue time" do
        get :show

        json = JSON.parse(response.body)
        expect(json["queue_time_ms"]).to include(
          "error" => include("Failed to fetch queue time data"),
          "sample_count" => 0
        )
      end

      it "returns error for queue time windows" do
        get :show

        json = JSON.parse(response.body)
        expect(json["queue_time_windows"]).to include(
          "error" => include("Failed to calculate queue time windows"),
          "10s" => { "avg" => 0, "sample_count" => 0 },
          "20s" => { "avg" => 0, "sample_count" => 0 },
          "30s" => { "avg" => 0, "sample_count" => 0 }
        )
      end

      it "returns error for requests per minute" do
        get :show

        json = JSON.parse(response.body)
        expect(json["requests_per_minute"]).to include(
          "error" => include("Failed to calculate requests per minute"),
          "count" => 0,
          "window_seconds" => 60
        )
      end
    end

    context "percentile calculations" do
      it "calculates p50 correctly" do
        base_time = Time.now.to_f
        queue_times = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
        queue_times.each_with_index do |qt, i|
          timestamp = base_time - (10 - i)
          redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, timestamp, qt)
        end

        get :show

        json = JSON.parse(response.body)
        # p50 should be the median (average of 50 and 60)
        expect(json["queue_time_ms"]["p50"]).to eq(55.0)
      end

      it "calculates p95 correctly" do
        base_time = Time.now.to_f
        queue_times = (1..100).to_a # 100 values
        queue_times.each_with_index do |qt, i|
          timestamp = base_time - (100 - i)
          redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, timestamp, qt)
        end

        get :show

        json = JSON.parse(response.body)
        # p95 should be around the 95th percentile
        expect(json["queue_time_ms"]["p95"]).to be >= 95
        expect(json["queue_time_ms"]["p95"]).to be <= 96
      end

      it "calculates p99 correctly" do
        base_time = Time.now.to_f
        queue_times = (1..100).to_a # 100 values
        queue_times.each_with_index do |qt, i|
          timestamp = base_time - (100 - i)
          redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, timestamp, qt)
        end

        get :show

        json = JSON.parse(response.body)
        # p99 should be around the 99th percentile
        expect(json["queue_time_ms"]["p99"]).to be >= 99
        expect(json["queue_time_ms"]["p99"]).to be <= 100
      end

      it "handles single value correctly" do
        base_time = Time.now.to_f
        redis.zadd(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, base_time, 42.5)

        get :show

        json = JSON.parse(response.body)
        expect(json["queue_time_ms"]["p50"]).to eq(42.5)
        expect(json["queue_time_ms"]["p95"]).to eq(42.5)
        expect(json["queue_time_ms"]["p99"]).to eq(42.5)
        expect(json["queue_time_ms"]["min"]).to eq(42.5)
        expect(json["queue_time_ms"]["max"]).to eq(42.5)
      end

      it "handles empty array in percentile calculation" do
        controller = described_class.new
        result = controller.send(:percentile, [], 50)
        expect(result).to eq(0)
      end
    end

    context "with Puma stats" do
      before do
        # Mock Puma.stats if available
        if defined?(Puma)
          allow(Puma).to receive(:respond_to?).with(:stats).and_return(true)
          puma_stats = {
            workers: 2,
            phase: 0,
            booted_workers: 2,
            old_workers: 0,
            backlog: 0,
            running: 10,
            pool_capacity: 20,
            max_threads: 10
          }.to_json
          allow(Puma).to receive(:stats).and_return(puma_stats)
        end
      end

      it "returns Puma stats when available" do
        get :show

        json = JSON.parse(response.body)
        if defined?(Puma)
          expect(json["puma"]).to include(
            "workers" => 2,
            "phase" => 0,
            "booted_workers" => 2,
            "old_workers" => 0,
            "backlog" => 0,
            "running" => 10,
            "pool_capacity" => 20,
            "max_threads" => 10
          )
        end
      end
    end

    context "without Puma stats" do
      before do
        # Mock Puma not being available
        if defined?(Puma)
          allow(Puma).to receive(:respond_to?).with(:stats).and_return(false)
        end
      end

      it "returns basic stats when Puma stats unavailable" do
        get :show

        json = JSON.parse(response.body)
        expect(json["puma"]).to be_present
      end
    end

    context "CSRF protection" do
      it "skips CSRF token verification" do
        # This should not raise CSRF error
        expect do
          get :show
        end.not_to raise_error
      end
    end
  end

  describe "#percentile" do
    let(:controller) { described_class.new }

    it "calculates percentile for sorted array" do
      sorted = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      expect(controller.send(:percentile, sorted, 50)).to eq(5)
      expect(controller.send(:percentile, sorted, 95)).to eq(10)
      expect(controller.send(:percentile, sorted, 99)).to eq(10)
    end

    it "handles edge case with index 0" do
      sorted = [10, 20, 30]
      expect(controller.send(:percentile, sorted, 33)).to eq(10)
    end

    it "handles single element" do
      sorted = [42]
      expect(controller.send(:percentile, sorted, 50)).to eq(42)
      expect(controller.send(:percentile, sorted, 95)).to eq(42)
      expect(controller.send(:percentile, sorted, 99)).to eq(42)
    end

    it "handles empty array" do
      expect(controller.send(:percentile, [], 50)).to eq(0)
    end
  end
end

