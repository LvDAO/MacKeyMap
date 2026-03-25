# Release Process

MacKeyMap uses semantic versioning for user-facing releases:

- `MAJOR`: incompatible behavior or configuration changes
- `MINOR`: new features or broader device/remap support
- `PATCH`: bug fixes, packaging fixes, documentation-only diagnostics improvements

## Source of truth

- [`VERSION`](/Users/lyuwt/MacKeyMap/VERSION) stores the app bundle version shown in Finder and the menu bar diagnostics.
- [`rust-core/Cargo.toml`](/Users/lyuwt/MacKeyMap/rust-core/Cargo.toml) should stay in sync with `VERSION` for crate metadata.
- Git tags use the `vX.Y.Z` form, for example `v0.1.0`.

## Pre-release checklist

1. Update [`VERSION`](/Users/lyuwt/MacKeyMap/VERSION).
2. Keep [`rust-core/Cargo.toml`](/Users/lyuwt/MacKeyMap/rust-core/Cargo.toml) on the same version.
3. Run:
   ```bash
   cargo test --workspace
   swift build
   ./scripts/build_app.sh release
   ./scripts/package_release.sh
   ```
4. Smoke-test the built app:
   - launch it
   - verify your keyboard still appears in `Connected Keyboards`
   - verify remap is active
   - verify `Export Diagnostics…` succeeds
5. Review the generated archive in `dist/`.

## GitHub release flow

1. Commit the version bump and release notes changes.
2. Create an annotated tag:
   ```bash
   git tag -a v0.1.0 -m "MacKeyMap 0.1.0"
   ```
3. Push the branch and the tag:
   ```bash
   git push origin main
   git push origin v0.1.0
   ```
4. GitHub Actions `release.yml` rebuilds the app and uploads the versioned zip to the Release page.

## Distribution notes

- Current releases are intended for direct website or GitHub distribution, not the Mac App Store.
- Without a paid Apple Developer membership, artifacts remain unsigned or ad hoc signed and are not notarized.
- Keep release notes explicit about installation steps, permissions, and the expected Gatekeeper warning flow.
