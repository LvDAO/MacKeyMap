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
- GitHub Releases must be signed with the same Apple Development identity used for local testing. Ad-hoc signed builds can break `Input Monitoring`, even if the user re-grants the permission.
- Configure these GitHub Actions secrets before publishing:
  - `MACKEYMAP_SIGNING_CERT_BASE64`: base64-encoded `.p12` export of the Apple Development certificate
  - `MACKEYMAP_SIGNING_CERT_PASSWORD`: password used for the `.p12` export
  - `MACKEYMAP_KEYCHAIN_PASSWORD`: temporary runner keychain password
  - `MACKEYMAP_SIGN_IDENTITY`: exact signing identity string, for example `Apple Development: name@example.com (TEAMID)`
- `release.yml` now fails fast if those secrets are missing, instead of shipping a broken ad-hoc release.
- Keep release notes explicit about installation steps, permissions, and the expected Gatekeeper warning flow.
