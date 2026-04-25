# ColorBerry

This repo is for jdi screen driver and configure file of ColorBerry, which is available on [discord](https://discord.gg/2uGPpVmCCE) and [Elecrow](https://www.elecrow.com/colorberry.html)

# jdi screen driver

support debian 11 32-bit and debian 12 64-bit with raspberry pi, and debian 12 64-bit with orange pi zero 2w

# Tested Raspberry Pi OS Versions

The current source tree and the Bookworm setup script in this repo have been tested on:

* Raspberry Pi OS Bookworm 32-bit (`armhf`)
* Raspberry Pi kernel `6.12.75+rpt-rpi-v7`
* Raspberry Pi Zero 2 W mounted in Beepy / ColorBerry hardware

This is the supported path for setting up the screen, keyboard, and side-button backlight together.

The older zip archives in this repo are still older snapshots for:

* Raspberry Pi Debian 11 32-bit
* Raspberry Pi Debian 12 64-bit

but the integrated setup flow below is for Raspberry Pi OS Bookworm 32-bit.

# Raspberry PI

## One-Step Bookworm Setup

This repo now includes a setup script that installs:

* the local `sharp-drm` driver from `raspberry-src`
* the `beepy-kbd` keyboard driver from source
* the console keymap
* the side-button backlight service
* a battery helper as `colorberry-battery`
* `tmux` for the optional battery footer workflow

### Prerequisites

Before running the script:

* use Raspberry Pi OS Bookworm 32-bit
* boot the Pi into the kernel you actually want to run
* make sure matching headers exist for that running kernel
* if the Beepy / ColorBerry RP2040 firmware is old, flash the latest `i2c_puppet.uf2` first

Firmware flash reference:

* [Beepy Getting Started](https://beepy.sqfmi.com/docs/getting-started)
* [Beepy Keyboard Firmware](https://beepy.sqfmi.com/docs/firmware/keyboard)

### Run It

From the repo root on the Pi:

```shell
cd ~/jdi-drm-rpi_updated
sudo bash ./setup-colorberry-rpi-bookworm.sh --reboot
```

The script will:

* enable I2C
* remove conflicting apt packages such as PPA `sharp-drm` / `beepy-kbd`
* build and install this repo's `sharp-drm`
* clone and build `https://github.com/ardangelo/beepberry-keyboard-driver.git`
* install `beepy-kbd.ko` and `beepy-kbd.dtbo`
* install `back.py` as `/usr/local/bin/colorberry-backlight`
* install and enable `colorberry-backlight.service`
* install `battery.py` as `/usr/local/bin/colorberry-battery`
* install `tmux`

If you prefer to reboot manually, omit `--reboot`.

### Notes

* This flow intentionally does **not** use the PPA `sharp-drm` package, because that package failed to build cleanly on the tested `6.12.75+rpt-rpi-v7` kernel.
* The script installs `beepy-fw` on a best-effort basis if the Beepy PPA is reachable, but it does not force a firmware flash.
* If `/dev/i2c-1` is still missing after the script finishes, reboot once and rerun the verification commands below.

### Verify After Reboot

```shell
lsmod | grep sharp
lsmod | grep beepy
dmesg | grep -Ei "sharp|beepy"
ls /sys/firmware/beepy
ls /sys/firmware/beepy/keyboard_backlight
cat /sys/module/sharp_drm/parameters/backlit
```

### Backlight Checks

```shell
echo 1 | sudo tee /sys/module/sharp_drm/parameters/backlit
echo 255 | sudo tee /sys/firmware/beepy/keyboard_backlight
```

### Battery Helper

Beepy exposes these battery sysfs entries under `/sys/firmware/beepy`:

* `battery_percent`
* `battery_volts`
* `battery_raw`

The setup script installs a helper as `/usr/local/bin/colorberry-battery`.

Examples:

```shell
colorberry-battery
colorberry-battery --percent
colorberry-battery --volts
colorberry-battery --json
```

For `tmux`, you can use:

```tmux
set -g status-right "#{ip} | #(/usr/local/bin/colorberry-battery --percent)%% | %H:%M"
```

### tmux Footer On Startup

This repo includes a sample tmux config at `colorberry.tmux.conf` that shows
battery percentage in the tmux footer.

To use it on the Pi:

```shell
cp ~/jdi-drm-rpi_updated/colorberry.tmux.conf ~/.tmux.conf
tmux source-file ~/.tmux.conf
```

The sample footer uses:

```tmux
#(/usr/local/bin/colorberry-battery --percent 2>/dev/null || printf -- '--')%% | %H:%M
```

If you also want tmux to start automatically on the local device console, add
this to your shell startup file such as `~/.zshrc`:

```shell
if [ -z "$SSH_CONNECTION" ]; then
        if [[ "$(tty)" =~ /dev/tty ]] && type fbterm > /dev/null 2>&1; then
                fbterm
        elif [ -z "$TMUX" ] && type tmux >/dev/null 2>&1; then
                tmux new -As "$(basename "$(tty)")"
        fi
fi
```

That keeps SSH sessions unaffected, but starts tmux automatically on the local
screen.

The side button is handled by `colorberry-backlight.service`, not by cron.

You should not normally run `back.py` by hand in a terminal. It is a long-running listener process and is meant to run under `systemd` in the background.

### Backlight Service

The installer enables the service automatically. Useful commands:

```shell
sudo systemctl status colorberry-backlight.service
sudo systemctl restart colorberry-backlight.service
sudo journalctl -u colorberry-backlight.service -b
```

### Manual Driver Build Only

If you only want to rebuild the display driver:

```shell
cd ~/jdi-drm-rpi_updated/raspberry-src
make clean
make
sudo make install
```

### Set dithering level

```shell
echo <level> | sudo tee /sys/module/sharp_drm/parameters/dither > /dev/null
<level> from 0 to 4, 0 for close dithering, 4 for max
```

## .zshrc

```shell
if [ -z "$SSH_CONNECTION" ]; then
        if [[ "$(tty)" =~ /dev/tty ]] && type fbterm > /dev/null 2>&1; then
                fbterm
        # otherwise, start/attach to tmux
        elif [ -z "$TMUX" ] && type tmux >/dev/null 2>&1; then
                fcitx 2>/dev/null &
                tmux new -As "$(basename $(tty))"
        fi
fi
export PROMPT="%c$ "
export PATH=$PATH:~/sbin
export SDL_VIDEODRIVER="fbcon"
export SDL_FBDEV="/dev/fb1"
alias d0="echo 0 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d3="echo 3 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d4="echo 4 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias b="echo 1 | sudo tee /sys/module/sharp_drm/parameters/backlit"
alias bn="echo 0 | sudo tee /sys/module/sharp_drm/parameters/backlit"
alias key='echo "keys" | sudo tee /sys/module/beepy_kbd/parameters/touch_as > /dev/null'
alias mouse='echo "mouse" | sudo tee /sys/module/beepy_kbd/parameters/touch_as > /dev/null'
```

# Orangepi zero 2W

Based on `Orangepizero2w_1.0.2_debian_bookworm_server_linux6.1.31.7z`

unzip `jdi-drm-orangepi-debian12-64.zip` file in any location and cd into it.

## install

```bash
sudo orangepi-add-overlay sharp-drm.dts
sudo cp sharp-drm.ko /lib/modules/6.1.31-sun50iw9/ # when upgrade, only need copy this file and reboot
sudo depmod -a
sudo echo "sharp-drm" >> /etc/modules 
# make sure only one sharp-drm in /etc/modules
```

## backlight

build [wiringOP-Python](https://github.com/orangepi-xunlong/wiringOP-Python/tree/next) with "next" branch, do the same as raspberry pi with `orangepi-back.py`

## .zshrc

```bash
if [ -z "$SSH_CONNECTION" ]; then
        if [[ "$(tty)" =~ /dev/tty ]] && type fbterm > /dev/null 2>&1; then
               fbterm
        elif [ -z "$TMUX" ] && type tmux >/dev/null 2>&1; then
                fcitx 2>/dev/null &
                tmux new -As "$(basename $(tty))"
        fi
fi

export PROMPT="%c$ "

alias d0="echo 0 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d3="echo 3 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d4="echo 4 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias b="echo 1 | sudo tee /sys/module/sharp_drm/parameters/backlit"
alias bn="echo 0 | sudo tee /sys/module/sharp_drm/parameters/backlit"
alias key='echo "keys" | sudo tee /sys/module/beepy_kbd/parameters/touch_as > /dev/null'
alias mouse='echo "mouse" | sudo tee /sys/module/beepy_kbd/parameters/touch_as > /dev/null'
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=14'
```

## .tmux.conf

```bash
# Status bar
set -g status-position top
set -g status-left ""
set -g status-right "#{ip} #{wifi_ssid} #{wifi_icon}|[#(cat /sys/firmware/beepy/battery_percent)]%H:%M"
set -g status-interval 10
set -g window-status-separator ' | '
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'gmoe/tmux-wifi'
set -g @plugin 'tmux-plugins/tmux-sensible'
run-shell ~/.tmux/plugins/tmux-plugin-ip/ip.tmux
run '~/.tmux/plugins/tpm/tpm'

set -g @tmux_wifi_icon_5 "☰"
set -g @tmux_wifi_icon_4 "☱"
set -g @tmux_wifi_icon_3 "⚌"
set -g @tmux_wifi_icon_2 "⚍"
set -g @tmux_wifi_icon_1 "⚊"
set -g @tmux_wifi_icon_off ""
```

## /etc/rc.local

```bash
echo 0 | sudo tee /sys/module/sharp_drm/parameters/dither
echo 0 | sudo tee /sys/firmware/beepy/keyboard_backlight > /dev/null
/usr/local/bin/gpio export 226 in
/usr/local/bin/gpio edge 226 rising
echo "key" | sudo tee /sys/module/beepy_kbd/parameters/touch_as > /dev/null
echo "always" | sudo tee /sys/module/beepy_kbd/parameters/touch_act > /dev/null
```

# xfce

```bash
sudo apt install task-xfce-desktop
sudo apt-get install xserver-xorg-legacy
sudo usermod -a orangepi -G tty
```

## /etc/X11/Xwrapper.config

```
	allowed_users=anybody
	needs_root_rights=yes
```

## /etc/X11/xorg.conf

```


Section "Device"
    Identifier "FBDEV"
    Driver "fbdev"
    Option "fbdev" "/dev/fb0"
#    Option "ShadowFB" "false"
EndSection

Section "ServerFlags"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection
```

# keyboard input under gui

copy file of gui-keymap/ to system file:

```
/usr/share/X11/xkb/symbols/us
/usr/share/X11/xkb/keycodes/evdev
```

map sym z,x,c...m to F1...F7,

shift - $ = F8

sym - $ = F9

sym - h = F10

sym - j = F11

sym - l = F12

sym - f = &

# [mgba](mgba.md) for playing gba game on ColorBerry
