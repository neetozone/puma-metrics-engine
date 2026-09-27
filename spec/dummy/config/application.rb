# frozen_string_literal: true

require_relative "boot"

require "action_controller/railtie"

Bundler.require(*Rails.groups)
require "puma_metrics_engine"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.api_only = true
    # There is no config.ru, so Rails can't find the root on its own.
    config.root = File.expand_path("..", __dir__)
  end
end

