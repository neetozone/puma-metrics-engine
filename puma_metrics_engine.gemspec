# frozen_string_literal: true

require_relative "lib/puma_metrics_engine/version"

Gem::Specification.new do |spec|
  spec.name          = "puma_metrics_engine"
  spec.version       = PumaMetricsEngine::VERSION
  spec.authors       = ["Neeto"]
  spec.email         = ["engineering@bigbinary.com"]

  spec.summary       = "Rails engine that provides a /matrix endpoint for Puma metrics and queue time statistics"
  spec.description   = "A Rails engine that exposes Puma server metrics, queue time statistics, and request rate information via a /matrix endpoint"
  spec.homepage      = "https://github.com/bigbinary/puma_metrics_engine"
  spec.license       = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    [
      "lib/**/*",
      "app/**/*",
      "config/**/*",
      "README.md",
      "LICENSE.txt"
    ].flat_map { |pattern| Dir[pattern] }
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.0.0"

  spec.add_dependency "rails", ">= 7.0"
  spec.add_dependency "redis", ">= 5.0"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec-rails", "~> 6.0"
  spec.add_development_dependency "rspec-mocks", "~> 3.12"
  spec.add_development_dependency "fakeredis", "~> 0.9"
  spec.add_development_dependency "timecop", "~> 0.9"
  spec.add_development_dependency "webmock", "~> 3.18"
end
