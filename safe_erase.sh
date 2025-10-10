secure_erase_succeeded=false

if [[ $is_rotational -eq 1 ]]; then
    echo "Drive $DEVICE is a HDD (rotational)."
    run_confirmed "sudo umount $DEVICE || true"
    run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"

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
        secure_erase_succeeded=true
    else
        echo -e "${RED}❌ NVMe secure erase failed or skipped. Falling back to dd...${NC}"
        run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
    fi

elif [[ $target == mmcblk* ]]; then
    echo "Drive $DEVICE is an mmcblk (eMMC) SSD."
    run_confirmed "sudo apt update && sudo apt install -y mmc-utils"

    sectors=$(cat /sys/block/"$target"/size)
    let last_sector="$sectors - 1"
    echo "Device has $sectors sectors. Last sector: $last_sector"

    if run_confirmed "sudo mmc erase secure-erase 0 $last_sector $DEVICE"; then
        echo -e "${GREEN}✅ eMMC secure erase succeeded.${NC}"
        secure_erase_succeeded=true
    else
        echo -e "${RED}❌ eMMC erase failed. Falling back to dd...${NC}"
        run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
    fi

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
            secure_erase_succeeded=true
        else
            echo -e "${RED}❌ Enhanced secure erase failed. Trying normal secure erase...${NC}"
            if run_confirmed "sudo hdparm --user-master u --security-erase Pwd1234! $DEVICE"; then
                echo -e "${GREEN}✅ Normal secure erase succeeded. Skipping dd.${NC}"
                secure_erase_succeeded=true
            else
                echo -e "${RED}❌ Normal secure erase failed. Falling back to dd...${NC}"
                run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
            fi
        fi
    else
        echo -e "${RED}❌ Failed to set security password. Falling back to dd...${NC}"
        run_confirmed "sudo dd if=/dev/zero of=$DEVICE bs=$dd_bs status=progress $dd_flag"
    fi
fi

# 🛑 Only run post-wipe verification if secure erase was not successful
if [[ "$secure_erase_succeeded" != "true" ]]; then
    run_confirmed "sudo dd if=$DEVICE bs=1M count=20 | hexdump -C"
else
    echo -e "${YELLOW}Skipping post-wipe verification because secure erase succeeded.${NC}"
fi

echo "Cleaning root Trash..."
run_confirmed "sudo rm -rf /root/.local/share/Trash/*"

echo -e "${GREEN}Wipe process complete.${NC}"

