#!/bin/bash

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

# Function to run a command interactively
run_confirmed() {
    echo -e "\nCommand:\n$1"
    read -rp "Run this command? (y/n): " confirm
    if [[ $confirm == "y" ]]; then
        set +e
        eval "$1"
        local status=$?
        if [[ $status -ne 0 ]]; then
            echo -e "${RED}❌ Command failed: $1${NC}"
        fi
        return $status
    else
        echo "Skipped."
        return 1
    fi
}

# Function to offer unfreeze methods
check_and_offer_unfreeze() {
    local device=$1
    local output
    output=$(sudo hdparm -I "$device")

    if echo "$output" | grep -q "frozen"; then
        echo -e "${RED}⚠️  Drive is frozen. Secure erase may not work.${NC}"
        echo "Would you like to try to unfreeze it?"
        select method in "Sleep & Resume (may reboot system)" "Unplug & Replug manually" "Power cycle via sysfs" "Skip"; do
            case $REPLY in
                1)
                    echo -e "${YELLOW}Attempting suspend... Save your work. System will resume shortly.${NC}"
                    run_confirmed "systemctl suspend"
                    break
                    ;;
                2)
                    echo -e "${YELLOW}Please unplug and replug the drive: $device${NC}"
                    read -rp "Press Enter once the drive is reconnected..."
                    break
                    ;;
                3)
                    echo -e "${YELLOW}Attempting sysfs power cycle...${NC}"
                    dev_name=$(basename "$device")
                    run_confirmed "echo 1 | sudo tee /sys/block/$dev_name/device/delete"
                    sleep 1
                    run_confirmed "echo '- - -' | sudo tee /sys/class/scsi_host/host*/scan"
                    break
                    ;;
                4)
                    echo "Skipping unfreeze attempt."
                    break
                    ;;
                *)
                    echo "Invalid selection. Try again."
                    ;;
            esac
        done
    else
        echo -e "${GREEN}✅ Drive is not frozen. Proceeding with erase.${NC}"
    fi
}

echo -e "${YELLOW}Detecting all block devices...${NC}"
lsblk -o NAME,SIZE,ROTA,TYPE,MOUNTPOINT,MODEL

boot_dev=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//')
usb_devs=$(lsblk -S | awk '$3 == "usb" {print $1}')

echo -e "\n${YELLOW}Boot device: $boot_dev${NC}"
echo -e "${YELLOW}USB devices: $usb_devs${NC}"

candidates=()
for dev in /sys/block/*; do
    dev_name=$(basename "$dev")

    [[ $dev_name == loop* || $dev_name == ram* ]] && continue

    if echo "$usb_devs" | grep -qw "$dev_name"; then
        echo -e "${RED}Skipping USB device: $dev_name${NC}"
        continue
    fi

    if [[ "/dev/$dev_name" == "$boot_dev" ]]; then
        echo -e "${RED}Skipping boot device: $dev_name${NC}"
        continue
    fi

    candidates+=("$dev_name")
done

if [[ ${#candidates[@]} -eq 1 ]]; then
    target="${candidates[0]}"
    echo -e "${GREEN}Selected device: /dev/$target${NC}"
else
    echo -e "${YELLOW}Multiple candidates found. Choose one:${NC}"
    select dev in "${candidates[@]}"; do
        target=$dev
        break
    done
fi

DEVICE="/dev/$target"
echo -e "${GREEN}Targeting device: $DEVICE${NC}"

is_rotational=$(cat /sys/block/"${target%%[0-9]*}"/queue/rotational)

if [[ $is_rotational -eq 1 ]]; then
    echo "Drive $DEVICE is a HDD (rotational)."
    run_confirmed "sudo umount $DEVICE || true"
    run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=100M status=progress"
    run_confirmed "sudo hexdump -n 256 -C $DEVICE"

elif [[ $target == nvme* ]]; then
    echo "Drive $DEVICE is an NVMe SSD."

    if ! command -v nvme &> /dev/null; then
        echo -e "${YELLOW}nvme-cli not found. Installing...${NC}"
        run_confirmed "sudo apt update && sudo apt install -y nvme-cli"
    fi

    run_confirmed "sudo nvme list"

    echo -e "${YELLOW}Running NVMe secure erase (format --ses=1 --force)...${NC}"
    if run_confirmed "sudo nvme format $DEVICE --ses=1 --force"; then
        echo -e "${GREEN}✅ NVMe secure erase succeeded. Skipping dd.${NC}"
    else
        echo -e "${RED}❌ NVMe secure erase failed or skipped. Falling back to dd...${NC}"
        run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=100M status=progress"
    fi

    run_confirmed "sudo hexdump -n 256 -C $DEVICE"

elif [[ $target == mmcblk* ]]; then
    echo "Drive $DEVICE is an mmcblk (eMMC) SSD."
    run_confirmed "sudo apt update && sudo apt install -y mmc-utils"

    sectors=$(cat /sys/block/"$target"/size)
    let last_sector="$sectors - 1"
    echo "Device has $sectors sectors. Last sector: $last_sector"

    if run_confirmed "sudo mmc erase secure-erase 0 $last_sector $DEVICE"; then
        echo -e "${GREEN}✅ eMMC secure erase succeeded.${NC}"
    else
        echo -e "${RED}❌ eMMC erase failed. Falling back to dd...${NC}"
        run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=100M status=progress"
    fi

    run_confirmed "sudo hexdump -n 256 -C $DEVICE"

else
    echo "Drive $DEVICE is assumed to be a SATA SSD."

    echo "Checking if drive supports secure erase..."
    run_confirmed "sudo hdparm -I $DEVICE | grep -i security"

    echo "Checking if drive is frozen..."
    check_and_offer_unfreeze "$DEVICE"

    run_confirmed "sudo umount ${DEVICE}* || true"
    run_confirmed "sudo sync"

    echo "Setting temporary security password..."
    if run_confirmed "sudo hdparm --user-master u --security-set-pass Pwd1234! $DEVICE"; then
        echo "Trying enhanced secure erase first..."
        if run_confirmed "sudo hdparm --user-master u --security-erase-enhanced Pwd1234! $DEVICE"; then
            echo -e "${GREEN}✅ Enhanced secure erase succeeded. Skipping fallback and dd.${NC}"
        else
            echo -e "${RED}❌ Enhanced secure erase failed. Trying normal secure erase...${NC}"
            if run_confirmed "sudo hdparm --user-master u --security-erase Pwd1234! $DEVICE"; then
                echo -e "${GREEN}✅ Normal secure erase succeeded. Skipping dd.${NC}"
            else
                echo -e "${RED}❌ Normal secure erase failed. Falling back to dd...${NC}"
                run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=100M status=progress"
            fi
        fi
    else
        echo -e "${RED}❌ Failed to set security password. Falling back to dd...${NC}"
        run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=100M status=progress"
    fi

    run_confirmed "sudo dd if=$DEVICE bs=1M count=20 | hexdump -C"
fi

echo "Cleaning root Trash..."
run_confirmed "sudo rm -rf /root/.local/share/Trash/*"

echo -e "${GREEN}Wipe process complete.${NC}"

