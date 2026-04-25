#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RPI_DIR="${SCRIPT_DIR}/raspberry-src"
KEYBOARD_REPO_URL="${KEYBOARD_REPO_URL:-https://github.com/ardangelo/beepberry-keyboard-driver.git}"
KEYBOARD_SRC_DIR="${KEYBOARD_SRC_DIR:-/usr/local/src/beepberry-keyboard-driver}"
BACKLIGHT_BIN="/usr/local/bin/colorberry-backlight"
BACKLIGHT_SERVICE_SRC="${SCRIPT_DIR}/colorberry-backlight.service"
BACKLIGHT_SERVICE="/etc/systemd/system/colorberry-backlight.service"
KEYMAP_DEST="/usr/local/share/kbd/keymaps/beepy-kbd.map"
MODULES_FILE="/etc/modules"
REBOOT_AFTER=0

for arg in "$@"; do
	case "$arg" in
	--reboot)
		REBOOT_AFTER=1
		;;
	-h|--help)
		cat <<'EOF'
Usage: sudo bash ./setup-colorberry-rpi-bookworm.sh [--reboot]

Installs the local sharp-drm driver, builds the Beepy keyboard driver from
source, enables I2C, installs the side-button backlight service, and prepares
the console keymap for Raspberry Pi OS Bookworm.

This script is intended for Beepy/ColorBerry-style hardware on Raspberry Pi OS
Bookworm. A reboot is required before the keyboard overlay takes effect.
EOF
		exit 0
		;;
	*)
		echo "Unknown argument: $arg" >&2
		exit 1
		;;
	esac
done

if [[ ${EUID} -ne 0 ]]; then
	exec sudo --preserve-env=KEYBOARD_REPO_URL,KEYBOARD_SRC_DIR bash "$0" "$@"
fi

if [[ ! -f "${RPI_DIR}/Makefile" ]]; then
	echo "Could not find raspberry-src under ${SCRIPT_DIR}" >&2
	exit 1
fi

if [[ -r /etc/os-release ]]; then
	# shellcheck disable=SC1091
	source /etc/os-release
else
	echo "Could not read /etc/os-release" >&2
	exit 1
fi

if [[ "${VERSION_CODENAME:-}" != "bookworm" ]]; then
	echo "This script supports Raspberry Pi OS Bookworm only. Found: ${PRETTY_NAME:-unknown}" >&2
	exit 1
fi

if [[ ! -d /boot/firmware/overlays ]]; then
	OVERLAYS_DIR="/boot/overlays"
	BOOT_CONFIG="/boot/config.txt"
else
	OVERLAYS_DIR="/boot/firmware/overlays"
	BOOT_CONFIG="/boot/firmware/config.txt"
fi

ensure_line() {
	local file="$1"
	local line="$2"
	grep -qxF "$line" "$file" 2>/dev/null || printf '%s\n' "$line" >> "$file"
}

replace_or_append_kv() {
	local file="$1"
	local key="$2"
	local value="$3"
	if grep -q "^${key}=" "$file" 2>/dev/null; then
		sed -i "s|^${key}=.*|${key}=${value}|" "$file"
	else
		printf '%s=%s\n' "$key" "$value" >> "$file"
	fi
}

dedupe_modules() {
	awk '!seen[$0]++' "$MODULES_FILE" > "${MODULES_FILE}.tmp"
	mv "${MODULES_FILE}.tmp" "$MODULES_FILE"
}

echo "Installing build and runtime dependencies..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
	build-essential \
	curl \
	device-tree-compiler \
	git \
	gnupg \
	i2c-tools \
	kbd \
	python3-rpi.gpio \
	raspberrypi-kernel-headers

if [[ ! -e "/lib/modules/$(uname -r)/build" ]]; then
	echo "Matching kernel headers are missing for $(uname -r)." >&2
	exit 1
fi

if command -v raspi-config >/dev/null 2>&1; then
	echo "Enabling I2C..."
	raspi-config nonint do_i2c 0 || true
fi
modprobe i2c-dev || true
ensure_line "$MODULES_FILE" "i2c-dev"

echo "Removing conflicting apt packages if present..."
DEBIAN_FRONTEND=noninteractive apt-get remove --purge -y sharp-drm beepy-kbd beepy-symbol-overlay || true
DEBIAN_FRONTEND=noninteractive apt-get -f install -y || true

