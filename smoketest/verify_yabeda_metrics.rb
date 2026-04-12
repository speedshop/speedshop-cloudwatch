require_relative "verify_support"

expected_metrics = {
  "Puma" => %w[backlog running busy_threads pool_capacity max_threads requests_count workers booted_workers old_workers],
  "RackQueue" => %w[duration],
  "Sidekiq" => %w[
    jobs_enqueued_total
    jobs_executed_total
    jobs_success_total
    job_latency
    job_runtime
    jobs_waiting_count
    active_workers_count
    jobs_scheduled_count
    jobs_retry_count
    jobs_dead_count
    active_processes
    queue_latency
  ]
}
forbidden_metrics = VerifySupport.built_in_metrics_by_namespace
expected_metric_counts = {
  "Puma" => {"workers" => 1},
  "RackQueue" => {"duration" => 1},
  "Sidekiq" => {"jobs_enqueued_total" => 1, "jobs_executed_total" => 1}
}
expected_unique_metric_counts = {
  "Puma" => 9,
  "RackQueue" => 1,
  "Sidekiq" => 12
}
expected_units = {
  "Puma" => {
    "workers" => ["None"],
    "running" => ["None"],
    "requests_count" => ["None"]
  },
  "RackQueue" => {
    "duration" => ["Seconds"]
  },
  "Sidekiq" => {
    "jobs_enqueued_total" => ["None"],
    "job_latency" => ["Seconds"],
    "job_runtime" => ["Seconds"],
    "queue_latency" => ["None"]
  }
}
expected_dimensions = {
  "Puma" => {
    "backlog" => %w[index],
    "running" => %w[index],
    "busy_threads" => %w[index],
    "pool_capacity" => %w[index],
    "max_threads" => %w[index],
    "requests_count" => %w[index],
    "workers" => [],
    "booted_workers" => [],
    "old_workers" => []
  },
  "RackQueue" => {
    "duration" => []
  },
  "Sidekiq" => {
    "jobs_enqueued_total" => %w[queue worker],
    "jobs_executed_total" => %w[queue worker],
    "jobs_success_total" => %w[queue worker],
    "job_latency" => %w[queue worker],
    "job_runtime" => %w[queue worker],
    "jobs_waiting_count" => %w[queue],
    "active_workers_count" => [],
    "jobs_scheduled_count" => [],
    "jobs_retry_count" => [],
    "jobs_dead_count" => [],
    "active_processes" => [],
    "queue_latency" => %w[queue]
  }
}
expected_sample_totals = {
  "RackQueue" => {"duration" => 20},
  "Sidekiq" => {
    "job_latency" => 20,
    "job_runtime" => 20
  }
}
expected_value_sums = {
  "Sidekiq" => {
    "jobs_enqueued_total" => 20,
    "jobs_executed_total" => 20,
    "jobs_success_total" => 20
  }
}

verifier = VerifySupport.new(metrics_file: File.join(__dir__, "tmp", "captured_metrics.csv"))
verifier.print_analysis_header

missing_metrics = []
verifier.print_captured_metrics(expected_metrics) { |metric| missing_metrics << metric }

forbidden_found = []
verifier.print_forbidden_metrics(forbidden_metrics) { |metric| forbidden_found << metric }

count_failures = []
verifier.print_metric_counts(expected_metric_counts) { |failure| count_failures << failure }

coverage_failures = []
verifier.print_unique_metric_counts(expected_unique_metric_counts) { |failure| coverage_failures << failure }

unit_failures = []
verifier.print_metric_units(expected_units) { |failure| unit_failures << failure }

dimension_failures = []
verifier.print_metric_dimensions(expected_dimensions) { |failure| dimension_failures << failure }

sample_total_failures = []
verifier.print_metric_sample_totals(expected_sample_totals) { |failure| sample_total_failures << failure }

value_sum_failures = []
verifier.print_metric_value_sums(expected_value_sums) { |failure| value_sum_failures << failure }

verifier.print_summary(expected_metrics)

if missing_metrics.empty? && forbidden_found.empty? && count_failures.empty? && coverage_failures.empty? &&
    unit_failures.empty? && dimension_failures.empty? && sample_total_failures.empty? && value_sum_failures.empty?
  puts "✅ All expected Yabeda metrics were captured!"
  puts "✅ No built-in metrics leaked into the Yabeda smoke test!"
  puts "✅ Metric coverage, units, dimensions, and traffic totals matched expectations!"
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
  puts "❌ #{count_failures.length} metric count assertions failed:"
  count_failures.each { |failure| puts "   - #{failure}" }
end

if coverage_failures.any?
  puts "❌ #{coverage_failures.length} metric coverage assertions failed:"
  coverage_failures.each { |failure| puts "   - #{failure}" }
end

if unit_failures.any?
  puts "❌ #{unit_failures.length} metric unit assertions failed:"
  unit_failures.each { |failure| puts "   - #{failure}" }
end

if dimension_failures.any?
  puts "❌ #{dimension_failures.length} metric dimension assertions failed:"
  dimension_failures.each { |failure| puts "   - #{failure}" }
end

if sample_total_failures.any?
  puts "❌ #{sample_total_failures.length} metric sample total assertions failed:"
  sample_total_failures.each { |failure| puts "   - #{failure}" }
end

if value_sum_failures.any?
  puts "❌ #{value_sum_failures.length} metric value sum assertions failed:"
  value_sum_failures.each { |failure| puts "   - #{failure}" }
end

exit 1
