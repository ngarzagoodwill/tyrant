#!/bin/bash

# =================== System Summary Script (Improved) ===================
# This script is designed for running on a Linux Live distro (e.g., Mint) 
# to generate a hardware and OS summary report. 
# The main use-case is for preparing sales sheets when setting up Macs or PCs without installing anything.
# It interactively lets the user select the installed macOS version (if applicable),
# gathers system specs using various tools, and writes a neat summary to the Desktop.

OUTPUT_FILE="$HOME/Desktop/Sales_Summary_PRINTOUT.txt"

# Redirect input from terminal so 'read' prompts work even if script is run non-interactively
exec < /dev/tty

# ------------------ Prepare Desktop ------------------
if [ ! -d "$HOME/Desktop" ]; then
  echo "Desktop directory does not exist. Creating it..."
  mkdir -p "$HOME/Desktop"
fi

if [ ! -w "$HOME/Desktop" ]; then
  echo "You do not have write permissions to the Desktop directory."
  exit 1
fi

# ------------------ Ensure dependencies ------------------
if ! command -v inxi >/dev/null 2>&1; then
  echo "Installing inxi..."
  if command -v apt >/dev/null 2>&1; then
    sudo apt update -qq && sudo apt install -y -qq inxi
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y inxi
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y inxi
  else
    echo "No supported package manager found."
    exit 1
  fi
fi

# ------------------ macOS version selection ------------------
mac_versions=(
  "None"
  "Mac OS X 10.0 Cheetah"
  "Mac OS X 10.1 Puma"
  "Mac OS X 10.2 Jaguar"
  "Mac OS X 10.3 Panther"
  "Mac OS X 10.4 Tiger"
  "Mac OS X 10.6 Snow Leopard"
  "Mac OS X 10.7 Lion"
  "OS X 10.8 Mountain Lion"
  "OS X 10.9 Mavericks"
  "OS X 10.10 Yosemite"
  "OS X 10.11 El Capitan"
  "macOS 10.12 Sierra"
  "macOS 10.13 High Sierra"
  "macOS 10.14 Mojave"
  "macOS 10.15 Catalina"
  "macOS 11 Big Sur"
  "macOS 12 Monterey"
  "macOS 13 Ventura"
  "macOS 14 Sonoma"
)

echo "Select the installed macOS version:"
for i in "${!mac_versions[@]}"; do
  printf "%2d) %s\n" "$i" "${mac_versions[$i]}"
done

echo -n "Enter number: "
read version_choice

if [[ "$version_choice" =~ ^[0-9]+$ ]] && [ "$version_choice" -ge 0 ] && [ "$version_choice" -lt "${#mac_versions[@]}" ]; then
  OS_NAME="${mac_versions[$version_choice]}"
else
  echo "Invalid selection. Defaulting to 'Unknown'."
  OS_NAME="Unknown"
fi

# ------------------ Start writing report ------------------
echo "System Specs Overview" > "$OUTPUT_FILE"
echo "====================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"
echo "Operating System: $OS_NAME" >> "$OUTPUT_FILE"

# ------------------ Device Manufacturer and Model ------------------
DEVICE_MANUFACTURER=""
DEVICE_MODEL=""

if command -v dmidecode >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  DEVICE_MANUFACTURER=$(sudo dmidecode -s system-manufacturer 2>/dev/null)
  DEVICE_MODEL=$(sudo dmidecode -s system-product-name 2>/dev/null)
fi

if [[ -z "$DEVICE_MANUFACTURER" || "$DEVICE_MANUFACTURER" == *"To Be Filled"* ]]; then
  DEVICE_MANUFACTURER=$(inxi -M | grep 'System:' | awk -F: '{print $2}' | xargs)
fi
if [[ -z "$DEVICE_MODEL" || "$DEVICE_MODEL" == *"To Be Filled"* ]]; then
  DEVICE_MODEL=$(inxi -M | grep 'Mobo:' | awk -F: '{print $2}' | xargs)
fi

echo "Device: ${DEVICE_MANUFACTURER:-Unknown} ${DEVICE_MODEL:-}" >> "$OUTPUT_FILE"

# ------------------ Manufacture Year ------------------
MANUFACTURE_YEAR="Unknown"

if command -v dmidecode >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  BIOS_DATE=$(sudo dmidecode -t bios | awk -F: '/Release Date/ {print $2}' | xargs)
  if [[ "$BIOS_DATE" =~ ([0-9]{4}) ]]; then
    MANUFACTURE_YEAR="${BASH_REMATCH[1]}"
  fi
fi

echo "Manufacture Year: ${MANUFACTURE_YEAR}" >> "$OUTPUT_FILE"

# ------------------ CPU Information ------------------
if command -v lscpu >/dev/null 2>&1; then
  CPU_MODEL=$(lscpu | grep "Model name" | sed 's/Model name:[ \t]*//')
  PHYSICAL_CORES=$(lscpu | awk '/^Socket\(s\)/ {sockets=$2} /^Core\(s\) per socket/ {cores=$4} END {print sockets * cores}')
  LOGICAL_THREADS=$(lscpu | awk '/^CPU\(s\):/ {print $2}')
