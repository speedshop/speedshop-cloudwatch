#!/usr/bin/env bash

set -e

export SMOKETEST_MODE=yabeda
export SMOKETEST_TITLE="Speedshop Cloudwatch Yabeda Smoketest"
export VERIFY_SCRIPT=verify_yabeda_metrics.rb

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"/run_smoketest.sh
