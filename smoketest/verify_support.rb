require "cgi"
require "csv"

class VerifySupport
  attr_reader :captured_data, :captured_metrics, :metric_counts

  def initialize(metrics_file:)
    @metrics_file = metrics_file
    abort_unless_metrics_file_exists

    @captured_data = CSV.read(metrics_file, headers: true).map(&:to_h)
    abort_if_no_metrics

    @captured_metrics = Hash.new { |hash, key| hash[key] = [] }
    @metric_counts = Hash.new { |hash, key| hash[key] = Hash.new(0) }

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

      params.keys.grep(/MetricData\.member\.\d+\.MetricName/).each do |key|
        metric_name = params[key].first
        namespace_key = namespace.split("/").last
        captured_metrics[namespace_key] << metric_name unless captured_metrics[namespace_key].include?(metric_name)
        metric_counts[namespace_key][metric_name] += 1
      end
    end
  end
end
