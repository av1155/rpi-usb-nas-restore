# Raspberry Pi NAS-Based Full Restore

This script allows you to boot your Raspberry Pi from a USB stick, mount a backup folder from a Synology NAS, and restore a full `.img.gz` system backup to your NVMe SSD — all headless, over SSH, or via an interactive terminal.

---

## Features

- Interactive selection of available backups
- Interactive selection of target disk for restore
- One-command restore to target disk
- Safe and SSH-friendly
- No physical access required (after initial setup)

---

## What You Need

### Hardware

- Raspberry Pi 5
- NVMe or microSD drive connected
- Spare USB stick (8 GB or more)
- Synology NAS with an NFS share containing your backups

---

## Set USB Boot in EEPROM (Raspberry Pi)

Follow these steps to configure your Raspberry Pi to boot from USB by editing the EEPROM bootloader settings manually.

### 1. Install the EEPROM Configuration Tool

```bash
sudo apt update
sudo apt install -y rpi-eeprom
```

### 2. Edit the EEPROM Boot Configuration

```bash
sudo -E EDITOR=nano rpi-eeprom-config --edit
```

This will open the EEPROM configuration in a text editor.

### 3. Set the Boot Order

Find the line that starts with `BOOT_ORDER`, and change it to:

```bash
BOOT_ORDER=0xf641
```

| Priority | Value | Boot Device                    |
| -------- | ----- | ------------------------------ |
| 1st      | `4`   | **USB** (SSD/HDD, flash drive) |
| 2nd      | `6`   | **NVMe** (PCIe SSD)            |
| 3rd      | `1`   | **SD Card**                    |
| Loop     | `f`   | **Restart** from the top       |

This prioritizes USB devices while still allowing fallback options.

### 4. Save and Exit

Save the changes in the editor and close it. Then apply the updated configuration with:

```bash
sudo rpi-eeprom-update -d -f
```

### 5. Reboot the Raspberry Pi

```bash
sudo reboot
```

Your Raspberry Pi is now set to attempt booting from a USB device first.

---

## Step-by-Step Setup

### 1. Prepare the USB Recovery Stick

1. Download **Raspberry Pi Imager**:
   [https://www.raspberrypi.com/software/](https://www.raspberrypi.com/software/)

2. Flash **Raspberry Pi OS Lite (64-bit)** to the USB stick using the Imager.

3. While configuring image settings (gear icon in Imager):

    - Set a **hostname** (e.g., `pi-restore`)
    - Set a **username and password**
    - Enable **SSH** with password authentication
    - Configure **Wi-Fi** settings (if needed)
    - Set **locale settings** (timezone, keyboard layout, language)
    - **Disable telemetry** (turn off usage reporting)
    - **Untick** "Eject media when finished"

4. After flashing, open the USB stick’s **boot partition** (`bootfs`) and edit the file `firstrun.sh` to set a static IP. This ensures NFS access from the NAS works automatically.

    ```bash
    # Set static IP for recovery access
    echo 'interface eth0
    static ip_address=192.168.X.XXX/24
    static routers=192.168.X.1
    static domain_name_servers=192.168.X.1' >> /etc/dhcpcd.conf

    rm -f /boot/firstrun.sh
    sed -i 's| systemd.run.*||g' /boot/cmdline.txt
    exit 0
    ```

    > Update these IP addresses to match your home network setup.
    >
    > - `static ip_address`: Use an unused IP outside your router's DHCP range,
    >   or the same static IP your Pi already uses (if previously set)
    > - `static routers`: This should be your router's IP (often 192.168.1.1 or 192.168.4.1)
    > - `static domain_name_servers`: Can be your router's IP or a public DNS like 8.8.8.8
    > - Use `interface wlan0` if you are **_not_** using ethernet.

---

### 2. NAS Configuration

On your **Synology NAS**:

- Enable **NFS**:
  DSM → Control Panel → File Services → NFS
- Create a shared folder: `pi-server-backups`
- Grant NFS permissions:

    - Host/IP: `192.168.X.XXX` (same as Pi’s static IP)
    - Privilege: `Read/Write`
    - Squash: `No mapping`

---

### 4. SSH and Run the Restore Script

**SSH into your Pi:**

```bash
ssh <pi-username>@<pi-ip>
```

> ⚠️ If you get a `REMOTE HOST IDENTIFICATION HAS CHANGED` error after restoring, it means the host key has changed (expected when re-imaging the system).
> To fix it, run:
>
> ```bash
> ssh-keygen -R <pi-ip>
> ```
>
> Then try connecting again.

**Download and run the restore script:**

```bash
bash <(curl -s https://raw.githubusercontent.com/av1155/rpi-usb-nas-restore/main/restore.sh)
```

> The script will:
>
> - Prompt for your NAS IP
> - Mount the NFS backup folder
> - Let you choose a backup file and target disk
> - Confirm and restore the system
> - Power off the Pi when done

---

## Notes

- The static IP ensures your NAS allows access without needing DHCP or manual reconfiguration.
- You must temporarily boot the Pi from USB (use `raspi-config` to change boot order).
- The restored backup will also restore the **bootloader settings**, so boot order will revert to whatever was saved in the image.
- This restores your Pi’s full state — OS, services, configs, and files.

---

## License

[MIT License](LICENSE)