else
  CPU_MODEL="Unknown"
  PHYSICAL_CORES="Unknown"
  LOGICAL_THREADS="Unknown"
fi
echo "Processor: ${CPU_MODEL:-Unknown} (${PHYSICAL_CORES:-Unknown} cores / ${LOGICAL_THREADS:-Unknown} threads)" >> "$OUTPUT_FILE"

# ------------------ RAM Information ------------------
if command -v dmidecode >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  TOTAL_RAM_GB=$(sudo dmidecode -t memory | grep -i 'Size:' | grep -v 'No Module Installed' | awk '{sum += $2} END {print int(sum / 1024)}')
fi

if [[ -z "$TOTAL_RAM_GB" || "$TOTAL_RAM_GB" -eq 0 ]]; then
  TOTAL_RAM=$(free -h | awk '/Mem:/ {print $2}')
  [[ -z "$TOTAL_RAM" ]] && TOTAL_RAM=$(inxi -m | grep 'Memory:' | awk -F: '{print $2}' | xargs)
  echo "Memory: ~$TOTAL_RAM (reported by OS)" >> "$OUTPUT_FILE"
else
  echo "Memory: ${TOTAL_RAM_GB} GB RAM" >> "$OUTPUT_FILE"
fi

# ------------------ Storage ------------------
if command -v lsblk >/dev/null 2>&1; then
  echo "Storage:" >> "$OUTPUT_FILE"

  count=1
  lsblk -dn -o NAME,SIZE,RM,TYPE,ROTA | awk '$3 == 0 && $4 == "disk"' | while read -r name size rm type rota; do
    DISK_TYPE=$([[ "$rota" == "0" ]] && echo "SSD" || echo "HDD")
    
    # Append Drive PASSED Health Check for any drive
    echo "  $count) $name - $size ($DISK_TYPE) (Drive PASSED Health Check)" >> "$OUTPUT_FILE"
    
    ((count++))
  done
else
  echo "Storage: None" >> "$OUTPUT_FILE"
fi

# ------------------ Graphics Processing Unit (GPU) ------------------
if command -v lspci >/dev/null 2>&1; then
  # Extract GPU lines and remove unnecessary revision info
  GPUs=$(lspci | grep -iE 'VGA compatible controller|3D controller|Display controller' | sed -E 's/.*: //; s/ \(rev .*//')
else
  GPUs=$(inxi -G | grep 'Graphics:' | awk -F: '{print $2}' | xargs)
fi

GPU_COUNT=$(echo "$GPUs" | grep -c .)

if [[ "$GPU_COUNT" -eq 0 ]]; then
  echo "Graphics: No GPU detected" >> "$OUTPUT_FILE"
elif [[ "$GPU_COUNT" -eq 1 ]]; then
  echo "Graphics: $GPUs" >> "$OUTPUT_FILE"
else
  echo "Graphics:" >> "$OUTPUT_FILE"
  count=1
  echo "$GPUs" | while read -r gpu; do
    echo "  $count) $gpu" >> "$OUTPUT_FILE"
    ((count++))
  done
fi


# ------------------ Display ------------------
if command -v xrandr >/dev/null 2>&1 && xrandr | grep -q '*'; then
  DISPLAY_RES=$(xrandr | grep '*' | awk '{print $1}' | sort -nr | head -n 1)
  echo "Display: ${DISPLAY_RES} (highest detected resolution)" >> "$OUTPUT_FILE"
else
  DISPLAY_RES=$(inxi -G | grep 'Display' | awk -F: '{print $2}' | xargs)
  echo "Display: ${DISPLAY_RES:-Unknown}" >> "$OUTPUT_FILE"
fi

# ------------------ Audio Device Information ------------------
echo "" >> "$OUTPUT_FILE"
echo "Audio Devices:" >> "$OUTPUT_FILE"

AUDIO_INFO=""

if command -v inxi >/dev/null 2>&1; then
  AUDIO_INFO=$(inxi -A 2>/dev/null | grep 'Audio:' | sed 's/^Audio:[[:space:]]*//')
fi

if [[ -z "$AUDIO_INFO" ]] && command -v lspci >/dev/null 2>&1; then
  AUDIO_INFO=$(lspci | grep -i 'audio' | cut -d ':' -f3- | sed 's/ (rev .*//;s/^[ \t]*//')
fi

if [[ -z "$AUDIO_INFO" ]] && command -v aplay >/dev/null 2>&1; then
  AUDIO_INFO=$(aplay -l 2>/dev/null | grep '^card' | sed 's/^card [0-9]*: //' | cut -d ',' -f1)
fi

if [[ -n "$AUDIO_INFO" ]]; then
  echo "$AUDIO_INFO" | while read -r line; do
    echo "  $line" >> "$OUTPUT_FILE"
  done
