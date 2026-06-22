# frozen_string_literal: true

require_relative "boot"

require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)
require "puma_metrics_engine"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults Rails::VERSION::STRING.to_f
    config.api_only = true
  end
end

