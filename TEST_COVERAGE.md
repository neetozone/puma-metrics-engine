# Test Coverage

This document describes the comprehensive test suite for PumaMetricsEngine.

## Test Structure

The test suite uses RSpec and includes:

1. **Unit Tests** - Testing individual components in isolation
2. **Integration Tests** - Testing end-to-end functionality
3. **Edge Case Tests** - Testing error conditions and boundary cases

## Test Files

### `spec/puma_metrics_engine/queue_time_tracker_spec.rb`

Comprehensive tests for the `QueueTimeTracker` middleware covering:

- **Header Parsing**:
  - nginx format (`t=1234567890.123`)
  - Direct timestamp format
  - Microsecond timestamp conversion
  - Missing headers
  - Malformed headers
  - Empty strings

- **Queue Time Storage**:
  - Valid queue times are stored correctly
  - Negative queue times (clock skew) are rejected
  - Unreasonably large queue times (> 1 hour) are rejected
  - Request timestamps are always stored

- **Redis Operations**:
  - Data is stored in correct Redis keys
  - Multiple requests aggregate correctly
  - Cleanup removes old data (TTL)

- **Error Handling**:
  - Redis connection failures don't break requests
  - App errors are properly propagated
  - Tracking errors are logged but don't affect requests

### `spec/puma_metrics_engine/matrix_controller_spec.rb`

Comprehensive tests for the `MatrixController` covering:

- **Queue Time Statistics**:
  - Aggregate statistics (avg, p50, p95, p99, max, min)
  - Sample count
  - Empty data handling
  - Percentile calculations

- **Queue Time Windows**:
  - 10s, 20s, 30s window calculations
  - Correct filtering of data outside windows
  - Average calculations

- **Requests Per Minute**:
  - Accurate counting within 60-second window
  - Exclusion of old requests

- **Puma Stats**:
  - Puma stats when available
  - Fallback when Puma not available
  - Error handling

- **Error Handling**:
  - Redis connection failures
  - Graceful degradation

- **CSRF Protection**:
  - Token verification is skipped

### `spec/integration/queue_time_tracking_spec.rb`

End-to-end integration tests covering:

- **Full Request Flow**:
  - Queue time tracking through middleware
  - Data retrieval via `/matrix` endpoint
  - Complete request/response cycle

- **Multi-Worker Scenarios**:
  - Data aggregation across multiple workers
  - Shared Redis state

- **TTL and Cleanup**:
  - Old data is properly cleaned up
  - Recent data is preserved

- **Response Format**:
  - All required fields are present
  - Valid JSON structure

## Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/puma_metrics_engine/queue_time_tracker_spec.rb

# Run with documentation format
bundle exec rspec --format documentation

# Run specific test
bundle exec rspec spec/puma_metrics_engine/queue_time_tracker_spec.rb:45
```

## Test Dependencies

- `rspec-rails` - RSpec testing framework for Rails
- `rspec-mocks` - Mocking library
- `fakeredis` - In-memory Redis for testing
- `timecop` - Time manipulation for testing
- `webmock` - HTTP request stubbing

## Coverage Areas

✅ Header parsing (multiple formats)
✅ Queue time calculation and validation
✅ Redis storage and retrieval
✅ Data aggregation
✅ Time window calculations
✅ Percentile calculations
✅ Error handling
✅ Edge cases (negative times, large values, missing data)
✅ Multi-worker scenarios
✅ TTL and cleanup
✅ Integration testing

## Test Statistics

- **QueueTimeTracker**: ~25 test cases
- **MatrixController**: ~20 test cases
- **Integration**: ~5 test cases

Total: **~50 comprehensive test cases** covering all major functionality and edge cases.

