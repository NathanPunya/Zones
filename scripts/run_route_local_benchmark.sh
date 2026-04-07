#!/bin/sh
# Times local route math (no Google API). Requires a concrete Simulator destination.
# Usage: ./scripts/run_route_local_benchmark.sh
#    or: ./scripts/run_route_local_benchmark.sh 'platform=iOS Simulator,name=iPhone 17'
set -e
cd "$(dirname "$0")/.."
DEST="${1:-platform=iOS Simulator,name=iPhone 17}"
xcodebuild -scheme Zones -destination "$DEST" \
  -only-testing:ZonesTests/RouteGenLocalTimingTests/testLocalSuggestionAndGeometryLatencyPerLevel \
  test 2>&1 | tee /tmp/zones_route_local_benchmark.log
echo "Log: /tmp/zones_route_local_benchmark.log"
