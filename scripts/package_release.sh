#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

mkdir -p build
tar czf build/dwc_i2s_audio_hub_rtl_release.tgz rtl docs sim constraints lint README.md
echo "Created build/dwc_i2s_audio_hub_rtl_release.tgz"
