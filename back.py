#!/bin/python3
import signal
import sys
from time import sleep, time

import RPi.GPIO as GPIO

BUTTON_PIN = 17
DEBOUNCE_SECONDS = 0.2
POLL_SECONDS = 0.05
DISPLAY_BACKLIGHT_PATH = "/sys/module/sharp_drm/parameters/backlit"
KEYBOARD_BACKLIGHT_PATH = "/sys/firmware/beepy/keyboard_backlight"

backlit_on = False
last_time = time()


def signal_handler(sig, frame):
    GPIO.cleanup()
    print("cleanup")
    sys.exit(0)


def write_value(path, value):
    try:
        with open(path, "w", encoding="ascii") as handle:
            handle.write(f"{value}\n")
        return True
    except FileNotFoundError:
        return False


def read_value(path, default="0"):
    try:
        with open(path, "r", encoding="ascii") as handle:
            return handle.read().strip() or default
    except FileNotFoundError:
        return default


def set_backlight(enabled):
    global backlit_on

    backlit_on = enabled
    display_ok = write_value(DISPLAY_BACKLIGHT_PATH, "1" if enabled else "0")
    keyboard_ok = write_value(KEYBOARD_BACKLIGHT_PATH, "255" if enabled else "0")
    print(
        f"backlight={'on' if enabled else 'off'} "
        f"display={'ok' if display_ok else 'missing'} "
        f"keyboard={'ok' if keyboard_ok else 'missing'}",
        flush=True,
    )


def button_pressed():
    global last_time

    if time() - last_time < DEBOUNCE_SECONDS:
        return

    last_time = time()
    set_backlight(not backlit_on)


if __name__ == "__main__":
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(BUTTON_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    backlit_on = read_value(DISPLAY_BACKLIGHT_PATH, "0") == "1"
    print(
        f"Listening on GPIO {BUTTON_PIN}, current display backlight="
        f"{'on' if backlit_on else 'off'}",
        flush=True,
    )

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    last_state = GPIO.input(BUTTON_PIN)
    while True:
        state = GPIO.input(BUTTON_PIN)
        if last_state == GPIO.HIGH and state == GPIO.LOW:
            button_pressed()
        last_state = state
        sleep(POLL_SECONDS)
