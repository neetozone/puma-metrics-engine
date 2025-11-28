# frozen_string_literal: true

Rails.application.routes.draw do
  mount PumaMetricsEngine::Engine, at: "/puma_metrics_engine"
end

