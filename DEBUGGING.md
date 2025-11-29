# Debugging Production Issues

If you're not seeing queue time data in production, use the `/debug` endpoint to diagnose the issue.

## Quick Debug Steps

1. **Access the debug endpoint**: `GET /your-mount-path/debug`

2. **Check the response** for these key indicators:

### Middleware Status
```json
{
  "middleware": {
    "registered": true/false,
    "middleware_stack": [...],
    "note": "..."
  }
}
```
- If `registered: false`, the middleware isn't being loaded. Check that the engine is properly mounted.

### Redis Status
```json
{
  "redis": {
    "connected": true/false,
    "url": "redis://...",
    "keys": {
      "queue_times": true/false,
      "request_timestamps": true/false
    }
  }
}
```
- If `connected: false`, check your `REDIS_URL` environment variable.
- If keys don't exist, no data has been stored yet.

### Headers
```json
{
  "headers": {
    "x_request_start": "...",
    "http_x_request_start": "...",
    "all_x_headers": {...},
    "note": "Check if X-Request-Start header is being sent by your load balancer"
  }
}
```
- If both header fields are `null`, your load balancer isn't sending the `X-Request-Start` header.
- This is the most common issue!

### Data Summary
```json
{
  "data": {
    "queue_times_count": 0,
    "request_timestamps_count": 0,
    "recent_queue_times": [],
    "recent_timestamps": []
  }
}
```
- If counts are 0, no data is being stored.
- Check middleware status and headers above.

## Common Issues

### 1. Missing X-Request-Start Header

**Symptom**: `headers.x_request_start` and `headers.http_x_request_start` are both `null`

**Solution**: Configure your load balancer to send the header:

**nginx**:
```nginx
proxy_set_header X-Request-Start "t=${msec}";
```

**HAProxy**: Usually sets this automatically, but verify in your config.

**Cloud Load Balancers**: Check your provider's documentation for enabling request timing headers.

### 2. Middleware Not Registered

**Symptom**: `middleware.registered: false`

**Solution**: 
- Ensure the engine is mounted in your routes
- Check that `PumaMetricsEngine::Engine` is loaded
- Verify the gem is in your Gemfile and bundle is up to date

### 3. Redis Connection Issues

**Symptom**: `redis.connected: false`

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

3. Check the debug endpoint:
```bash
curl http://localhost:3000/your-mount-path/debug
```

4. Check the matrix endpoint:
```bash
curl http://localhost:3000/your-mount-path/matrix
```

