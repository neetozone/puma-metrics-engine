# frozen_string_literal: true

PumaMetricsEngine::Engine.routes.draw do
  get "matrix", to: "matrix#show"
end