echo "Installing Beepy firmware package (best effort)..."
if curl -fsS --compressed "https://ardangelo.github.io/beepy-ppa/KEY.gpg" | gpg --dearmor > /etc/apt/trusted.gpg.d/beepy.gpg; then
	curl -fsS --compressed -o /etc/apt/sources.list.d/beepy.list "https://ardangelo.github.io/beepy-ppa/beepy.list"
	apt-get update || true
	DEBIAN_FRONTEND=noninteractive apt-get install -y beepy-fw || true
fi

echo "Building and installing sharp-drm from this repo..."
	make -C "$RPI_DIR" clean
	make -C "$RPI_DIR"
	make -C "$RPI_DIR" install

echo "Fetching Beepy keyboard driver source..."
mkdir -p "$(dirname "$KEYBOARD_SRC_DIR")"
if [[ -d "${KEYBOARD_SRC_DIR}/.git" ]]; then
	git -C "$KEYBOARD_SRC_DIR" fetch --depth=1 origin
	git -C "$KEYBOARD_SRC_DIR" reset --hard origin/HEAD
else
	rm -rf "$KEYBOARD_SRC_DIR"
	git clone --depth=1 "$KEYBOARD_REPO_URL" "$KEYBOARD_SRC_DIR"
fi

if [[ -f "${KEYBOARD_SRC_DIR}/src/params_iface.c" ]]; then
	sed -i 's/^static int sharp_path_param_set/static __maybe_unused int sharp_path_param_set/' \
		"${KEYBOARD_SRC_DIR}/src/params_iface.c"
fi

echo "Building Beepy keyboard driver..."
make -C "$KEYBOARD_SRC_DIR" clean
make -C "$KEYBOARD_SRC_DIR"

echo "Installing Beepy keyboard driver..."
install -D -m 0644 "${KEYBOARD_SRC_DIR}/beepy-kbd.ko" "/lib/modules/$(uname -r)/extra/beepy-kbd.ko"
install -D -m 0644 "${KEYBOARD_SRC_DIR}/beepy-kbd.dtbo" "${OVERLAYS_DIR}/beepy-kbd.dtbo"
ensure_line "$BOOT_CONFIG" "dtoverlay=beepy-kbd,irq_pin=4"
ensure_line "$MODULES_FILE" "beepy-kbd"
dedupe_modules
depmod -a

if [[ -f "${KEYBOARD_SRC_DIR}/beepy-kbd.map" ]]; then
	echo "Installing console keymap..."
	install -D -m 0644 "${KEYBOARD_SRC_DIR}/beepy-kbd.map" "$KEYMAP_DEST"
	replace_or_append_kv /etc/default/keyboard KMAP "$KEYMAP_DEST"
	rm -f /etc/console-setup/cached_setup_keyboard.sh
	loadkeys "$KEYMAP_DEST" || true
fi

echo "Installing side-button backlight service..."
install -D -m 0755 "${SCRIPT_DIR}/back.py" "$BACKLIGHT_BIN"
install -D -m 0644 "$BACKLIGHT_SERVICE_SRC" "$BACKLIGHT_SERVICE"

systemctl daemon-reload
systemctl enable --now colorberry-backlight.service || true

echo
echo "Install complete."
echo "Tested target: Raspberry Pi OS Bookworm 32-bit on Pi Zero 2 W / Beepy / ColorBerry."
echo "A reboot is required before the keyboard overlay is active."
echo "The side-button backlight listener is installed as colorberry-backlight.service."

if [[ -e /dev/i2c-1 ]]; then
	if i2cdetect -y 1 | grep -q '\<1f\>'; then
		echo "Detected RP2040 firmware at I2C address 0x1f."
	else
		echo "Did not detect RP2040 firmware at 0x1f. If the keyboard does not work after reboot,"
		echo "flash the latest i2c_puppet.uf2 to the Beepy RP2040 and rerun this script."
	fi
else
	echo "/dev/i2c-1 is not present yet. If this was the first time enabling I2C, reboot once."
fi

if [[ $REBOOT_AFTER -eq 1 ]]; then
	echo "Rebooting..."
	reboot
fi
