# Developing KeepAwake

Everything the app does lives in `Sources/main.swift`. There is no Xcode project
and no package manifest — `build.sh` drives `swiftc` directly and assembles the
bundle by hand.

| File | Role |
| --- | --- |
| `Sources/main.swift` | The entire app |
| `build.sh` | Compiles both architectures, signs, and packages |
| `release.sh` | Bumps the version, signs the update, publishes |
| `makeicon.swift` | Renders the icon from an SF Symbol into `.icns` |
| `appcast.xml` | The update feed clients poll — committed, not generated at runtime |
| `VERSION` | Single source of truth for the version number |

## Building

```bash
./build.sh
```

Produces, in `build/`:

- `KeepAwake.app` — universal (arm64 + x86_64), macOS 13+
- `KeepAwake-<version>.dmg` — what people download
- `KeepAwake-<version>.zip` — what Sparkle installs

Sparkle is fetched into `vendor/` on first build and cached, so the 3 MB
framework never enters git history.

## How it works

The app is one IOKit power assertion:

```swift
IOPMAssertionCreateWithName(
    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    "KeepAwake: user requested" as CFString,
    &assertionID
)
```

The kernel owns that flag until it's released, so nothing has to run to keep it
alive. The menu is rebuilt only when opened, and a `Timer` exists only during a
timed session — with a 30-second tolerance so macOS can coalesce the wake-up with
other scheduled work. An idle KeepAwake schedules nothing at all.

Switching **Keep Display On** swaps the assertion type between
`PreventUserIdleDisplaySleep` and `PreventUserIdleSystemSleep`. The type is fixed
when an assertion is created, so an active session is torn down and retaken,
preserving whatever time was left.

Verify the live state at any point:

```bash
pmset -g assertions | grep -i keepawake
```

## Releasing

```bash
./release.sh 1.3 "What changed in this version."
```

That bumps `VERSION`, builds, signs the archive with the EdDSA key from your login
Keychain, regenerates `appcast.xml`, commits, pushes, and creates the GitHub
release with the DMG and ZIP attached.

**Publishing the appcast is what actually ships the update.** Existing installs
poll `appcast.xml` on the `main` branch via `raw.githubusercontent.com`, which is
CDN-cached — expect a few minutes before clients see a new version.

### The signing key

Update archives are signed with an EdDSA key whose public half is baked into the
app (`SUPublicEDKey` in `build.sh`). Sparkle refuses any download that doesn't
match, which is what makes updates safe despite the app not being notarized.

The private key lives in your login Keychain, with a backup at
`~/Documents/KeepAwake-signing/`. **If you lose it you can no longer ship updates
to existing installs** — they reject archives signed by any other key, and every
user would have to reinstall by hand. Anyone who obtains it can push an update
your users' Macs will trust and install, so keep it off the network.

Re-import it on another machine with:

```bash
vendor/Sparkle-*/bin/generate_keys -f keepawake-sparkle-private-key.txt
```

## Signing and notarization

Releases are **ad-hoc signed** (`codesign --sign -`). The app runs anywhere, but
Gatekeeper warns on first open because it isn't notarized by Apple.

Notarizing needs a **Developer ID Application** certificate, which requires a paid
Apple Developer Program membership. An *Apple Development* certificate will not
work — it only authorizes devices in your own provisioning profile. With a real
identity:

```bash
./build.sh "Developer ID Application: Your Name (TEAMID)"

xcrun notarytool store-credentials "AC" --apple-id you@example.com --team-id TEAMID
xcrun notarytool submit build/KeepAwake-<version>.dmg --keychain-profile "AC" --wait
xcrun stapler staple build/KeepAwake-<version>.dmg
```

The DMG then installs with no warning, and the right-click → Open step disappears
from the README instructions.

## Gotchas worth knowing

These each cost real debugging time:

- **Hardened runtime breaks ad-hoc builds.** `--options runtime` enables library
  validation, which requires the app and embedded framework to share a Team ID.
  Ad-hoc signatures have none, so dyld refuses to load Sparkle and the app dies at
  launch. `build.sh` applies it only for a real signing identity.
- **macOS ships bash 3.2**, where expanding an empty array under `set -u` aborts
  the script. Use strings for optional argument lists.
- **`supportsGentleScheduledUpdateReminders` must stay `false`.** Setting it true
  tells Sparkle the app will nudge the user itself — impossible for an accessory
  app with no Dock icon and no window, so found updates are silently deferred.
- **Sign inside-out.** Sparkle's XPC services, `Updater.app`, and `Autoupdate` are
  each signed before the framework, which is signed before the app. `--deep`
  leaves the nested helpers wrong.
