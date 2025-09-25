#!/bin/bash

# Check if smartmontools is installed
if ! command -v smartctl &> /dev/null; then
    echo "smartmontools not found. Installing..."
    sudo apt update && sudo apt install -y smartmontools
fi

while true; do
    echo "🔍 Detecting available drives..."

    # Get list of drives (names only)
    drives=($(lsblk -d -o NAME,SIZE,MODEL | grep -E '^sd|^nvme' | awk '{print $1}'))

    # Display drives with numbers
    for i in "${!drives[@]}"; do
        name=${drives[$i]}
        info=$(lsblk -d -o NAME,SIZE,MODEL | grep "^$name")
        echo "$((i+1))) $info"
    done

    # Ask user to select drive by number
    read -p "Enter the number of the drive to check: " selection

    # Validate input
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "${#drives[@]}" ]; then
        echo "❌ Invalid selection."
        continue
    fi

    drive=${drives[$((selection-1))]}
    DEVICE="/dev/$drive"

    # Check if device exists
    if [ ! -b "$DEVICE" ]; then
        echo "❌ Device $DEVICE not found."
        continue
    fi

    if [[ "$drive" == nvme* ]]; then
        echo "📋 Detected NVMe drive. Displaying full SMART info..."
        sudo smartctl -a "$DEVICE"
        echo "▶️ Finished displaying SMART data."
    else
        echo "📋 Checking SMART support on $DEVICE..."
        smartctl -i "$DEVICE" | grep -q "SMART support is: Enabled"

        if [ $? -ne 0 ]; then
            echo "⚠️ SMART not enabled. Trying to enable it..."
            sudo smartctl -s on "$DEVICE"
            sleep 1
        fi

        smartctl -i "$DEVICE" | grep -q "SMART support is: Enabled"
        if [ $? -ne 0 ]; then
            echo "❌ SMART not supported or cannot be enabled on $DEVICE."
            continue
        fi

        echo "🩺 Running SMART health test..."
        sudo smartctl -H "$DEVICE"

        read -p "Do you want to see full SMART data? (y/n): " show_details
        if [[ "$show_details" =~ ^[Yy]$ ]]; then
            sudo smartctl -a "$DEVICE"
            echo "▶️ Finished displaying SMART data."
        else
            echo "✅ Basic health check completed."
        fi
    fi

    # Ask if user wants to check another drive
    read -p "Do you want to check another drive? (y/n): " again
    if [[ ! "$again" =~ ^[Yy]$ ]]; then
        echo "Goodbye!"
        exit 0
    fi

    echo ""
done

