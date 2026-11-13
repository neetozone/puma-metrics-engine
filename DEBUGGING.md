# Debugging Production Issues

If you're not seeing queue time data in production, run these checks in a Rails console on the app.

## Quick Debug Steps

### Middleware Status
```ruby
Rails.application.middleware.to_a.map(&:klass).map(&:name).include?("PumaMetricsEngine::QueueTimeTracker")
```
- If `false`, the middleware isn't being loaded. Check that the engine is properly mounted.

### Redis Status
```ruby
redis = Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" })
redis.ping
redis.exists?(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY)
redis.exists?(PumaMetricsEngine::MatrixController::REQUESTS_KEY)
```
- If `ping` raises, check your `REDIS_URL` environment variable.
- If keys don't exist, no data has been stored yet.

### Headers
- Check the Rails logs for `[QueueTimeTracker] No X-Request-Start header found` (logged at `debug` level; see Logging below).
- If it appears on every request, your load balancer isn't sending the `X-Request-Start` header.
- This is the most common issue!

### Data Summary
```ruby
redis.zcard(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY)
redis.zcard(PumaMetricsEngine::MatrixController::REQUESTS_KEY)
redis.zrange(PumaMetricsEngine::MatrixController::QUEUE_TIMES_KEY, -10, -1)
```
- If counts are 0, no data is being stored.
- Check middleware status and headers above.

## Common Issues

### 1. Missing X-Request-Start Header

**Symptom**: Logs show `[QueueTimeTracker] No X-Request-Start header found` on every request

**Solution**: Configure your load balancer to send the header:

**nginx**:
```nginx
proxy_set_header X-Request-Start "t=${msec}";
```

**HAProxy**: Usually sets this automatically, but verify in your config.

**Cloud Load Balancers**: Check your provider's documentation for enabling request timing headers.

### 2. Middleware Not Registered

**Symptom**: The middleware check above returns `false`

**Solution**: 
- Ensure the engine is mounted in your routes
- Check that `PumaMetricsEngine::Engine` is loaded
- Verify the gem is in your Gemfile and bundle is up to date

### 3. Redis Connection Issues

**Symptom**: `redis.ping` raises an error

**Solution**:
- Verify `REDIS_URL` environment variable is set correctly
- Check Redis server is running and accessible
- Test connection: `redis-cli -u $REDIS_URL ping`

### 4. Data Not Persisting

**Symptom**: Middleware is registered, headers are present, but data counts are 0

**Solution**:
- Check Rails logs for `[QueueTimeTracker]` error messages
- Verify Redis write permissions
- Check if async threads are completing (may need to wait a moment after requests)

## Logging

The middleware logs debug information in production:

- `[QueueTimeTracker] X-Request-Start header: ...` - Shows when header is found
- `[QueueTimeTracker] No X-Request-Start header found` - Header missing
- `[QueueTimeTracker] Stored queue time: Xms` - Successful storage
- `[QueueTimeTracker] Invalid queue time: Xms (rejected)` - Queue time validation failed
- `[QueueTimeTracker] Error: ...` - Any errors during processing

Check your Rails logs for these messages to trace the flow.

## Testing Locally

To test if everything works:

1. Make a request with the header:
```bash
curl -H "X-Request-Start: t=$(ruby -e 'puts Time.now.to_f')" http://localhost:3000/your-endpoint
```

2. Wait a moment for async processing

3. Check the matrix endpoint:
```bash
curl http://localhost:3000/your-mount-path/matrix
```

