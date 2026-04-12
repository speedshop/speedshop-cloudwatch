require_relative "metric_contract"
require_relative "verify_support"

expected_metrics = SmoketestMetricContract.expected_metrics
expected_metric_counts = SmoketestMetricContract.expected_metric_counts
expected_unique_metric_counts = SmoketestMetricContract.expected_unique_metric_counts
expected_units = SmoketestMetricContract.expected_units
expected_dimensions = SmoketestMetricContract.expected_dimensions
expected_value_kinds = SmoketestMetricContract.expected_value_kinds
expected_sample_totals = SmoketestMetricContract.expected_sample_totals
ignored_value_sums = SmoketestMetricContract.parity_ignored_value_sums
format_key = lambda do |key|
  namespace, metric_name, unit, datum_kind, dimensions = key
  dimensions_string = dimensions.map { |name, value| "#{name}=#{value}" }.join(", ")
  parts = ["#{namespace}/#{metric_name}", unit, datum_kind]
  parts << (dimensions_string.empty? ? "(no dimensions)" : dimensions_string)
  parts.join(" | ")
end

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
verifier.print_metric_value_kinds(expected_value_kinds) { |failure| kind_failures << failure }

sample_total_failures = []
verifier.print_metric_sample_totals(expected_sample_totals) { |failure| sample_total_failures << failure }

parity_diff_failures = []
compare_metrics_file = ENV["COMPARE_METRICS_FILE"]
if compare_metrics_file && File.exist?(compare_metrics_file)
  puts "Checking normalized parity diff against #{compare_metrics_file}:"
  puts

  builtin = VerifySupport.new(metrics_file: compare_metrics_file)
  builtin_summary = builtin.normalized_summary.each_with_object({}) do |entry, index|
    index[[entry[:namespace], entry[:metric_name], entry[:unit], entry[:datum_kind], entry[:dimensions]]] = entry
  end
  parity_summary = verifier.normalized_summary.each_with_object({}) do |entry, index|
    index[[entry[:namespace], entry[:metric_name], entry[:unit], entry[:datum_kind], entry[:dimensions]]] = entry
  end

  all_keys = (builtin_summary.keys + parity_summary.keys).uniq.sort_by(&:inspect)
  ignored_value_sum_keys = ignored_value_sums.map { |namespace, metric_name| [namespace, metric_name] }

  all_keys.each do |key|
    builtin_entry = builtin_summary[key]
    parity_entry = parity_summary[key]

    if builtin_entry.nil?
      failure = "unexpected normalized parity metric #{format_key.call(key)}"
      parity_diff_failures << failure
      puts "  ❌ #{failure}"
      next
    end

    if parity_entry.nil?
      failure = "missing normalized parity metric #{format_key.call(key)}"
      parity_diff_failures << failure
      puts "  ❌ #{failure}"
      next
    end

    if builtin_entry[:datum_count] != parity_entry[:datum_count]
      failure = "#{format_key.call(key)} datum count got #{parity_entry[:datum_count]}, expected #{builtin_entry[:datum_count]}"
      parity_diff_failures << failure
      puts "  ❌ #{failure}"
    else
      puts "  ✓ #{format_key.call(key)} datum count matched (#{parity_entry[:datum_count]})"
    end

    if builtin_entry[:sample_total] != parity_entry[:sample_total]
      failure = "#{format_key.call(key)} sample total got #{parity_entry[:sample_total]}, expected #{builtin_entry[:sample_total]}"
      parity_diff_failures << failure
      puts "  ❌ #{failure}"
    else
      puts "  ✓ #{format_key.call(key)} sample total matched (#{parity_entry[:sample_total]})"
    end

    next if ignored_value_sum_keys.include?([key[0], key[1]])

    if builtin_entry[:value_sum] != parity_entry[:value_sum]
      failure = "#{format_key.call(key)} value sum got #{parity_entry[:value_sum]}, expected #{builtin_entry[:value_sum]}"
      parity_diff_failures << failure
      puts "  ❌ #{failure}"
    else
      puts "  ✓ #{format_key.call(key)} value sum matched (#{parity_entry[:value_sum]})"
    end
  end

  puts
end

verifier.print_summary(expected_metrics)

if missing_metrics.empty? && unexpected_metrics.empty? && count_failures.empty? && coverage_failures.empty? &&
    unit_failures.empty? && dimension_failures.empty? && kind_failures.empty? && sample_total_failures.empty? &&
    parity_diff_failures.empty?
  puts "✅ The Yabeda parity smoketest matched the built-in contract!"
  puts "✅ Units, dimensions, datum kinds, and sample totals matched expectations!"
  puts "✅ The normalized parity diff stayed aligned with the built-in smoketest!" if compare_metrics_file
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

if parity_diff_failures.any?
  puts "❌ #{parity_diff_failures.length} normalized parity diff assertions failed:"
  parity_diff_failures.each { |failure| puts "   - #{failure}" }
end

exit 1
