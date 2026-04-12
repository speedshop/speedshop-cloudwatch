#!/usr/bin/env bash

set -e

SMOKETEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d /tmp/speedshop-cloudwatch-parity.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==============================================="
echo "  Speedshop Cloudwatch Yabeda Parity Diff"
echo "==============================================="
echo ""

echo "Step 1: Capturing built-in smoketest output..."
SMOKETEST_MODE=builtin \
SMOKETEST_TITLE="Speedshop Cloudwatch Built-in Baseline Smoketest" \
VERIFY_SCRIPT=verify_metrics.rb \
"$SMOKETEST_DIR"/run_smoketest.sh
cp "$SMOKETEST_DIR"/tmp/captured_metrics.csv "$TMP_DIR"/builtin.csv

echo "✓ Saved built-in baseline to $TMP_DIR/builtin.csv"
echo ""

echo "Step 2: Running Yabeda parity smoketest against the built-in baseline..."
SMOKETEST_MODE=yabeda_parity \
SMOKETEST_TITLE="Speedshop Cloudwatch Yabeda Parity Diff Smoketest" \
VERIFY_SCRIPT=verify_yabeda_parity_metrics.rb \
COMPARE_METRICS_FILE="$TMP_DIR"/builtin.csv \
"$SMOKETEST_DIR"/run_smoketest.sh
