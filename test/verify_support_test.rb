# frozen_string_literal: true

require "test_helper"
require_relative "../smoketest/verify_support"

class VerifySupportTest < Minitest::Test
  def test_built_in_metrics_by_namespace_covers_all_builtin_metrics
    built_in_metrics = VerifySupport.built_in_metrics_by_namespace

    assert_includes built_in_metrics.fetch("Puma"), "OldWorkers"
    assert_includes built_in_metrics.fetch("Puma"), "Backlog"
    assert_includes built_in_metrics.fetch("Sidekiq"), "QueueSize"
    assert_includes built_in_metrics.fetch("Sidekiq"), "DefaultQueueLatency"
    assert_includes built_in_metrics.fetch("Rack"), "RequestQueueTime"
    assert_includes built_in_metrics.fetch("ActiveJob"), "QueueLatency"
  end
end
