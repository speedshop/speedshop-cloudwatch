require_relative "verify_support"

expected_metrics = {
  "Puma" => %w[workers booted_workers running pool_capacity max_threads],
  "RackQueue" => %w[duration],
  "Sidekiq" => %w[jobs_enqueued_total jobs_executed_total jobs_success_total job_runtime jobs_waiting_count queue_latency]
}
forbidden_metrics = {
  "Puma" => %w[Workers BootedWorkers],
  "Rack" => %w[RequestQueueTime],
  "ActiveJob" => %w[QueueLatency],
  "Sidekiq" => %w[EnqueuedJobs ProcessedJobs]
}
expected_metric_counts = {
  "Puma" => {"workers" => 1},
  "RackQueue" => {"duration" => 1},
  "Sidekiq" => {"jobs_enqueued_total" => 1, "jobs_executed_total" => 1}
}

verifier = VerifySupport.new(metrics_file: File.join(__dir__, "tmp", "captured_metrics.csv"))
verifier.print_analysis_header

missing_metrics = []
verifier.print_captured_metrics(expected_metrics) { |metric| missing_metrics << metric }

forbidden_found = []
verifier.print_forbidden_metrics(forbidden_metrics) { |metric| forbidden_found << metric }

count_failures = []
verifier.print_metric_counts(expected_metric_counts) { |failure| count_failures << failure }
verifier.print_summary(expected_metrics)

if missing_metrics.empty? && forbidden_found.empty? && count_failures.empty?
  puts "✅ All expected Yabeda metrics were captured!"
  puts "✅ No built-in metrics leaked into the Yabeda smoke test!"
  puts "✅ All Yabeda metric counts met expectations!"
  exit 0
end

if missing_metrics.any?
  puts "❌ Missing #{missing_metrics.length} Yabeda metrics:"
  missing_metrics.each { |metric| puts "   - #{metric}" }
end

if forbidden_found.any?
  puts "❌ Found #{forbidden_found.length} forbidden built-in metrics:"
  forbidden_found.each { |metric| puts "   - #{metric}" }
end

if count_failures.any?
  puts "❌ #{count_failures.length} Yabeda metric count assertions failed:"
  count_failures.each { |failure| puts "   - #{failure}" }
end

exit 1
