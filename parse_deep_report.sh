#!/bin/bash

# Location of the deep hardware report
REPORT_FILE="$HOME/Scripts/datadump/Deep_Hardware_Report.txt"

# Return nothing if file is missing
[ ! -f "$REPORT_FILE" ] && exit 0

# Define legacy hardware match patterns
LEGACY_PATTERNS=(
  # Intel CPUs
  "Pentium(R) Dual-Core"
  "Intel\(R\) Pentium\(R\) 4"
  "Intel\(R\) Pentium\(R\) D"
  "Intel\(R\) Pentium\(R\) M"
  "Intel\(R\) Celeron"
  "Intel\(R\) Atom"
  "Core2 Duo"
  "Core2 Quad"
  "Intel Core i[1-5]-[0-2][0-9]{2,3}[^0-9]"  # 1st/2nd gen Core i-series
  "Intel GMA"
  "Intel HD Graphics [1-4][0-9]{2}"          # HD 2000–4999
  "Intel 4 Series Chipset"
  "Intel G33"
  "Intel 945"
  "Intel 965"
  "Intel 915"

  # AMD CPUs
  "AMD Athlon 64"
  "AMD Athlon XP"
  "AMD Sempron"
  "AMD Turion"
  "AMD Phenom"
  "AMD FX[- ]"                               # FX-4100, FX 8350, etc.

  # GPUs - NVIDIA
  "NVIDIA GeForce 6"
  "NVIDIA GeForce 7"
  "NVIDIA GeForce 8"
  "NVIDIA GeForce FX"
  "NVIDIA Quadro FX"

  # GPUs - ATI/AMD
  "ATI Radeon X"
  "ATI Radeon HD [1-4][0-9]{2}"              # HD 2400, etc.
  "ATI Mobility Radeon"
  "AMD Radeon HD 5000"
  "AMD Radeon HD 6000"

  # Legacy Audio/Chipsets
  "82801"                                     # ICH family
  "82801JI"                                   # ICH10
  "ICH[6-9]"                                  # ICH6–ICH9
  "ICH10"
  "nForce 4"
  "nForce 7"
  "VIA Chipset"
  "SiS 741"
  "Matrox G200"
  "Realtek RTL8139"                           # Old 10/100 NIC
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

