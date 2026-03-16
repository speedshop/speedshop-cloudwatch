require_relative "../lib/speedshop/cloudwatch/config"
require_relative "verify_support"

config = Speedshop::Cloudwatch::Config.instance
expected_metrics = config.metrics.transform_keys { |integration| config.namespaces[integration] }
  .transform_values { |metrics| metrics.map(&:to_s) }
forbidden_metrics = {"Test" => ["RakeTaskMetric"]}
expected_metric_counts = {
  "Rack" => {"RequestQueueTime" => 2},
  "ActiveJob" => {"QueueLatency" => 2},
  "Sidekiq" => {"EnqueuedJobs" => 1}
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
  puts "✅ All expected metrics were captured!"
  puts "✅ No forbidden metrics were captured!"
  puts "✅ All metric counts met expectations!"
  exit 0
end

if missing_metrics.any?
  puts "❌ Missing #{missing_metrics.length} metrics:"
  missing_metrics.each { |metric| puts "   - #{metric}" }
end

if forbidden_found.any?
  puts "❌ Found #{forbidden_found.length} forbidden metrics:"
  forbidden_found.each { |metric| puts "   - #{metric}" }
end

if count_failures.any?
  puts "❌ #{count_failures.length} metric count assertions failed:"
  count_failures.each { |failure| puts "   - #{failure}" }
end

exit 1
