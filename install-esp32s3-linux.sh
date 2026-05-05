#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-wifi.env}"
REPO_URL="https://github.com/hpsaturn/esp32s3-linux.git"
REPO_DIR="esp32s3-linux"
DOCKER_IMAGE="esp32linuxbase"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

ensure_config_line() {
  local file="$1"
  local key="$2"
  local value="$3"

  if grep -q "^${key}=" "$file"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    echo "${key}=${value}" >> "$file"
  fi
}

load_env() {
  [[ -f "$ENV_FILE" ]] || die "Env file not found: $ENV_FILE"

  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  : "${ESP32_PORT:?Missing ESP32_PORT in $ENV_FILE}"
  : "${WIFI_SSID:?Missing WIFI_SSID in $ENV_FILE}"
  : "${WIFI_PASSWORD:?Missing WIFI_PASSWORD in $ENV_FILE}"
  : "${WIFI_COUNTRY:=DE}"
  : "${BOARD_CONFIG:=devkit-c1-8m.conf}"
  : "${ENABLE_DROPBEAR:=1}"
  if [[ "$ENABLE_DROPBEAR" == "1" ]]; then
    : "${SSH_PUBLIC_KEY_FILE:?Missing SSH_PUBLIC_KEY_FILE in $ENV_FILE}"
  fi
}

check_host() {
  need_cmd git
  need_cmd docker

  [[ -e "$ESP32_PORT" ]] || die "Serial device not found: $ESP32_PORT"

  if ! docker info >/dev/null 2>&1; then
    die "Docker not usable by current user. Run: sudo usermod -aG docker \$USER ; newgrp docker"
  fi
}

checkout_repo() {
  if [[ ! -d "$REPO_DIR" ]]; then
    git clone --recursive "$REPO_URL" "$REPO_DIR"
  else
    cd "$REPO_DIR"
    git pull --ff-only
    git submodule update --init --recursive
    cd ..
  fi
}

build_docker_image() {
  cd "$REPO_DIR"

  docker build \
    --build-arg DOCKER_USER="$USER" \
    --build-arg DOCKER_USERID="$(id -u)" \
    -t "$DOCKER_IMAGE" .

  cd ..
}

prepare_settings() {
  cd "$REPO_DIR"

  if [[ ! -f settings.cfg ]]; then
    cp settings.cfg.default settings.cfg
  fi

  cd ..
}

prepare_overlay() {
  cd "$REPO_DIR/esp32-linux-build"

  mkdir -p buildroot_overlay/etc/init.d
  mkdir -p buildroot_overlay/var/run/wpa_supplicant
  mkdir -p buildroot_overlay/root

  if command -v wpa_passphrase >/dev/null 2>&1; then
    {
      echo "ctrl_interface=/var/run/wpa_supplicant"
      echo "update_config=1"
      echo "country=${WIFI_COUNTRY}"
      echo
      wpa_passphrase "$WIFI_SSID" "$WIFI_PASSWORD" | sed '/^[[:space:]]*#psk=/d'
    } > buildroot_overlay/etc/wpa_supplicant.conf
  else
    cat > buildroot_overlay/etc/wpa_supplicant.conf <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=${WIFI_COUNTRY}

network={
    ssid="${WIFI_SSID}"
    psk="${WIFI_PASSWORD}"
}
EOF
  fi

  chmod 600 buildroot_overlay/etc/wpa_supplicant.conf

  cat > buildroot_overlay/etc/init.d/S41wifi <<'EOF'
#!/bin/sh

IFACE="espsta0"
CONF="/etc/wpa_supplicant.conf"

case "$1" in
  start)
    echo "Starting Wi-Fi on ${IFACE}"

    ip link set "${IFACE}" up 2>/dev/null || true

    if ! pgrep wpa_supplicant >/dev/null 2>&1; then
      wpa_supplicant -B -i "${IFACE}" -c "${CONF}"
    fi

    udhcpc -i "${IFACE}" -q -n || udhcpc -i "${IFACE}" &
    ;;

  stop)
    echo "Stopping Wi-Fi on ${IFACE}"

    killall udhcpc 2>/dev/null || true
    killall wpa_supplicant 2>/dev/null || true
    ip link set "${IFACE}" down 2>/dev/null || true
    ;;

  restart)
    "$0" stop
    sleep 1
    "$0" start
    ;;

  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac

exit 0
EOF

  chmod +x buildroot_overlay/etc/init.d/S41wifi

  if [[ "$ENABLE_DROPBEAR" == "1" ]]; then
    [[ -f "$SSH_PUBLIC_KEY_FILE" ]] || die "SSH public key not found: $SSH_PUBLIC_KEY_FILE"

    mkdir -p buildroot_overlay/root/.ssh
    chmod 700 buildroot_overlay/root/.ssh
    cp "$SSH_PUBLIC_KEY_FILE" buildroot_overlay/root/.ssh/authorized_keys
    chmod 600 buildroot_overlay/root/.ssh/authorized_keys

    cat > buildroot_overlay/etc/init.d/S50dropbear <<'EOF'
#!/bin/sh

case "$1" in
  start)
    echo "Starting Dropbear SSH"
    mkdir -p /var/run
    dropbear -s -R -E
    ;;

  stop)
    echo "Stopping Dropbear SSH"
    killall dropbear 2>/dev/null || true
    ;;

  restart)
    "$0" stop
    sleep 1
    "$0" start
    ;;

  *)
    echo "Usage: $0 {start|stop|restart}"
    exit 1
    ;;
esac

exit 0
EOF

    chmod +x buildroot_overlay/etc/init.d/S50dropbear
  fi

  if [[ -f "$BOARD_CONFIG" ]]; then
    ensure_config_line "$BOARD_CONFIG" "BR2_ROOTFS_OVERLAY" '"buildroot_overlay"'

    if [[ "$ENABLE_DROPBEAR" == "1" ]]; then
      ensure_config_line "$BOARD_CONFIG" "BR2_PACKAGE_DROPBEAR" "y"
    fi
  else
    echo "WARNING: board config not found: $BOARD_CONFIG"
    echo "Available configs:"
    ls -1 *.conf 2>/dev/null || true
  fi

  cd ../..
}

flash_board() {
  cd "$REPO_DIR"

  docker run --rm -it \
    --name esp32s3linux \
    --user="$(id -u):$(id -g)" \
    -v ./esp32-linux-build:/app \
    --env-file settings.cfg \
    --device="$ESP32_PORT" \
    "$DOCKER_IMAGE" \
    ./rebuild-esp32s3-linux-wifi.sh -c "$BOARD_CONFIG"

  cd ..
}

main() {
  load_env
  check_host
  checkout_repo
  build_docker_image
  prepare_settings
  prepare_overlay
  flash_board
}

main "$@"
