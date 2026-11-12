# AndroidStudioScripts

Scripts to use from Android Studio through a toolbar button.

## connect_wifi.sh

Connects an Android device to adb over wifi, from a single form with:

| Field | Required | Default | Notes |
|---|---|---|---|
| IP last part | Yes | | Last number of the device IP (`192.168.1.___`) |
| Port | No | `5555` | With a pairing code, the **pairing port** shown next to the code |
| Pairing code | No | | 6 digits. Leave empty to connect through USB |

It works in two modes:

- **USB → wifi** (no pairing code): the device is plugged in via USB, the script switches it to TCP/IP on the given port and connects to it over wifi. If several USB devices are plugged in, it asks which one to use.
- **Wireless debugging** (with a pairing code, Android 11+): no cable needed. The script pairs with the device, then finds the connection port by itself (it's a different, random port) and connects.

Requirements: macOS (for the form) and the Android SDK platform-tools (installed with Android Studio).

## Setup in a new Android Studio install

### 1. Get the script

```bash
git clone https://github.com/yvhalo/AndroidStudioScripts.git ~/Developer/personal/AndroidStudioScripts
chmod +x ~/Developer/personal/AndroidStudioScripts/connect_wifi.sh
```

Any folder works; just use the same path in the next step.

### 2. Register it as an External Tool

1. Open **Android Studio → Settings → Tools → External Tools**.
2. Click **+** and fill in:
   - **Name:** `Connect wifi`
   - **Description:** `Connect wifi devices`
   - **Program:** `$USER_HOME$/Developer/personal/AndroidStudioScripts/connect_wifi.sh`
   - **Arguments:** leave **empty** (otherwise the form is skipped)
   - **Working directory:** `$ProjectFileDir$`
3. Under **Advanced Options**, keep **Open console for tool output** checked to see what adb does.
4. Click **OK** and **Apply**.

The tool is now available under **Tools → External Tools → Connect wifi**.

### 3. Add a toolbar button (optional)

1. Open **Settings → Appearance & Behavior → Menus and Toolbars**.
2. Select **Main Toolbar** (or the toolbar group where you want the button) and click **+ → Add Action…**.
3. Choose **External Tools → Connect wifi** and click **OK**.
4. To give it an icon, select the new entry, click **Edit Icon** and search for `AdbDevicePairing`.
5. Click **Apply**.

Settings are stored per Android Studio version. When a new version imports your settings, the tool and button come along; on a clean install, repeat steps 2 and 3.

## Usage

### USB → wifi

1. Plug the device in via USB and accept the debugging prompt on the device.
2. Click **Connect wifi**.
3. Enter the last part of the device IP. Keep port `5555` unless you need another one. Leave the pairing code empty.
4. Click **Connect**. You can unplug the cable once the console shows `connected to …`.

### Wireless debugging (no cable)

1. On the device: **Settings → Developer options → Wireless debugging** → turn it on → **Pair device with pairing code**. Keep that popup open.
2. Click **Connect wifi**.
3. Enter the last part of the IP shown in the popup, the **port shown in the popup** (not 5555) and the 6-digit code.
4. Click **Connect**.

Once a device has been paired, it usually reconnects by itself the next time wireless debugging is turned on.

### From a terminal

```bash
./connect_wifi.sh                      # opens the form
./connect_wifi.sh 45                   # USB → wifi on port 5555
./connect_wifi.sh 45 5556              # USB → wifi on port 5556
./connect_wifi.sh 45 37011 123456      # wireless debugging: pairing port + code
```

The values can also be passed as a single space-separated argument (`./connect_wifi.sh "45 37011 123456"`).

### Environment variables

| Variable | Default | Use |
|---|---|---|
| `IP_PREFIX` | `192.168.1` | First three parts of the IP, if your network uses another range |
| `GUI` | `1` | `GUI=0` asks each value in the console instead of the form |

## Troubleshooting

- **`Pairing failed`**: check the port is the one in the pairing popup (it changes every time the popup opens) and that the popup is still open.
- **`Paired, but could not find the connection port`**: connect by hand with the port shown on the device's Wireless debugging screen: `adb connect <ip>:<port>`.
- **`No USB device connected`**: plug the device in, or use a pairing code instead.
- **adb not found**: the script looks for adb in `$ANDROID_SDK_ROOT`, `$ANDROID_HOME` and `~/Library/Android/sdk`. Set one of those variables if your SDK lives elsewhere.
- **The device and the Mac must be on the same network.**
