#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
c++ -std=c++17 -Wall -Wextra -Werror -I "$HERE/rewards-stubs" "$HERE/test_rewards.cpp" -o "$OUT/test-rewards"
"$OUT/test-rewards"
