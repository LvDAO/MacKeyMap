# MacKeyMap

MacKeyMap is a small macOS menu bar app for remapping an external Windows-layout keyboard to macOS behavior.

## Install

1. Download the latest release from GitHub Releases.
2. Open `MacKeyMap.app`.
3. If macOS blocks the app on first launch, use `Open` from Finder or allow it in System Settings.
4. Grant `Input Monitoring` when prompted.

## Use

1. Plug in or reconnect your external keyboard.
2. Click the MacKeyMap menu bar icon.
3. Turn on `Enable Remapping`.
4. In `Connected Keyboards`, make sure your keyboard is enabled.

Available options:

- `Swap Left Alt and Win`
- `Swap Right Alt and Win`
- `Disable Context Menu Remap`
- `Launch at Login`

## Diagnostics

MacKeyMap stores logs and config here:

- `~/Library/Application Support/MacKeyMap/config.json`
- `~/Library/Application Support/MacKeyMap/Logs/app.log`
- `~/Library/Application Support/MacKeyMap/Logs/engine.log`

You can also use:

- `Diagnostics > Open Diagnostics Folder`
- `Diagnostics > Export Diagnostics…`
