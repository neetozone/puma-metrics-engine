# frozen_string_literal: true

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"

# Load Rails and the engine
require File.expand_path("../dummy/config/environment", __FILE__)

abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories.
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
end

