#!/bin/bash

# Check if smartmontools is installed
if ! command -v smartctl &> /dev/null; then
    echo "smartmontools not found. Installing..."
    sudo apt update && sudo apt install -y smartmontools
fi

# Check if nvme-cli is installed
if ! command -v nvme &> /dev/null; then
    echo "nvme-cli not found. Installing..."
    sudo apt update && sudo apt install -y nvme-cli
fi

while true; do
    echo "🔍 Detecting available drives..."

    # Get list of drives with size and model (filter sd* and nvme*)
    mapfile -t drives < <(lsblk -dn -o NAME,SIZE,MODEL,TYPE | grep 'disk')

    if [ ${#drives[@]} -eq 0 ]; then
        echo "❌ No drives found."
        exit 1
    fi

    # Display drives with size and model
    for i in "${!drives[@]}"; do
        read -r name size model type <<< "${drives[i]}"
        if [ -z "$model" ]; then
            echo "$((i+1))) $name  Size: $size"
        else
            echo "$((i+1))) $name  Size: $size  Model: $model"
        fi
    done

    read -rp "Enter the number of the drive to check: " selection

    if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#drives[@]} )); then
        echo "❌ Invalid selection."
        continue
    fi

    drive=$(echo "${drives[$((selection - 1))]}" | awk '{print $1}')
    type=$(echo "${drives[$((selection - 1))]}" | awk '{print $4}')
    DEVICE="/dev/$drive"

    if [ ! -b "$DEVICE" ]; then
        echo "❌ Device $DEVICE not found."
        continue
    fi

    # Try traditional SMART first
    echo "📋 Checking SMART support on $DEVICE..."

    device_types=( "auto" "nvme" "sat" "ata" )
    smart_supported=false
    smartctl_device_type="auto"

    for dt in "${device_types[@]}"; do
        if sudo smartctl -i -d "$dt" "$DEVICE" 2>/dev/null | grep -q "SMART support is: Enabled"; then
            smart_supported=true
            smartctl_device_type="$dt"
            break
        fi
    done

    if $smart_supported ; then
        echo "🩺 Running SMART health test (device type: $smartctl_device_type)..."
        sudo smartctl -H -d "$smartctl_device_type" "$DEVICE"

        read -rp "Do you want to see full SMART data? (y/n): " show_details
        if [[ "$show_details" =~ ^[Yy]$ ]]; then
            sudo smartctl -a -d "$smartctl_device_type" "$DEVICE"
            echo "▶️ Finished displaying SMART data."
        else
            echo "✅ Basic health check completed."
        fi

    elif [[ "$type" == "disk" && "$drive" == nvme* ]]; then
        # NVMe fallback
        echo "ℹ️ SMART not supported via smartctl, but NVMe drive detected. Using nvme-cli..."
        echo "🩺 Running NVMe health check on $DEVICE..."
        sudo nvme smart-log "$DEVICE"

        read -rp "Do you want to see detailed NVMe log pages? (y/n): " show_details
        if [[ "$show_details" =~ ^[Yy]$ ]]; then
            sudo nvme smart-log-add "$DEVICE"
            echo "▶️ Finished displaying NVMe extended data."
        else
            echo "✅ Basic NVMe health check completed."
        fi

    else
        echo "❌ SMART not supported or cannot be enabled on $DEVICE."
        continue
    fi

    read -rp "Do you want to check another drive? (y/n): " again
    if [[ ! "$again" =~ ^[Yy]$ ]]; then
        echo "👋 Goodbye!"
        exit 0
    fi

    echo ""
done

