#!/usr/bin/env bash

set -e

export SMOKETEST_MODE=yabeda_parity
export SMOKETEST_TITLE="Speedshop Cloudwatch Yabeda Parity Smoketest"
export VERIFY_SCRIPT=verify_yabeda_parity_metrics.rb

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/run_smoketest.sh
