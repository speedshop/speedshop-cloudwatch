require "cgi"
require "csv"
require_relative "../lib/speedshop/cloudwatch/config"
require_relative "../lib/speedshop/cloudwatch/metrics"

class VerifySupport
  attr_reader :captured_data, :captured_metrics, :metric_counts, :datums

  def self.built_in_metrics_by_namespace(config: Speedshop::Cloudwatch::Config.instance)
    Speedshop::Cloudwatch::METRICS.transform_keys { |integration| config.namespaces.fetch(integration) }
      .transform_values { |metrics| metrics.map { |metric| metric.name.to_s } }
  end

  def initialize(metrics_file:)
    @metrics_file = metrics_file
    abort_unless_metrics_file_exists

    @captured_data = CSV.read(metrics_file, headers: true).map(&:to_h)
    abort_if_no_metrics

    @captured_metrics = Hash.new { |hash, key| hash[key] = [] }
    @metric_counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    @datums = []

    parse_captured_data
  end

  def print_analysis_header
    puts "📊 Analyzing #{captured_data.length} CloudWatch API calls..."
    puts
  end

  def print_captured_metrics(expected_metrics)
    puts "Captured metrics by integration:"
    puts

    expected_metrics.each do |namespace, metrics|
      puts "#{namespace}:"
      captured = captured_metrics[namespace] || []

      metrics.each do |metric|
        if captured.include?(metric)
          puts "  ✓ #{metric}"
        else
          puts "  ❌ #{metric} (MISSING)"
          yield "#{namespace}/#{metric}" if block_given?
        end
      end

      puts
    end
  end

  def print_unexpected_metrics(expected_metrics)
    puts "Checking for unexpected metrics:"
    puts

    expected = expected_metrics.transform_values { |metrics| Array(metrics).map(&:to_s).sort }
    namespaces = (captured_metrics.keys + expected.keys).uniq.sort

    namespaces.each do |namespace|
      actual_metrics = Array(captured_metrics[namespace]).sort
      unexpected_metrics = actual_metrics - Array(expected[namespace])

      if unexpected_metrics.empty?
        puts "  ✓ #{namespace}: no unexpected metrics"
      else
        unexpected_metrics.each do |metric|
          puts "  ❌ #{namespace}/#{metric} (UNEXPECTED)"
          yield "#{namespace}/#{metric}" if block_given?
        end
      end
    end

    puts
  end

  def print_forbidden_metrics(forbidden_metrics)
    puts "Checking for forbidden metrics (should NOT be present):"
    puts

    forbidden_metrics.each do |namespace, metrics|
      captured = captured_metrics[namespace] || []

      metrics.each do |metric|
        if captured.include?(metric)
          puts "  ❌ #{namespace}/#{metric} (SHOULD NOT BE PRESENT)"
          yield "#{namespace}/#{metric}" if block_given?
        else
          puts "  ✓ #{namespace}/#{metric} correctly not captured"
        end
      end
    end

    puts
  end

  def print_metric_counts(expected_counts)
    puts "Checking metric counts (based on generated traffic):"
    puts

    expected_counts.each do |namespace, metrics|
      puts "#{namespace}:"

      metrics.each do |metric, minimum_count|
        actual_count = metric_counts[namespace][metric]
        if actual_count >= minimum_count
          puts "  ✓ #{metric}: #{actual_count} (expected >= #{minimum_count})"
        else
          puts "  ❌ #{metric}: #{actual_count} (expected >= #{minimum_count})"
          yield "#{namespace}/#{metric}: got #{actual_count}, expected >= #{minimum_count}" if block_given?
        end
      end

      puts
    end
  end

  def print_unique_metric_counts(expected_counts)
    puts "Checking unique metric coverage:"
    puts

    expected_counts.each do |namespace, minimum_count|
      actual_count = captured_metrics.fetch(namespace, []).length
      if actual_count >= minimum_count
        puts "  ✓ #{namespace}: #{actual_count} unique metrics (expected >= #{minimum_count})"
      else
        puts "  ❌ #{namespace}: #{actual_count} unique metrics (expected >= #{minimum_count})"
        yield "#{namespace}: got #{actual_count}, expected >= #{minimum_count}" if block_given?
      end
    end

    puts
  end

  def print_metric_units(expected_units)
    puts "Checking metric units:"
    puts

    expected_units.each do |namespace, metrics|
      puts "#{namespace}:"

      metrics.each do |metric, expected_unit|
        actual_units = metric_units(namespace: namespace, metric_name: metric)
        expected = Array(expected_unit).sort
        if actual_units == expected
          puts "  ✓ #{metric}: #{format_values(actual_units)}"
        else
          puts "  ❌ #{metric}: #{format_values(actual_units)} (expected #{format_values(expected)})"
          yield "#{namespace}/#{metric}: got #{format_values(actual_units)}, expected #{format_values(expected)}" if block_given?
        end
      end

      puts
    end
  end

  def print_metric_dimensions(expected_dimensions)
    puts "Checking metric dimensions:"
    puts

    expected_dimensions.each do |namespace, metrics|
      puts "#{namespace}:"

      metrics.each do |metric, expected_dimension_names|
        actual_dimension_names = metric_dimension_names(namespace: namespace, metric_name: metric)
        expected = Array(expected_dimension_names).map(&:to_s).sort
        if actual_dimension_names == expected
          puts "  ✓ #{metric}: #{format_values(actual_dimension_names)}"
        else
          puts "  ❌ #{metric}: #{format_values(actual_dimension_names)} (expected #{format_values(expected)})"
          yield "#{namespace}/#{metric}: got #{format_values(actual_dimension_names)}, expected #{format_values(expected)}" if block_given?
        end
      end

      puts
    end
  end

  def print_metric_sample_totals(expected_totals)
    puts "Checking metric sample totals:"
    puts

    expected_totals.each do |namespace, metrics|
      puts "#{namespace}:"

      metrics.each do |metric, minimum_total|
        actual_total = metric_sample_total(namespace: namespace, metric_name: metric)
        if actual_total >= minimum_total
          puts "  ✓ #{metric}: #{format_number(actual_total)} samples (expected >= #{minimum_total})"
        else
          puts "  ❌ #{metric}: #{format_number(actual_total)} samples (expected >= #{minimum_total})"
          yield "#{namespace}/#{metric}: got #{format_number(actual_total)} samples, expected >= #{minimum_total}" if block_given?
        end
      end

      puts
    end
  end

  def print_metric_value_sums(expected_sums)
    puts "Checking metric value sums:"
    puts

    expected_sums.each do |namespace, metrics|
      puts "#{namespace}:"

      metrics.each do |metric, minimum_sum|
        actual_sum = metric_value_sum(namespace: namespace, metric_name: metric)
        if actual_sum >= minimum_sum
          puts "  ✓ #{metric}: #{format_number(actual_sum)} total value (expected >= #{minimum_sum})"
        else
          puts "  ❌ #{metric}: #{format_number(actual_sum)} total value (expected >= #{minimum_sum})"
          yield "#{namespace}/#{metric}: got #{format_number(actual_sum)} total value, expected >= #{minimum_sum}" if block_given?
        end
      end

      puts
    end
  end

  def print_metric_value_kinds(expected_kinds)
    puts "Checking metric datum kinds:"
    puts

    expected_kinds.each do |namespace, metrics|
      puts "#{namespace}:"

      metrics.each do |metric, expected_kind|
        actual_kinds = metric_value_kinds(namespace: namespace, metric_name: metric)
        expected = Array(expected_kind).map(&:to_s).sort
        if actual_kinds == expected
          puts "  ✓ #{metric}: #{format_values(actual_kinds)}"
        else
          puts "  ❌ #{metric}: #{format_values(actual_kinds)} (expected #{format_values(expected)})"
          yield "#{namespace}/#{metric}: got #{format_values(actual_kinds)}, expected #{format_values(expected)}" if block_given?
        end
      end

      puts
    end
  end

  def metric_units(namespace:, metric_name:)
    datums_for(namespace: namespace, metric_name: metric_name).map { |datum| datum[:unit] }.compact.uniq.sort
  end

  def metric_dimension_names(namespace:, metric_name:)
    datums_for(namespace: namespace, metric_name: metric_name).flat_map { |datum| datum[:dimensions].keys }.uniq.sort
  end

  def metric_dimension_values(namespace:, metric_name:, dimension_name:)
    datums_for(namespace: namespace, metric_name: metric_name).map { |datum| datum[:dimensions][dimension_name] }.compact.uniq.sort
  end

  def metric_sample_total(namespace:, metric_name:)
    datums_for(namespace: namespace, metric_name: metric_name).inject(0.0) do |sum, datum|
      sum + datum_sample_count(datum)
    end
  end

  def metric_value_sum(namespace:, metric_name:)
    datums_for(namespace: namespace, metric_name: metric_name).inject(0.0) do |sum, datum|
      sum + datum_value_sum(datum)
    end
  end

  def metric_value_kinds(namespace:, metric_name:)
    datums_for(namespace: namespace, metric_name: metric_name).map { |datum| datum_kind(datum) }.uniq.sort
  end

  def normalized_summary
    datums.group_by do |datum|
      [
        datum[:namespace],
        datum[:metric_name],
        datum[:unit],
        datum_kind(datum),
        normalized_dimensions_hash(datum[:dimensions])
      ]
    end.map do |(namespace, metric_name, unit, kind, dimensions), grouped_datums|
      {
        namespace: namespace,
        metric_name: metric_name,
        unit: unit,
        datum_kind: kind,
        dimensions: dimensions,
        datum_count: grouped_datums.length,
        sample_total: grouped_datums.sum { |datum| datum_sample_count(datum) },
        value_sum: grouped_datums.sum { |datum| datum_value_sum(datum) }
      }
    end.sort_by do |entry|
      [entry[:namespace], entry[:metric_name], entry[:unit].to_s, entry[:datum_kind], entry[:dimensions].map(&:join)]
    end
  end

  def print_summary(expected_metrics)
    puts "Summary:"
    puts "  Total API calls: #{captured_data.length}"
    puts "  Total unique metrics: #{captured_metrics.values.flatten.uniq.length}"
    puts "  Expected metrics: #{expected_metrics.values.flatten.length}"
    puts "  Captured metrics: #{captured_metrics.values.flatten.uniq.length}"
    puts
  end

  private

  attr_reader :metrics_file

  def abort_unless_metrics_file_exists
    return if File.exist?(metrics_file)

    puts "❌ No metrics file found at #{metrics_file}"
    exit 1
  end

  def abort_if_no_metrics
    return unless captured_data.empty?

    puts "❌ No metrics were captured!"
    exit 1
  end

  def parse_captured_data
    captured_data.each do |request|
      params = CGI.parse(request.fetch("body"))
      namespace = params["Namespace"]&.first
      next unless namespace

      namespace_key = namespace.split("/").last
      datum_indexes(params).each do |index|
        metric_name = params["MetricData.member.#{index}.MetricName"]&.first
        next unless metric_name

        datums << {
          namespace: namespace_key,
          metric_name: metric_name,
          unit: params["MetricData.member.#{index}.Unit"]&.first,
          dimensions: parse_dimensions(params, index),
          value: parse_float(params["MetricData.member.#{index}.Value"]&.first),
          values: parse_number_list(params, "MetricData.member.#{index}.Values"),
          counts: parse_number_list(params, "MetricData.member.#{index}.Counts"),
          statistic_values: parse_statistic_values(params, index)
        }

        captured_metrics[namespace_key] << metric_name unless captured_metrics[namespace_key].include?(metric_name)
        metric_counts[namespace_key][metric_name] += 1
      end
    end
  end

  def datum_indexes(params)
    params.keys.grep(/\AMetricData\.member\.\d+\.MetricName\z/).map do |key|
      key[/\AMetricData\.member\.(\d+)\.MetricName\z/, 1].to_i
    end.sort
  end

  def parse_dimensions(params, metric_index)
    params.keys.grep(/\AMetricData\.member\.#{metric_index}\.Dimensions\.member\.\d+\.Name\z/).each_with_object({}) do |key, dimensions|
      dimension_index = key[/\.member\.(\d+)\.Name\z/, 1]
      name = params["MetricData.member.#{metric_index}.Dimensions.member.#{dimension_index}.Name"]&.first
      value = params["MetricData.member.#{metric_index}.Dimensions.member.#{dimension_index}.Value"]&.first
      dimensions[name] = value if name
    end
  end

  def parse_number_list(params, prefix)
    keys = params.keys.grep(/\A#{Regexp.escape(prefix)}\.member\.\d+\z/)
    values = keys.sort_by { |key| key[/\.member\.(\d+)\z/, 1].to_i }
      .map { |key| parse_float(params[key]&.first) }
    values unless values.empty?
  end

  def parse_statistic_values(params, metric_index)
    prefix = "MetricData.member.#{metric_index}.StatisticValues"
    sample_count = parse_float(params["#{prefix}.SampleCount"]&.first)
    sum = parse_float(params["#{prefix}.Sum"]&.first)
    minimum = parse_float(params["#{prefix}.Minimum"]&.first)
    maximum = parse_float(params["#{prefix}.Maximum"]&.first)

    return unless [sample_count, sum, minimum, maximum].any?

    {
      sample_count: sample_count || 0.0,
      sum: sum || 0.0,
      minimum: minimum || 0.0,
      maximum: maximum || 0.0
    }
  end

  def datums_for(namespace:, metric_name:)
    datums.select { |datum| datum[:namespace] == namespace && datum[:metric_name] == metric_name }
  end

  def datum_sample_count(datum)
    return datum[:counts]&.sum || datum[:values].size if datum[:values]

    statistic_values = datum[:statistic_values]
    return statistic_values[:sample_count] if statistic_values

    1.0
  end

  def datum_value_sum(datum)
    if datum[:values]
      counts = datum[:counts] || Array.new(datum[:values].size, 1.0)
      return datum[:values].zip(counts).sum { |value, count| value * count }
    end

    statistic_values = datum[:statistic_values]
    return statistic_values[:sum] if statistic_values

    datum[:value] || 0.0
  end

  def datum_kind(datum)
    return "values_counts" if datum[:values]

    datum[:statistic_values] ? "statistic_values" : "value"
  end

  def normalized_dimensions_hash(dimensions)
    dimensions.keys.sort.map { |name| [name, dimensions[name]] }
  end

  def parse_float(value)
    value && value.to_f
  end

  def format_number(number)
    return number.to_i.to_s if number.finite? && number == number.to_i

    format("%.3f", number)
  end

  def format_values(values)
    values.empty? ? "(none)" : values.join(", ")
  end
end
