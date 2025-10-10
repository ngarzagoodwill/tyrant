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

    # Get list of drives with size and model (sd*, nvme*, mmcblk*)
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

    # --- eMMC CHECK ---
    if [[ "$drive" == mmcblk* ]]; then
        echo "📦 Detected eMMC device: $DEVICE"

        life_time_path="/sys/block/$drive/device/life_time"
        eol_path="/sys/block/$drive/device/pre_eol_info"

        if [[ -f "$life_time_path" && -f "$eol_path" ]]; then
            echo "🩺 Checking eMMC health..."

            life_time=($(cat "$life_time_path"))
            pre_eol=$(cat "$eol_path")

            slc=${life_time[0]}
            mlc=${life_time[1]}

            interpret_wear() {
                case "$1" in
                    0x00) echo "0% used";;
                    0x01) echo "0–10% used";;
                    0x02) echo "10–20% used";;
                    0x03) echo "20–30% used";;
                    0x04) echo "30–40% used";;
                    0x05) echo "40–50% used";;
                    0x06) echo "50–60% used";;
                    0x07) echo "60–70% used";;
                    0x08) echo "70–80% used";;
                    0x09) echo "80–90% used";;
                    0x0a) echo "90–100% used";;
                    0x0b) echo "⚠️ Exceeded design life";;
                    *) echo "Unknown";;
                esac
            }

            interpret_eol() {
                case "$1" in
                    0x01) echo "Normal";;
                    0x02) echo "⚠️ Warning (80–90% life used)";;
                    0x03) echo "⚠️⚠️ Urgent (90%+ life used)";;
                    *) echo "Unknown";;
                esac
            }

            echo "📊 SLC (Type A) wear: $(interpret_wear $slc)"
            echo "📊 MLC (Type B) wear: $(interpret_wear $mlc)"
            echo "⏳ Pre EOL Info: $(interpret_eol $pre_eol)"

        else
            echo "❌ eMMC health data not available for $DEVICE."
        fi

    # --- NVMe CHECK ---
    elif [[ "$drive" == nvme* ]]; then
        echo "ℹ️ NVMe drive detected. Using nvme-cli..."
        echo "🩺 Running NVMe health check on $DEVICE..."
        sudo nvme smart-log "$DEVICE"

        read -rp "Do you want to see detailed NVMe log pages? (y/n): " show_details
        if [[ "$show_details" =~ ^[Yy]$ ]]; then
            sudo nvme smart-log-add "$DEVICE"
            echo "▶️ Finished displaying NVMe extended data."
        else
            echo "✅ Basic NVMe health check completed."
        fi

    # --- SATA/Other SMART Drives ---
    else
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
        else
            echo "❌ SMART not supported or cannot be enabled on $DEVICE."
        fi
    fi

    read -rp "Do you want to check another drive? (y/n): " again
    if [[ ! "$again" =~ ^[Yy]$ ]]; then
        echo "👋 Goodbye!"
        exit 0
    fi

    echo ""
done

