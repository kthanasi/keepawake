<div align="center">

# KeepAwake

**A tiny macOS menu-bar app that stops your screen from sleeping.**

[![Download](https://img.shields.io/github/v/release/kthanasi/keepawake?label=download&style=flat-square)](https://github.com/kthanasi/keepawake/releases/latest)
[![Platform](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square)](https://github.com/kthanasi/keepawake/releases/latest)
[![Universal](https://img.shields.io/badge/binary-universal-blue?style=flat-square)](https://github.com/kthanasi/keepawake/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

</div>

---

KeepAwake holds a single IOKit power assertion — the same kernel mechanism
`caffeinate` uses — so the work of staying awake is done by macOS, not by the app.
There is no polling loop, no background timer, and no busywork to burn battery.

- **Free of overhead** — 0.0% CPU and ~40 MB RSS while active
- **Universal binary** — Apple Silicon and Intel, macOS 13+
- **Under 400 KB**, no dependencies, no network access
- **Timed sessions** that expire on their own so you can't forget to turn it off

## Install

1. Download **KeepAwake-1.0.dmg** from the
   [latest release](https://github.com/kthanasi/keepawake/releases/latest).
2. Open the DMG and drag **KeepAwake** into **Applications**.
3. **First launch only:** right-click (or Control-click) KeepAwake in
   `/Applications` and choose **Open**, then click **Open** in the dialog.

Step 3 is required because the app is ad-hoc signed rather than notarized (see
[Signing](#signing-and-notarization)). A plain double-click on the very first run
will be blocked by Gatekeeper. Every launch after that is normal.

If macOS still refuses, clear the download quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/KeepAwake.app
```

## Usage

Click the cup icon in the menu bar. A filled cup means it's awake; an outline
means normal sleep is allowed.

| Menu item | What it does |
| --- | --- |
| **Indefinitely** | Stay awake until you turn it off |
| **For 15m / 30m / 1h / 2h / 5h** | Timed session that expires on its own |
| **Turn Off** | End the session now |
| **Keep Display On** | Uncheck to let the *screen* sleep while keeping the *Mac* awake |
| **Start on Login** | Register KeepAwake as a login item |
| **Activate on Launch** | Turn on automatically whenever the app starts |
| **Check for Updates…** | Ask the update feed right now |
| **Update Automatically** | Download and install new versions in the background |

The menu header always shows the current state and the time remaining.

Confirm it's working at any point:

```bash
pmset -g assertions | grep -i keepawake
```

`PreventUserIdleDisplaySleep` means the screen is being held on.
`PreventUserIdleSystemSleep` means only the machine is.

## Updates

KeepAwake updates itself with [Sparkle](https://sparkle-project.org). It checks
[`appcast.xml`](appcast.xml) on this repo once a day, and offers anything newer
than the running version — you can also check on demand from the menu, or turn on
**Update Automatically** to have it install silently.

Every update archive is signed with an EdDSA key whose public half is baked into
the app. Sparkle refuses any download whose signature doesn't match, so a
tampered or substituted archive can't be installed even though the app itself is
not notarized.

### Cutting a release

```bash
./release.sh 1.1 "What changed in this version."
```

That bumps `VERSION`, builds, signs the archive with the private key from your
login Keychain, regenerates `appcast.xml`, pushes, and creates the GitHub release
with both the DMG and the ZIP attached. Publishing the appcast is what actually
ships the update — existing installs pick it up within a day.

The private signing key lives only in your Keychain. **If you lose it you cannot
ship updates to existing installs**, since they will reject archives signed by any
other key; everyone would have to reinstall by hand.

## How it works

The whole app is one power assertion:

```swift
IOPMAssertionCreateWithName(
    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
    IOPMAssertionLevel(kIOPMAssertionLevelOn),
    "KeepAwake: user requested" as CFString,
    &assertionID
)
```

The kernel owns that flag until it's released, so nothing has to run to maintain
it. The menu is rebuilt only at the moment you open it, and a `Timer` exists only
during a timed session — with a 30-second tolerance so macOS can coalesce the
wake-up with other scheduled work. An idle KeepAwake schedules nothing at all.

## Building

```bash
./build.sh
```

Produces `build/KeepAwake.app` and `build/KeepAwake-1.0.dmg`.

| File | Role |
| --- | --- |
| `Sources/main.swift` | The entire app |
| `makeicon.swift` | Renders the icon from an SF Symbol into `.icns` |
| `build.sh` | Compiles both architectures, lipos them, signs, and builds the DMG |

## Signing and notarization

Releases are **ad-hoc signed** (`codesign --sign -`). The app runs on any Mac, but
Gatekeeper warns on first open because it is not notarized by Apple.

Notarizing requires a **Developer ID Application** certificate, which needs a paid
Apple Developer Program membership. If you have one, the build script already
takes it:

```bash
./build.sh "Developer ID Application: Your Name (TEAMID)"

xcrun notarytool store-credentials "AC" --apple-id you@example.com --team-id TEAMID
xcrun notarytool submit build/KeepAwake-1.0.dmg --keychain-profile "AC" --wait
xcrun stapler staple build/KeepAwake-1.0.dmg
```

After that the DMG installs with no warning at all.

## License

[MIT](LICENSE) © 2026 Kotabitus.

A copy also ships inside the app bundle at
`KeepAwake.app/Contents/Resources/LICENSE` and alongside the app in the DMG.
