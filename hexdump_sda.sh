#!/bin/bash

BYTES_TO_READ=256

while true; do
    # Get list of drives + partitions (exclude loop, ram, etc.)
    mapfile -t devices < <(lsblk -lnpo NAME,SIZE,TYPE,MOUNTPOINT | awk '$3 == "disk" {printf "%s %s [%s]", $1, $2, $3; if ($4) printf " mounted at %s", $4; print ""}')

    echo -e "\nAvailable devices and partitions:"
    for i in "${!devices[@]}"; do
      echo "$i) ${devices[$i]}"
    done

    # Prompt user to select a number
    read -rp "Enter the number of the device/partition to inspect: " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -ge "${#devices[@]}" ]; then
      echo "Invalid choice."
      exit 1
    fi

    # Extract device path (first field)
    DEVICE=$(echo "${devices[$choice]}" | awk '{print $1}')

    # Get size of selected block device (using sudo)
    SIZE=$(sudo blockdev --getsize64 "$DEVICE")

    echo -e "\nDevice: $DEVICE"
    echo "Size: $SIZE bytes"
    echo "Dumping $BYTES_TO_READ bytes at various offsets..."

    # Calculate offsets
    START_OFFSET=0
    QUARTER_OFFSET=$((SIZE / 4))
    MIDDLE_OFFSET=$((SIZE / 2))
    THREE_QUARTER_OFFSET=$((3 * SIZE / 4))
    END_OFFSET=$((SIZE - BYTES_TO_READ))

    # Prevent negative offset if device smaller than BYTES_TO_READ
    if [ $END_OFFSET -lt 0 ]; then
      END_OFFSET=0
    fi

    # Run hexdump at different offsets with sudo
    echo -e "\n=== START OF DEVICE (offset $START_OFFSET) ==="
    sudo hexdump -n $BYTES_TO_READ -s $START_OFFSET -C "$DEVICE"

    echo -e "\n=== QUARTER WAY (offset $QUARTER_OFFSET) ==="
    sudo hexdump -n $BYTES_TO_READ -s $QUARTER_OFFSET -C "$DEVICE"

    echo -e "\n=== MIDDLE (offset $MIDDLE_OFFSET) ==="
    sudo hexdump -n $BYTES_TO_READ -s $MIDDLE_OFFSET -C "$DEVICE"

    echo -e "\n=== THREE-QUARTERS (offset $THREE_QUARTER_OFFSET) ==="
    sudo hexdump -n $BYTES_TO_READ -s $THREE_QUARTER_OFFSET -C "$DEVICE"

    echo -e "\n=== END OF DEVICE (offset $END_OFFSET) ==="
    sudo hexdump -n $BYTES_TO_READ -s $END_OFFSET -C "$DEVICE"

    # Ask if user wants to repeat
    echo
    read -rp "Do you want to inspect another device? (y/n): " again
    if [[ "$again" != "y" && "$again" != "Y" ]]; then
        echo "Exiting..."
        break
    fi
done

