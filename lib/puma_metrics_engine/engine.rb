# frozen_string_literal: true

module PumaMetricsEngine
  class Engine < ::Rails::Engine
    isolate_namespace PumaMetricsEngine

    config.app_middleware.use PumaMetricsEngine::QueueTimeTracker
  end
end
