# ESP32-S3 Linux install with persistent Wi-Fi

This setup builds and flashes the ESP32-S3 Linux image using Docker and injects a permanent Wi-Fi configuration into the Buildroot overlay before flashing.

`config.env.example` is the template. Copy it to `config.env` and edit `config.env`.

```bash
cp config.env.example config.env
```

## Variables

| Variable | Meaning |
|---|---|
| `ESP32_PORT` | Serial device used for flashing, for example `/dev/ttyACM0` |
| `WIFI_SSID` | Wi-Fi network name |
| `WIFI_PASSWORD` | Wi-Fi password |
| `WIFI_COUNTRY` | Regulatory country code, for example `DE`, `US`, `GB` |
| `WIFI_PSK_MODE` | `plain` or `hashed` Wi-Fi PSK mode |
| `BOARD_CONFIG` | ESP32-S3 Linux board config file |
| `ESP32_HOSTNAME` | Optional hostname written to `/etc/hostname` |
| `ENABLE_DROPBEAR` | Set to `1` to enable Dropbear SSH |
| `SSH_PUBLIC_KEY_FILE` | Public key file copied to `/root/.ssh/authorized_keys` when Dropbear is enabled |

If Dropbear is enabled, set `SSH_PUBLIC_KEY_FILE` to a key like `~/.ssh/id_ed25519.pub`.
`ESP32_HOSTNAME` sets the local hostname.
Dropbear starts in key-only mode, so password login is disabled.

## Additional Packages

Buildroot package names live under `package/*/Config.in` in the Buildroot tree: https://github.com/buildroot/buildroot/tree/master/package.

Set `BR2_PACKAGE_FOO=y` in `config.env` to enable a package. Use `make menuconfig` to confirm the exact `BR2_PACKAGE_*` names.

## Requirements

Host machine:

- Linux
- Git
- Docker
- ESP32-S3 development board connected over USB
- ESP32-S3 board with PSRAM
- Roughly 20 GB of free disk space for the build

Check board serial port:

```bash
ls /dev/ttyACM* /dev/ttyUSB*
```

Common port:

```text
/dev/ttyACM0
```

If your board appears somewhere else, set `ESP32_PORT` in `config.env`.

## Run installer

```bash
make install
```

The script will:

1. Load Wi-Fi and board settings from `config.env`
2. Clone `hpsaturn/esp32s3-linux`
3. Build the Docker image
4. Copy default settings
5. Create a Buildroot overlay
6. Add `/etc/wpa_supplicant.conf`
7. Enable `BR2_ROOTFS_OVERLAY="board/espressif/esp32s3/rootfs_overlay /app/buildroot_overlay"` in the board config
9. Write the hostname and optionally enable Dropbear SSH
10. Build and flash the ESP32-S3 Linux image

## Open serial console

```bash
make connect
```

Login:

```text
root
```

Exit picocom:

```text
Ctrl-a
Ctrl-x
```

## Check Wi-Fi after boot

On the ESP32-S3 Linux shell:

```sh
ip addr show espsta0
```

Test network:

```sh
ping -c 3 8.8.8.8
```

Test DNS:

```sh
ping -c 3 google.com
```

## What gets installed into the ESP32-S3 image

The script injects these files into the Buildroot root filesystem overlay:

```text
/etc/wpa_supplicant.conf
/etc/hostname
/root/.ssh/authorized_keys
/etc/init.d/S50dropbear
```
