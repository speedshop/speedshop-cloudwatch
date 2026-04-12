# frozen_string_literal: true

# Portions of this code adapted from sidekiq-cloudwatchmetrics
# Copyright (c) 2018 Samuel Cochran
# https://github.com/sj26/sidekiq-cloudwatchmetrics
#
# The MIT License (MIT)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require "speedshop/cloudwatch/sidekiq_observations"

module Speedshop
  module Cloudwatch
    class Sidekiq
      def collect
        SidekiqObservations.collect.each do |observation|
          metric_mapper.report(
            metric: observation[:metric],
            value: observation[:value],
            dimensions: observation[:dimensions] || {},
            integration: :sidekiq
          )
        end
      rescue => e
        Speedshop::Cloudwatch.log_error("Failed to collect Sidekiq metrics: #{e.message}", e)
      end

      class << self
        def setup_lifecycle_hooks
          ::Sidekiq.configure_server do |sidekiq_config|
            if defined?(Sidekiq::Enterprise)
              sidekiq_config.on(:leader) do
                Speedshop::Cloudwatch.configure { |c| c.collectors << :sidekiq }
                Speedshop::Cloudwatch.start!
              end
            else
              sidekiq_config.on(:startup) do
                Speedshop::Cloudwatch.configure { |c| c.collectors << :sidekiq }
                Speedshop::Cloudwatch.start!
              end
            end

            sidekiq_config.on(:quiet) do
              Speedshop::Cloudwatch.stop!
            end

            sidekiq_config.on(:shutdown) do
              Speedshop::Cloudwatch.stop!
            end
          end
        end
      end

      private

      def metric_mapper
        Speedshop::Cloudwatch.metric_mapper
      end
    end
  end
end

Speedshop::Cloudwatch::Sidekiq.setup_lifecycle_hooks
