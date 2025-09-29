#!/bin/bash

while true; do
    echo "🔍 Available drives:"

    # Get drives with size, model, and type, filter disks only
    mapfile -t drives < <(lsblk -dn -o NAME,SIZE,MODEL,TYPE | grep 'disk')

    if [ ${#drives[@]} -eq 0 ]; then
        echo "❌ No drives found."
        exit 1
    fi

    for i in "${!drives[@]}"; do
        # Parse the line into variables
        read -r name size model type <<< "${drives[i]}"

        if [ -z "$model" ]; then
            echo "$((i + 1))) $name  Size: $size"
        else
            echo "$((i + 1))) $name  Size: $size  Model: $model"
        fi
    done

    read -rp "Select a drive by number (1-${#drives[@]}): " selection

    # Validate input
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#drives[@]} )); then
        echo "❌ Invalid selection."
        continue
    fi

    drive=$(echo "${drives[$((selection - 1))]}" | awk '{print $1}')
    DEVICE="/dev/$drive"

    if [ ! -b "$DEVICE" ]; then
        echo "❌ Device $DEVICE not found."
        continue
    fi

    echo "📦 Selected drive: $DEVICE"

    if [[ "$drive" == nvme* ]]; then
        echo "📋 Detected NVMe drive. Displaying full SMART info..."
        sudo smartctl -a "$DEVICE"
        echo "✅ Finished displaying SMART data."
    else
        echo "📋 Checking SMART support on $DEVICE..."
        if ! smartctl -i "$DEVICE" | grep -q "SMART support is: Enabled"; then
            echo "⚠️ SMART not enabled. Attempting to enable it..."
            sudo smartctl -s on "$DEVICE"
            sleep 1
        fi

        if ! smartctl -i "$DEVICE" | grep -q "SMART support is: Enabled"; then
            echo "❌ SMART not supported or could not be enabled on $DEVICE."
            continue
        fi

        echo "🩺 Running SMART health check..."
        sudo smartctl -H "$DEVICE"

        read -rp "📊 Do you want to see full SMART data? (y/n): " show_details
        if [[ "$show_details" =~ ^[Yy]$ ]]; then
            sudo smartctl -a "$DEVICE"
            echo "✅ Finished displaying SMART data."
        else
            echo "✅ Basic health check completed."
        fi
    fi

    read -rp "🔁 Check another drive? (y/n): " again
    if [[ ! "$again" =~ ^[Yy]$ ]]; then
        echo "👋 Goodbye!"
        break
    fi

    echo ""
done

