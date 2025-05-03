#!/bin/bash
set -e

# Full Pi Restore Script

show_help() {
    echo "Usage: $0 [--dry-run] [-h|--help]"
    echo
    echo "Options:"
    echo "  -d      --dry-run       Simulate restore without writing to disk"
    echo "  -h      --help          Show this help message"
    exit 0
}

# Flags
DRY_RUN=false

# Parse args
for arg in "$@"; do
    case "$arg" in
    -d | --dry-run) DRY_RUN=true ;;
    -h | --help) show_help ;;
    *)
        echo "Unknown option: $arg"
        show_help
        ;;
    esac
done

# Prompt for dry run if not already specified
if ! $DRY_RUN; then
    read -r -p "Do you want to perform a dry run first? [y/N]: " DRY_CHOICE
    DRY_CHOICE=${DRY_CHOICE,,}
    if [[ "$DRY_CHOICE" == "y" ]]; then
        DRY_RUN=true
        echo
    fi
fi

if $DRY_RUN; then
    echo "=== Raspberry Pi Full Restore (Dry Run) ==="
else
    echo "=== Raspberry Pi Full Restore ==="
fi
echo

# Ask for NAS IP
read -r -p "Enter NAS IP address: " NAS_IP
NAS_SHARE="/volume1/pi-server-backups"
MOUNT_POINT="/mnt/pi-backups"

echo
echo "[1/5] Installing required tools..."
sudo apt update -qq
sudo apt install -y nfs-common

echo
echo "[2/5] Mounting NAS share..."
sudo mkdir -p "$MOUNT_POINT"
if mountpoint -q "$MOUNT_POINT"; then
    echo "Already mounted: $MOUNT_POINT"
else
    sudo mount -o rw "$NAS_IP:$NAS_SHARE" "$MOUNT_POINT"
fi

echo
echo "[3/5] Available backups:"
mapfile -t BACKUPS < <(
    sudo find "$MOUNT_POINT" -maxdepth 1 -name "pi-backup-*.img.gz" -printf "%T@ %p\n" 2>/dev/null |
        sort -n -r |
        cut -d' ' -f2-
)

if [ "${#BACKUPS[@]}" -eq 0 ]; then
    echo "No backups found in $MOUNT_POINT. Exiting."
    exit 1
fi

for i in "${!BACKUPS[@]}"; do
    echo "$((i + 1)). ${BACKUPS[$i]##*/}"
done

read -r -p "Select backup to restore [1-${#BACKUPS[@]}]: " CHOICE
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || ((CHOICE < 1 || CHOICE > ${#BACKUPS[@]})); then
    echo "Invalid backup selection."
    exit 1
fi
FILE="${BACKUPS[$((CHOICE - 1))]}"

echo
echo "[4/5] Available storage devices:"
mapfile -t DEVICES < <(lsblk -dpno NAME,SIZE | grep -v "/boot\\|/root")

if [ "${#DEVICES[@]}" -eq 0 ]; then
    echo "No storage devices found. Exiting."
    exit 1
fi

for i in "${!DEVICES[@]}"; do
    echo "$((i + 1)). ${DEVICES[$i]}"
done

read -r -p "Select disk to restore to [1-${#DEVICES[@]}]: " DISK_CHOICE
if ! [[ "$DISK_CHOICE" =~ ^[0-9]+$ ]] || ((DISK_CHOICE < 1 || DISK_CHOICE > ${#DEVICES[@]})); then
    echo "Invalid disk selection."
    exit 1
fi
TARGET_DISK=$(echo "${DEVICES[$((DISK_CHOICE - 1))]}" | awk '{print $1}')

echo
echo "You chose to restore:"
echo "  Backup file : ${FILE##*/}"
echo "  Target disk : $TARGET_DISK"

if $DRY_RUN; then
    echo
    echo "⚠️  This is a dry run. No data will be written to the disk."
    read -r -p "Proceed with dry run simulation? [y/N]: " CONFIRM
else
    echo
    echo "⚠️  This will ERASE ALL DATA on $TARGET_DISK."
    read -r -p "Are you absolutely sure you want to continue? [y/N]: " CONFIRM
fi

CONFIRM=${CONFIRM,,}
if [[ "$CONFIRM" != "y" ]]; then
    echo "Aborted."
    exit 1
fi

echo
if $DRY_RUN; then
    echo "[5/5] Dry run: Would now run:"
    echo "  zcat \"$FILE\" | sudo dd of=\"$TARGET_DISK\" bs=4M status=progress conv=fsync"
    echo
    echo "Dry run complete — no data was modified."
    echo "Would now reboot."
else
    echo "[5/5] Restoring backup... this may take several minutes."
    zcat "$FILE" | sudo dd of="$TARGET_DISK" bs=4M status=progress conv=fsync

    echo
    echo "Syncing and rebooting..."
    sync
    sleep 2
    sudo reboot
fi
