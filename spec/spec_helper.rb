# frozen_string_literal: true

require "bundler/setup"
require "puma_metrics_engine"
require "fakeredis/rspec"
require "timecop"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Clean up Redis between tests
  config.before(:each) do
    Redis.new(url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" }).flushdb
  end

  # Reset Timecop after each test
  config.after(:each) do
    Timecop.return
  end
end

