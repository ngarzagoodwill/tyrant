#!/bin/bash

# ---------------- Colors ----------------
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

# -------- RAM Selection Block --------
echo "Select your system RAM size:"
echo " 1) 2 GB"
echo " 2) 4 GB"
echo " 3) 8 GB"
echo " 4) 16 GB"
echo " 5) 32 GB"
read -rp "Enter a number (1–5): " ram_choice

case $ram_choice in
  1) dd_bs="32M" ;;
  2) dd_bs="64M" ;;
  3) dd_bs="100M" ;;
  4) dd_bs="128M" ;;
  5) dd_bs="256M" ;;
  *) echo "Invalid selection. Defaulting to bs=64M"; dd_bs="64M" ;;
esac

echo -e "${YELLOW}Block size for dd set to: $dd_bs${NC}"

# -------- dd Flush Method Selection --------
echo "Choose dd flush method:"
echo " 1) conv=fsync"
echo " 2) oflag=direct"
read -rp "Enter a number (1–2): " flush_choice

case $flush_choice in
  1) dd_flag="conv=fsync" ;;
  2) dd_flag="oflag=direct" ;;
  *) echo "Invalid selection. Defaulting to conv=fsync"; dd_flag="conv=fsync" ;;
esac

echo -e "${YELLOW}dd flush method set to: $dd_flag${NC}"

# -------- Function: run_confirmed --------
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

# -------- Function: check_and_offer_unfreeze --------
check_and_offer_unfreeze() {
  local device=$1
  local output
  output=$(sudo hdparm -I "$device")

  if echo "$output" | grep -q "frozen"; then
    echo -e "${RED}⚠️ Drive is frozen. Secure erase may not work.${NC}"
    echo "Would you like to try to unfreeze it?"
    select method in \
      "Sleep & Resume (may reboot system)" \
      "Unplug & Replug manually" \
      "Power cycle via sysfs" \
      "Skip"; do
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

# -------- Device Detection --------
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

# -------- Type Detection & Wipe --------
is_rotational=$(cat /sys/block/"${target%%[0-9]*}"/queue/rotational)

if [[ $is_rotational -eq 1 ]]; then
  echo "Drive $DEVICE is a HDD (rotational)."
  run_confirmed "sudo umount $DEVICE || true"
  run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
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
    run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
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
    run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
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
        run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
      fi
    fi
  else
    echo -e "${RED}❌ Failed to set security password. Falling back to dd...${NC}"
    run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
  fi

  run_confirmed "sudo dd if=$DEVICE bs=1M count=20 | hexdump -C"
fi

# -------- Final Cleanup --------
echo "Cleaning root Trash..."
run_confirmed "sudo rm -rf /root/.local/share/Trash/*"
echo -e "${GREEN}Wipe process complete.${NC}"

