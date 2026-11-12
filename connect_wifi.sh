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
DEFAULT_PORT=5555

# The device usually lives on a fixed subnet, so we only ask for the last octet
# and build the full address from this prefix. Override with IP_PREFIX if needed.
IP_PREFIX="${IP_PREFIX:-192.168.1}"

# Use native macOS dialogs when available (also when launched from Android Studio's
# Shell Script run config). Disable with GUI=0 to force plain console prompts.
gui_enabled() {
    [[ "${GUI:-1}" == "1" && "$(uname)" == "Darwin" ]] && command -v osascript >/dev/null 2>&1
}

# Ask for a line of text. GUI: a dialog with a text field. CLI: read from stdin.
# Optional second arg pre-fills the answer. Prints the entered text (empty if the user cancels).
ask_text() {
    local prompt="$1" default="${2:-}"
    if gui_enabled; then
        osascript -e "text returned of (display dialog \"${prompt//\"/\\\"}\" default answer \"${default}\" with title \"${TITLE}\")" 2>/dev/null || true
    else
        local ans; read -r -p "${prompt} " ans; printf '%s' "${ans:-$default}"
    fi
}

# One native window with a labeled field per value. Prints "OK|octet|port|code",
# or nothing if cancelled. "|" is the separator because tabs would collapse empty fields in `read`.
ask_form() {
    osascript -l JavaScript -e '
ObjC.import("Cocoa");
function run(argv) {
    const [title, prefix, defaultPort] = argv;
    const app = $.NSApplication.sharedApplication;
    app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
    app.activateIgnoringOtherApps(true);
    const alert = $.NSAlert.alloc.init;
    alert.messageText = title;
    alert.informativeText = "Leave the pairing code empty to connect via USB.\nWith a code, use the port shown next to it.";
    alert.addButtonWithTitle("Connect");
    alert.addButtonWithTitle("Cancel");
    const rows = [
        ["IP last part (" + prefix + ".___)", ""],
        ["Port (optional, pairing port with a code)", defaultPort],
        ["Pairing code (optional)", ""],
    ];
    const width = 420, rowHeight = 32, labelWidth = 270;
    const view = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, width, rows.length * rowHeight));
    const fields = rows.map(([text, value], i) => {
        const y = (rows.length - 1 - i) * rowHeight;
        const label = $.NSTextField.labelWithString(text);
        label.frame = $.NSMakeRect(0, y + 3, labelWidth, 20);
        view.addSubview(label);
        const field = $.NSTextField.alloc.initWithFrame($.NSMakeRect(labelWidth + 8, y, width - labelWidth - 8, 24));
        field.stringValue = value;
        view.addSubview(field);
        return field;
    });
    fields.forEach((field, i) => { if (i < fields.length - 1) field.nextKeyView = fields[i + 1]; });
    alert.accessoryView = view;
    alert.window.initialFirstResponder = fields[0];
    if (alert.runModal != $.NSAlertFirstButtonReturn) return "";
    return ["OK"].concat(fields.map(f => f.stringValue.js.trim())).join("|");
}' "$TITLE" "$IP_PREFIX" "$DEFAULT_PORT" 2>/dev/null || true
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( $1 >= 1 && $1 <= 65535 ))
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

# Usage: connect_wifi.sh <octet> [port] [pairing_code]
# With no args (or an empty first arg) every value is asked for in a single form (GUI=0: one prompt each).
# With a pairing code (Android 11+ "Wireless debugging", no USB cable) the port is the pairing port.
# Android Studio's $Prompt$ passes everything typed as a single arg, so split it on whitespace.
if [[ $# -eq 1 ]]; then
    read -r -a split_args <<< "$1"
    set -- "${split_args[@]+"${split_args[@]}"}"
fi
(( $# > 3 )) && { echo "Too many values. Usage: <ip_end> [port] [pairing_code]"; exit 1; }

if [[ -n "${1:-}" ]]; then
    OCTET="$1"
    PORT="${2:-}"
    PAIR_CODE="${3:-}"
elif gui_enabled; then
    form="$(ask_form)"
    [[ -z "$form" ]] && { echo "Cancelled"; exit 1; }
    IFS='|' read -r _ OCTET PORT PAIR_CODE <<< "$form"
else
    OCTET="$(ask_text "Device IP last part (${IP_PREFIX}.___):")"
    [[ -z "$OCTET" ]] && { echo "No IP provided"; exit 1; }
    PORT="$(ask_text "Port (optional, default ${DEFAULT_PORT}; pairing port with a code):" "${PORT:-$DEFAULT_PORT}")"
    PAIR_CODE="$(ask_text "Wireless debugging pairing code (optional, leave empty to connect via USB):")"
fi
[[ -z "$OCTET" ]] && { echo "No IP provided"; exit 1; }
if [[ -z "$PORT" ]]; then
    PORT="$DEFAULT_PORT"
    echo "-> No port given, using default ${DEFAULT_PORT}"
fi
is_valid_port "$PORT" || { echo "'$PORT' is not a valid port (1-65535)"; exit 1; }
if [[ -n "$PAIR_CODE" && ! "$PAIR_CODE" =~ ^[0-9]{6}$ ]]; then
    echo "'$PAIR_CODE' is not a valid pairing code (6 digits)"; exit 1
fi

# Last octet must be a number in 0-255.
if [[ ! "$OCTET" =~ ^[0-9]{1,3}$ ]] || (( OCTET > 255 )); then
    echo "'$OCTET' is not a valid last octet (0-255)"; exit 1
fi
IP="${IP_PREFIX}.${OCTET}"

echo "-> Starting adb server..."
"$ADB" start-server

# Wireless debugging: pairing replaces the USB + `adb tcpip` step entirely.
# The connection port differs from the pairing port and changes on every toggle, so it is
# discovered from the device's mDNS announcement instead of being asked for.
MDNS_WAIT_SECONDS=10

find_connect_endpoint() {
    "$ADB" mdns services 2>/dev/null | tr '\r' '\n' \
        | awk -v ip="$1" '$2 ~ /_adb-tls-connect/ && index($3, ip ":") == 1 {print $3; exit}'
}

if [[ -n "$PAIR_CODE" ]]; then
    echo "-> Pairing with ${IP}:${PORT}..."
    pair_output="$("$ADB" pair "${IP}:${PORT}" "${PAIR_CODE}" 2>&1)" || true
    echo "$pair_output"
    [[ "$pair_output" == *"Successfully paired"* ]] || { echo "Pairing failed"; exit 1; }

    echo "-> Looking for the connection port..."
    endpoint=""
    for (( i = 0; i < MDNS_WAIT_SECONDS; i++ )); do
        endpoint="$(find_connect_endpoint "$IP")"
        [[ -n "$endpoint" ]] && break
        sleep 1
    done
    if [[ -z "$endpoint" ]]; then
        echo "Paired, but could not find the connection port. Connect with the port shown on the"
        echo "device's Wireless debugging screen: adb connect ${IP}:<port>"
        exit 1
    fi
    echo "-> Connecting to ${endpoint}..."
    "$ADB" connect "${endpoint}"
    exit 0
fi

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
