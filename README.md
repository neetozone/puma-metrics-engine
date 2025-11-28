# PumaMetricsEngine

A Rails engine that provides a `/matrix` endpoint for Puma metrics and queue time statistics.

## Installation

Add to your Gemfile:

```ruby
gem "puma_metrics_engine"
```

Then run `bundle install`.

## Usage

Mount the engine in your routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount PumaMetricsEngine::Engine, at: "/"
end
```

Access metrics at `/matrix` endpoint.

## Response Format

```json
{
  "timestamp": "2024-01-15T10:30:00Z",
  "queue_time_ms": {
    "avg": 12.5,
    "p50": 10.0,
    "p95": 25.0,
    "p99": 50.0,
    "max": 100.0,
    "min": 1.0,
    "sample_count": 1000
  },
  "queue_time_windows": {
    "10s": { "avg": 12.3, "sample_count": 50 },
    "20s": { "avg": 12.5, "sample_count": 100 },
    "30s": { "avg": 12.4, "sample_count": 150 }
  },
  "requests_per_minute": { "count": 120, "window_seconds": 60 },
  "puma": { "workers": 2, "backlog": 0, "running": 10, ... }
}
```

## Requirements

- **Rails** >= 7.0
- **Redis** >= 5.0
- **X-Request-Start header**: Set by your load balancer (nginx, HAProxy, etc.) for queue time tracking

Redis connection uses `ENV["REDIS_URL"]` or defaults to `redis://localhost:6379/1`.

## License

MIT
