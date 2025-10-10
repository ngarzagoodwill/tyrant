#!/bin/bash

OUTPUT_DIR="/home/mint/Scripts/datadump"
OUTPUT_FILE="$OUTPUT_DIR/Deep_Hardware_Report.txt"

# Create output dir if needed
mkdir -p "$OUTPUT_DIR"

{
  echo "=== DEEP HARDWARE REPORT ==="
  echo "Generated: $(date)"
  echo ""

  # Manufacturer & Model
  echo "--- System Manufacturer & Model ---"
  if command -v dmidecode >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    echo "System Manufacturer: $(sudo dmidecode -s system-manufacturer 2>/dev/null)"
    echo "Product Name: $(sudo dmidecode -s system-product-name 2>/dev/null)"
  else
    echo "System Manufacturer: Unknown"
    echo "Product Name: Unknown"
  fi
  echo ""

  # CPU info
  echo "--- CPU Info (lscpu) ---"
  lscpu
  echo ""

  # Memory / RAM info
  echo "--- Memory / RAM Modules ---"
  if command -v dmidecode >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo dmidecode -t memory
  fi
  echo ""
  echo "--- Free / OS Memory ---"
  free -h
  echo ""

  # Storage
  echo "--- Disks / Partitions (lsblk) ---"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
  echo ""
  echo "--- Filesystem / UUIDs (blkid) ---"
  blkid
  echo ""

  # Graphics / Video
  echo "--- Graphics Controllers (lspci) ---"
  lspci | grep -i 'vga\|3d'
  echo ""

  # Display
  echo "--- Display / Resolution (xrandr) ---"
  if command -v xrandr >/dev/null 2>&1; then
    xrandr --verbose || xrandr
  else
    echo "xrandr not available"
  fi
  echo ""

  # Audio
  echo "--- Audio Devices (inxi / lspci) ---"
  if command -v inxi >/dev/null 2>&1; then
    inxi -A
  fi
  lspci | grep -i audio
  echo ""

  # Battery
  echo "--- Battery Info (upower) ---"
  BAT_PATH=$(upower -e | grep battery)
  if [ -n "$BAT_PATH" ]; then
    upower -i "$BAT_PATH"
  else
    echo "No battery detected"
  fi
  echo ""

  # Network
  echo "--- Network (inxi / lspci) ---"
  if command -v inxi >/dev/null 2>&1; then
    inxi -N
  fi
  lspci | grep -i ethernet
  lspci | grep -i wireless
  echo ""

  # Bluetooth
  echo "--- Bluetooth Info ---"
  if command -v hciconfig >/dev/null 2>&1; then
    hciconfig -a
  else
    echo "hciconfig not available"
  fi
  echo ""

  # Input / Touchscreen detection (best-effort)
  echo "--- Input Devices (xinput / libinput) ---"
  if command -v xinput >/dev/null 2>&1; then
    xinput --list
  fi
  if command -v libinput >/dev/null 2>&1; then
    libinput list-devices
  fi
  echo ""

  # macOS version detection via mounted Apple partitions
  echo "--- macOS version detection (if Apple partition mounted) ---"
  for dev in $(blkid | grep -Ei 'apfs|hfs' | cut -d: -f1); do
    MNT="/mnt/apple_$dev"
    sudo mkdir -p "$MNT"
    sudo mount -o ro $dev "$MNT" 2>/dev/null
    if [ -f "$MNT/System/Library/CoreServices/SystemVersion.plist" ]; then
      echo "Found macOS version on $dev:"
      grep -A1 "ProductVersion" "$MNT/System/Library/CoreServices/SystemVersion.plist" | tail -n1
    fi
    sudo umount "$MNT" 2>/dev/null
    sudo rmdir "$MNT"
  done
  echo ""

  # TPM Info
  echo "--- TPM Info (if available) ---"
  if command -v tpm2_getcap >/dev/null 2>&1; then
    sudo tpm2_getcap properties-fixed 2>/dev/null
  elif [ -c /dev/tpm0 ]; then
    echo "TPM device found: /dev/tpm0"
  else
    echo "No TPM detected"
  fi
  echo ""

  # Secure Boot Info
  echo "--- Secure Boot Status ---"
  if command -v mokutil >/dev/null 2>&1; then
    mokutil --sb-state 2>/dev/null
  else
    echo "mokutil not available"
  fi
  echo ""


} > "$OUTPUT_FILE"

echo "Deep hardware dump saved to: $OUTPUT_FILE"

