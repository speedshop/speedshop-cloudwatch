require_relative "metric_contract"
require_relative "verify_support"

expected_metrics = SmoketestMetricContract.expected_metrics
expected_metric_counts = SmoketestMetricContract.expected_metric_counts
expected_unique_metric_counts = SmoketestMetricContract.expected_unique_metric_counts
expected_units = SmoketestMetricContract.expected_units
expected_dimensions = SmoketestMetricContract.expected_dimensions
allowed_value_kinds = SmoketestMetricContract.allowed_value_kinds
expected_sample_totals = SmoketestMetricContract.expected_sample_totals

verifier = VerifySupport.new(metrics_file: File.join(__dir__, "tmp", "captured_metrics.csv"))
verifier.print_analysis_header

missing_metrics = []
verifier.print_captured_metrics(expected_metrics) { |metric| missing_metrics << metric }

unexpected_metrics = []
verifier.print_unexpected_metrics(expected_metrics) { |metric| unexpected_metrics << metric }

count_failures = []
verifier.print_metric_counts(expected_metric_counts) { |failure| count_failures << failure }

coverage_failures = []
verifier.print_unique_metric_counts(expected_unique_metric_counts) { |failure| coverage_failures << failure }

unit_failures = []
verifier.print_metric_units(expected_units) { |failure| unit_failures << failure }

dimension_failures = []
verifier.print_metric_dimensions(expected_dimensions) { |failure| dimension_failures << failure }

kind_failures = []
verifier.print_metric_value_kinds(allowed_value_kinds) { |failure| kind_failures << failure }

sample_total_failures = []
verifier.print_metric_sample_totals(expected_sample_totals) { |failure| sample_total_failures << failure }

verifier.print_summary(expected_metrics)

if missing_metrics.empty? && unexpected_metrics.empty? && count_failures.empty? && coverage_failures.empty? &&
    unit_failures.empty? && dimension_failures.empty? && kind_failures.empty? && sample_total_failures.empty?
  puts "✅ The Yabeda parity smoketest matched the built-in contract!"
  puts "✅ Units, dimensions, datum kinds, and sample totals matched expectations!"
  exit 0
end

if missing_metrics.any?
  puts "❌ Missing #{missing_metrics.length} parity metrics:"
  missing_metrics.each { |metric| puts "   - #{metric}" }
end

if unexpected_metrics.any?
  puts "❌ Found #{unexpected_metrics.length} unexpected parity metrics:"
  unexpected_metrics.each { |metric| puts "   - #{metric}" }
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

if kind_failures.any?
  puts "❌ #{kind_failures.length} metric datum kind assertions failed:"
  kind_failures.each { |failure| puts "   - #{failure}" }
end

if sample_total_failures.any?
  puts "❌ #{sample_total_failures.length} metric sample total assertions failed:"
  sample_total_failures.each { |failure| puts "   - #{failure}" }
end

exit 1
