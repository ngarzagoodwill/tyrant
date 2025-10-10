#!/bin/bash

# Location of the deep hardware report
REPORT_FILE="$HOME/Scripts/datadump/Deep_Hardware_Report.txt"

# Return nothing if file is missing
[ ! -f "$REPORT_FILE" ] && exit 0

# Legacy hardware patterns (unchanged from your original)
LEGACY_PATTERNS=(
  "Pentium(R) Dual-Core"
  "Intel\\(R\\) Pentium\\(R\\) 4"
  "Intel\\(R\\) Pentium\\(R\\) D"
  "Intel\\(R\\) Pentium\\(R\\) M"
  "Intel\\(R\\) Celeron"
  "Intel\\(R\\) Atom"
  "Core2 Duo"
  "Core2 Quad"
  "Intel Core i[1-5]-[0-2][0-9]{2,3}[^0-9]"  # 1st/2nd gen
  "Intel GMA"
  "Intel HD Graphics [1-4][0-9]{2}"
  "Intel 4 Series Chipset"
  "Intel G33"
  "Intel 945"
  "Intel 965"
  "Intel 915"
  "AMD Athlon 64"
  "AMD Athlon XP"
  "AMD Sempron"
  "AMD Turion"
  "AMD Phenom"
  "AMD FX[- ]"
  "NVIDIA GeForce 6"
  "NVIDIA GeForce 7"
  "NVIDIA GeForce 8"
  "NVIDIA GeForce FX"
  "NVIDIA Quadro FX"
  "ATI Radeon X"
  "ATI Radeon HD [1-4][0-9]{2}"
  "ATI Mobility Radeon"
  "AMD Radeon HD 5000"
  "AMD Radeon HD 6000"
  "82801"
  "82801JI"
  "ICH[6-9]"
  "ICH10"
  "nForce 4"
  "nForce 7"
  "VIA Chipset"
  "SiS 741"
  "Matrox G200"
  "Realtek RTL8139"
)

# Check for legacy hardware
for pattern in "${LEGACY_PATTERNS[@]}"; do
  if grep -qiE "$pattern" "$REPORT_FILE"; then
    echo "❌ This is a Legacy Machine — best for retro use or parts."
    exit 0
  fi
done

# --------------------------
# CPU Compatibility Check
# --------------------------
CPU_MODEL=$(grep -i "Model name" "$REPORT_FILE" | head -n1 | cut -d: -f2- | xargs)

# Default: not compatible
CPU_OK=false

# Intel 8th Gen and newer (Core i3/i5/i7/i9 8xxx or later)
if echo "$CPU_MODEL" | grep -Eq "Intel.*Core.*i[3579]-[89][0-9]{2,3}"; then
  CPU_OK=true
fi

# AMD Ryzen 2000 or newer (Ryzen 3/5/7/9 2xxx or newer)
if echo "$CPU_MODEL" | grep -Eq "AMD Ryzen [3579] [2-9][0-9]{2,3}"; then
  CPU_OK=true
fi

# --------------------------
# TPM Detection
# --------------------------
TPM_PRESENT=false
if grep -q "/dev/tpm0" <<< "$(ls /dev 2>/dev/null)"; then
  TPM_PRESENT=true
elif grep -iq "tpm" "$REPORT_FILE"; then
  TPM_PRESENT=true
fi

# --------------------------
# Secure Boot Detection
# --------------------------
SECURE_BOOT_ENABLED=false
if command -v mokutil >/dev/null 2>&1; then
  if mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    SECURE_BOOT_ENABLED=true
  fi
fi

# --------------------------
# Final Output
# --------------------------
echo ""

if $CPU_OK && $TPM_PRESENT && $SECURE_BOOT_ENABLED; then
  echo "✅ Fully Compatible with Windows 11 — CPU, TPM, and Secure Boot detected."
elif $CPU_OK; then
  echo "⚠️ CPU meets Windows 11 requirements, but TPM or Secure Boot is missing — Windows 10 is recommended."
else
  echo "⚠️ Not compatible with Windows 11 — CPU too old. Best suited for Windows 10 or Linux."
fi

exit 0

