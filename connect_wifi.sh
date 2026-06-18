#!/bin/bash
set -euo pipefail

# Resolve adb by absolute path. Android Studio's Shell Script run config does NOT
# load ~/.zshrc, so a bare `adb` is not on PATH there. Try the SDK env vars first,
# then the default macOS SDK location, then fall back to PATH (for plain terminals).
ADB="adb"
for candidate in \
    "${ANDROID_SDK_ROOT:-}/platform-tools/adb" \
    "${ANDROID_HOME:-}/platform-tools/adb" \
    "$HOME/Library/Android/sdk/platform-tools/adb"; do
    if [[ -x "$candidate" ]]; then ADB="$candidate"; break; fi
done

TITLE="ADB WiFi Connect"

# Port adb listens on for TCP/IP connections (Android default).
PORT="${PORT:-5555}"

# The device usually lives on a fixed subnet, so we only ask for the last octet
# and build the full address from this prefix. Override with IP_PREFIX if needed.
IP_PREFIX="${IP_PREFIX:-192.168.1}"

# Use native macOS dialogs when available (also when launched from Android Studio's
# Shell Script run config). Disable with GUI=0 to force plain console prompts.
gui_enabled() {
    [[ "${GUI:-1}" == "1" && "$(uname)" == "Darwin" ]] && command -v osascript >/dev/null 2>&1
}

# Ask for a line of text. GUI: a dialog with a text field. CLI: read from stdin.
# Prints the entered text (empty if the user cancels).
ask_text() {
    local prompt="$1"
    if gui_enabled; then
        osascript -e "text returned of (display dialog \"${prompt//\"/\\\"}\" default answer \"\" with title \"${TITLE}\")" 2>/dev/null || true
    else
        local ans; read -r -p "${prompt} " ans; printf '%s' "$ans"
    fi
}

# Choose one entry from a list. GUI: a dropdown picker. CLI: a numbered menu.
# Args: prompt, then the option labels. Prints the chosen label (empty on cancel).
ask_choice() {
    local prompt="$1"; shift
    if gui_enabled; then
        local applescript="set L to {" first=1 lbl
        for lbl in "$@"; do
            lbl=${lbl//\"/\\\"}
            if [[ $first -eq 1 ]]; then applescript+="\"$lbl\""; first=0
            else applescript+=", \"$lbl\""; fi
        done
        applescript+="}
set c to choose from list L with prompt \"${prompt//\"/\\\"}\" with title \"${TITLE}\"
if c is false then return \"\"
return item 1 of c"
        osascript -e "$applescript" 2>/dev/null || true
    else
        echo "$prompt" >&2
        local opts=("$@") i
        for i in "${!opts[@]}"; do echo "  [$i] ${opts[$i]}" >&2; done
        local idx; read -r -p "Pick number: " idx
        printf '%s' "${opts[$idx]:-}"
    fi
}

OCTET="${1:-$(ask_text "Device IP last part (${IP_PREFIX}.___):")}"
[[ -z "$OCTET" ]] && { echo "No IP provided"; exit 1; }

# Last octet must be a number in 0-255.
if [[ ! "$OCTET" =~ ^[0-9]{1,3}$ ]] || (( OCTET > 255 )); then
    echo "'$OCTET' is not a valid last octet (0-255)"; exit 1
fi
IP="${IP_PREFIX}.${OCTET}"

echo "-> Starting adb server..."
"$ADB" start-server

# `adb tcpip` needs a single target. If several devices are attached it errors with
# "more than one device/emulator", so we pick the USB device explicitly with -s.
# Only USB devices count here: skip emulators and already-networked (host:port) ones.
usb_devices=()
while IFS= read -r serial; do
    [[ -n "$serial" ]] && usb_devices+=("$serial")
done < <("$ADB" devices | tr '\r' '\n' \
    | awk '$2 == "device" && $1 !~ /^emulator-/ && $1 !~ /:[0-9]+$/ {print $1}')

# Friendly name (e.g. "Pixel 7"), falling back to the serial if the prop is empty.
device_label() {
    local m; m="$("$ADB" -s "$1" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
    printf '%s (%s)' "${m:-$1}" "$1"
}

if [[ ${#usb_devices[@]} -eq 0 ]]; then
    echo "No USB device connected. Plug the device in via USB first."; exit 1
elif [[ ${#usb_devices[@]} -eq 1 ]]; then
    SERIAL="${usb_devices[0]}"
else
    # Build human-readable labels, ask, then map the chosen label back to its serial.
    labels=()
    for s in "${usb_devices[@]}"; do labels+=("$(device_label "$s")"); done
    chosen="$(ask_choice "Select the USB device to connect over WiFi:" "${labels[@]}")"
    [[ -z "$chosen" ]] && { echo "No device selected"; exit 1; }
    SERIAL=""
    for i in "${!labels[@]}"; do
        [[ "${labels[$i]}" == "$chosen" ]] && { SERIAL="${usb_devices[$i]}"; break; }
    done
    [[ -z "$SERIAL" ]] && { echo "Invalid selection"; exit 1; }
fi
echo "-> Using USB device $(device_label "$SERIAL")"

# Switch the (USB-connected) device to TCP/IP mode before connecting over WiFi.
echo "-> Enabling TCP/IP on port ${PORT}..."
"$ADB" -s "${SERIAL}" tcpip "${PORT}"

echo "-> Connecting to ${IP}:${PORT}..."
"$ADB" connect "${IP}:${PORT}"