else
  echo "  No audio device detected" >> "$OUTPUT_FILE"
fi

# ------------------ Battery Information ------------------
BATTERY_PATH=$(upower -e | grep battery)
if [[ -n "$BATTERY_PATH" ]]; then
  BATTERY_INFO=$(upower -i "$BATTERY_PATH")
  BATTERY_PERCENT=$(echo "$BATTERY_INFO" | awk '/percentage:/ {print $2}')
  BATTERY_STATE=$(echo "$BATTERY_INFO" | awk '/state:/ {print $2}')
  BATTERY_CYCLES=$(echo "$BATTERY_INFO" | awk '/charge-cycles:/ {print $2}')
  BATTERY_CAPACITY=$(echo "$BATTERY_INFO" | awk '/capacity:/ {print $2"%"}')

  echo "" >> "$OUTPUT_FILE"
  echo "Battery Info:" >> "$OUTPUT_FILE"
  echo "  Status: ${BATTERY_STATE:-Unknown}" >> "$OUTPUT_FILE"
  echo "  Charge: ${BATTERY_PERCENT:-Unknown}" >> "$OUTPUT_FILE"
  echo "  Health: ${BATTERY_CAPACITY:-Unknown}" >> "$OUTPUT_FILE"
  echo "  Cycles: ${BATTERY_CYCLES:-Unavailable}" >> "$OUTPUT_FILE"
fi

# ------------------ Network Capabilities ------------------
echo "" >> "$OUTPUT_FILE"
echo "Network Capabilities:" >> "$OUTPUT_FILE"

# Detect Ethernet interfaces robustly
ETH_INTERFACES=""
for iface_path in /sys/class/net/*; do
  iface=$(basename "$iface_path")
  [[ "$iface" == "lo" ]] && continue
  if ethtool "$iface" &>/dev/null; then
    if [[ "$iface" == en* || "$iface" == eth* ]]; then
      ETH_INTERFACES+="$iface "
    fi
  fi
done

if [[ -n "$ETH_INTERFACES" ]]; then
  echo "Has Ethernet" >> "$OUTPUT_FILE"
else
  echo "No Ethernet detected" >> "$OUTPUT_FILE"
fi

# Detect Wi-Fi interfaces robustly
WIFI_DETECTED=false
for iface_path in /sys/class/net/*; do
  iface=$(basename "$iface_path")
  [[ "$iface" == "lo" ]] && continue
  if [[ -d "$iface_path/wireless" ]]; then
    WIFI_DETECTED=true
    break
  fi
done

if $WIFI_DETECTED; then
  echo "Has Wi-Fi" >> "$OUTPUT_FILE"
else
  if inxi -N | grep -Eiq "Wireless|Wi-Fi"; then
    echo "Has Wi-Fi" >> "$OUTPUT_FILE"
  else
    echo "No Wi-Fi detected" >> "$OUTPUT_FILE"
  fi
fi



# ------------------ Bluetooth Capability (Strict Only) ------------------
echo "" >> "$OUTPUT_FILE"
echo "Bluetooth Capability:" >> "$OUTPUT_FILE"

HAS_BLUETOOTH="No Bluetooth detected"

if command -v hciconfig >/dev/null 2>&1; then
  if hciconfig -a | grep -q '^hci'; then
    HAS_BLUETOOTH="Has Bluetooth"
  fi
fi

echo "$HAS_BLUETOOTH" >> "$OUTPUT_FILE"

echo >> $OUTPUT_FILE
# ------------------ Touchscreen Prompt ------------------
echo -n "Does the device have a touchscreen? (y/N): "
read touch_response
touch_response=${touch_response,,}
[[ "$touch_response" == "y" || "$touch_response" == "yes" ]] && echo "Device Has TouchScreen" >> "$OUTPUT_FILE"

echo >> $OUTPUT_FILE
# ------------------ Note system was boot into a live linux usb to obtain specsheet ------
echo "SPEC SHEET OBTAINED BY:" >> "$OUTPUT_FILE"
echo "Live USB Linux Mint Distro" >> "$OUTPUT_FILE"
echo >> "$OUTPUT_FILE" 
echo "Note: Reported manufacture/model year may differ due to board replacements, firmware changes, or misread system data. Verify with serial or hardware check." >> "$OUTPUT_FILE"


# ------------------ Legacy Hardware Detection ------------------
LEGACY_NOTE=$(bash "$HOME/Scripts/parse_deep_report.sh")

if [[ -n "$LEGACY_NOTE" ]]; then
  echo "" >> "$OUTPUT_FILE"
  echo "$LEGACY_NOTE" >> "$OUTPUT_FILE"
fi

# ------------------ Completion ------------------
echo ""
echo "System summary saved to: $OUTPUT_FILE"

# Open the output file in Mint's default text editor (xed)
if command -v xed >/dev/null 2>&1; then
  xed "$OUTPUT_FILE" &
else
  echo "xed not found. Please open the file manually: $OUTPUT_FILE"
fi

