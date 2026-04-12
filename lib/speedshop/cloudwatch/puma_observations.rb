# frozen_string_literal: true

require "speedshop/cloudwatch/observations"

module Speedshop
  module Cloudwatch
    module PumaObservations
      module_function

      def from_stats(stats)
        Observations::Puma.from_stats(stats)
      end
    end
  end
end
