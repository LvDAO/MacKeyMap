# MacKeyMap

MacKeyMap is a macOS menu bar utility that makes an external Windows-layout keyboard behave like a Mac keyboard with system-level remapping and minimal runtime overhead.

## How it works

- `IOHIDManager` is used for keyboard discovery, hot-plug handling, and per-device selection.
- Actual remapping is applied through `hidutil UserKeyMapping`, so the system HID layer performs the remap.
- The app does not post synthetic key events and does not require Accessibility permission.
- The built-in Mac keyboard is detected but not auto-enabled.
- Newly discovered external keyboards are auto-enabled unless the user explicitly disables them.

## Current remap scope

- `Left Win -> Left Command`
- `Right Win -> Right Command`
- `Left Alt -> Left Option`
- `Right Alt -> Right Option`
- `Menu/Application -> Right Command`

Overrides in the menu bar app:

- `Swap Left Alt and Win`
- `Swap Right Alt and Win`
- `Disable Context Menu Remap`

## Repository layout

- `rust-core/`: Rust engine for device discovery, config state, diagnostics logging, and `hidutil` orchestration
- `App/Sources/MacKeyMapApp/`: AppKit menu bar shell
- `Assets/`: source icon assets used for the menu bar template icon and app icon
- `scripts/build_app.sh`: local app bundle build
- `scripts/package_release.sh`: versioned release zip build
- `docs/RELEASING.md`: release/versioning process

## Local build

Debug build:

```bash
./scripts/build_app.sh
```

Release build:

```bash
./scripts/build_app.sh release
```

Versioned release zip:

```bash
./scripts/package_release.sh
```

Development run:

```bash
cargo build --workspace
swift run MacKeyMapApp
```

## Local testing

1. Launch the built app:
   ```bash
   open /Users/lyuwt/MacKeyMap/dist/MacKeyMap.app
   ```
2. Grant `Input Monitoring` when prompted.
3. Plug in or reconnect the target keyboard.
4. Use the menu bar app to verify:
   - `Enable Remapping` is on
   - the keyboard appears in `Connected Keyboards`
   - the device shows `System remap active`

## Diagnostics

MacKeyMap now writes diagnostics into:

- config: `/Users/lyuwt/Library/Application Support/MacKeyMap/config.json`
- app log: `/Users/lyuwt/Library/Application Support/MacKeyMap/Logs/app.log`
- engine log: `/Users/lyuwt/Library/Application Support/MacKeyMap/Logs/engine.log`

Menu bar diagnostics actions:

- `Diagnostics > Open Diagnostics Folder`
- `Diagnostics > Export Diagnostics…`

The export archive includes:

- configuration snapshot
- engine snapshot
- app log
- engine log
- a short summary file with version and device state

## Menu bar status icon

The menu bar icon uses the monochrome command-mark asset as a template icon and adds a small badge so status is recognizable at a glance:

- solid dot: at least one selected keyboard is actively remapped
- hollow ring: app is enabled but currently idle
- minus bar: remapping is globally disabled
- triangle: permission or engine attention is required

## CI/CD

- `ci.yml` runs on every push, pull request, and manual dispatch on `macos-14`
- CI runs `cargo test --workspace`, runs the remap payload benchmark, builds the release app, and uploads a build artifact
- `release.yml` runs on `v*` tags and publishes a GitHub Release artifact
- Current public artifacts are intended for direct distribution outside the Mac App Store

## Distribution notes

- This project is currently aimed at direct GitHub or website distribution, not the Mac App Store.
- Without a paid Apple Developer membership, releases are not notarized.
- Users should expect a Gatekeeper warning on first launch and may need to use `Open` from Finder or System Settings to allow the app.

## Versioning and release process

- The bundle version is stored in [`VERSION`](/Users/lyuwt/MacKeyMap/VERSION).
- Release tags use the `vX.Y.Z` format.
- The detailed release checklist is in [`docs/RELEASING.md`](/Users/lyuwt/MacKeyMap/docs/RELEASING.md).
