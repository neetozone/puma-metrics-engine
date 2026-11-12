# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Engine routes", type: :routing do
  routes { PumaMetricsEngine::Engine.routes }

  it "does not route /debug" do
    expect(get: "/debug").not_to be_routable
  end
end
