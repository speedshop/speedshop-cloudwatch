# frozen_string_literal: true

require "test_helper"
require "speedshop/cloudwatch/observations/rack"

class RackQueueObservationTest < SpeedshopCloudwatchTest
  def setup
    super
    @now_ms = 1_700_000_000_000.0
  end

  def test_parses_common_request_start_header_formats
    expectations = {
      "t=1699999999.875" => 125.0,
      "1699999999875" => 125.0,
      "t=1699999999875" => 125.0,
      "1699999999875000" => 125.0,
      "t=1699999999" => 1_000.0
    }

    expectations.each do |header_value, expected_ms|
      queue_time = request_queue_time("HTTP_X_REQUEST_START" => header_value)
      assert_in_delta expected_ms, queue_time, 0.001, header_value
    end
  end

  def test_falls_back_to_x_queue_start_when_x_request_start_is_invalid
    queue_time = request_queue_time(
      "HTTP_X_REQUEST_START" => "invalid",
      "HTTP_X_QUEUE_START" => "1699999999900"
    )

    assert_in_delta 100.0, queue_time, 0.001
  end

  def test_rejects_invalid_or_unreasonable_header_values
    ["invalid", "t=", "t=0", "t=915148800", "t=1700000030.001"].each do |header_value|
      assert_nil request_queue_time("HTTP_X_REQUEST_START" => header_value), header_value
    end
  end

  def test_uses_first_comma_separated_header_value
    assert_in_delta 125.0, request_queue_time("HTTP_X_REQUEST_START" => "1699999999875, 1699999999900"), 0.001
    assert_nil request_queue_time("HTTP_X_REQUEST_START" => "invalid, 1699999999900")
  end

  def test_prefers_t_equals_token_over_plain_token
    queue_time = request_queue_time("HTTP_X_REQUEST_START" => "1699999999000 t=1699999999.875")

    assert_in_delta 125.0, queue_time, 0.001
  end

  def test_subtracts_puma_request_body_wait_milliseconds
    queue_time = request_queue_time(
      "HTTP_X_REQUEST_START" => "1699999999900",
      "puma.request_body_wait" => 40
    )

    assert_in_delta 60.0, queue_time, 0.001
  end

  def test_ignores_invalid_puma_request_body_wait_values
    assert_in_delta 100.0, request_queue_time(
      "HTTP_X_REQUEST_START" => "1699999999900",
      "puma.request_body_wait" => "not-a-number"
    ), 0.001

    assert_in_delta 100.0, request_queue_time(
      "HTTP_X_REQUEST_START" => "1699999999900",
      "puma.request_body_wait" => -40
    ), 0.001
  end

  def test_clamps_to_zero_after_puma_request_body_wait_subtraction
    queue_time = request_queue_time(
      "HTTP_X_REQUEST_START" => "1699999999900",
      "puma.request_body_wait" => 200
    )

    assert_equal 0.0, queue_time
  end

  private

  def request_queue_time(env)
    Speedshop::Cloudwatch::Observations::Rack.request_queue_time(env, now_ms: @now_ms)
  end
end
