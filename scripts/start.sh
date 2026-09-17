#!/bin/bash
set -euo pipefail
COUNT=${1:-300}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/dist/MirrorReward.app/Contents/MacOS/ad_watcher" "$COUNT"
