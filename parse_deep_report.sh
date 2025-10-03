#!/bin/bash

# Location of the deep hardware report
REPORT_FILE="$HOME/Scripts/datadump/Deep_Hardware_Report.txt"

# Return nothing if file is missing
[ ! -f "$REPORT_FILE" ] && exit 0

# Define legacy hardware match patterns (add more as needed)
LEGACY_PATTERNS=(
  "Pentium(R) Dual-Core"
  "Intel\(R\) Celeron"
  "Intel 4 Series Chipset"
  "82801JI"  # Old ICH10 audio chipset
  "Intel GMA"
  "Core2 Duo"
  "Core2 Quad"
  "ATI Radeon X"
  "NVIDIA GeForce 8"
  "NVIDIA GeForce 7"
)

# Check for legacy matches
for pattern in "${LEGACY_PATTERNS[@]}"; do
  if grep -qiE "$pattern" "$REPORT_FILE"; then
    echo "⚠️  This is a Legacy Machine, best suited for retro gaming/software or parts."
    exit 0
  fi
done

# No legacy hardware detected
exit 0

