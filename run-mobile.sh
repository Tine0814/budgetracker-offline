#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
if command -v flutter >/dev/null 2>&1; then
  tracker_flutter="$(command -v flutter)"
elif [[ -x ../budget_tracker/.tooling/flutter/bin/flutter ]]; then
  tracker_flutter="../budget_tracker/.tooling/flutter/bin/flutter"
else
  echo 'Install Flutter and add it to PATH, then run this script again.' >&2
  exit 1
fi

exec "${tracker_flutter}" run "$@"
