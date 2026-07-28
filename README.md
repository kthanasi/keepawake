<div align="center">

# KeepAwake

**Stop your Mac's screen from going to sleep — from the menu bar.**

[![Download](https://img.shields.io/github/v/release/kthanasi/keepawake?label=Download&style=for-the-badge)](https://github.com/kthanasi/keepawake/releases/latest)

[![Platform](https://img.shields.io/badge/macOS-13%2B-black?style=flat-square)](https://github.com/kthanasi/keepawake/releases/latest)
[![Universal](https://img.shields.io/badge/Apple_Silicon_%26_Intel-blue?style=flat-square)](https://github.com/kthanasi/keepawake/releases/latest)
[![Size](https://img.shields.io/badge/download-3.5_MB-lightgrey?style=flat-square)](https://github.com/kthanasi/keepawake/releases/latest)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

</div>

---

Presenting, reading, watching, waiting on a long build — sometimes you just need
the screen to stay on. KeepAwake puts a coffee cup in your menu bar that does
exactly that, and nothing else.

It asks macOS to hold the screen awake using the same built-in mechanism the
system's own `caffeinate` command uses. That means **the Mac does the work, not
the app** — KeepAwake sits at 0% CPU the entire time it's running.

- ☕️ **One click** to stay awake, one click to stop
- ⏱ **Timed sessions** that switch themselves off, so you can't forget
- 🔋 **No battery cost** of its own — no loops, no timers, nothing spinning
- 🪶 **Tiny** — under 4 MB, no dependencies, no account, no network beyond update checks
- 🔄 **Keeps itself up to date**

## Install

1. **[Download the latest version →](https://github.com/kthanasi/keepawake/releases/latest)**
   (grab the `.dmg`)
2. Open it and drag **KeepAwake** into your **Applications** folder.
3. **The first time you open it:** right-click (or Control-click) KeepAwake in
   Applications and choose **Open**, then click **Open** again in the dialog.

> **Why the extra step?** macOS shows a warning for apps that haven't been
> through Apple's paid notarization program. Right-click → Open is macOS's normal
> way of saying "I trust this one." You only do it once — after that KeepAwake
> opens like any other app.

Nothing appears in the Dock. Look for the ☕️ cup at the top-right of your screen.

## Using it

Click the cup icon in the menu bar. **A filled cup means your screen is being
kept on. An outline cup means normal sleep behaviour.**

| Menu item | What it does |
| --- | --- |
| **Indefinitely** | Stay awake until you switch it off |
| **For 15 min / 30 min / 1h / 2h / 5h** | Stay awake, then stop automatically |
| **Turn Off** | Go back to normal right away |
| **Keep Display On** | Turn this *off* to let the screen sleep while the Mac keeps working — handy for long downloads or exports |
| **Start on Login** | Open KeepAwake automatically when you log in |
| **Activate on Launch** | Start out awake whenever the app opens |
| **Check for Updates…** | Look for a new version now |
| **Update Automatically** | Install new versions in the background |

The top of the menu always tells you the current state and how much time is left.

## Updates

KeepAwake checks for new versions once a day and will offer them to you. You can
also check whenever you like from the menu, or let it update silently.

Updates are cryptographically signed, and the app refuses to install anything
that isn't signed with the project's key — so an update can't be tampered with in
transit.

## Uninstalling

Quit KeepAwake from its menu, then drag `KeepAwake.app` from Applications to the
Trash. If you'd like to remove its settings too:

```bash
defaults delete com.kthanasi.KeepAwake
rm -rf ~/Library/Caches/com.kthanasi.KeepAwake
```

## Questions

**Does it stop the screen from locking?**
It prevents the screen from *sleeping*, which also prevents the lock that follows.
It does not change your password or Screen Time settings.

**Will it keep my Mac awake with the lid closed?**
No. Closing the lid always sleeps the machine.

**Does it drain my battery?**
The app itself costs nothing measurable. Your screen staying on does use power —
that's the point of it — so a timed session is the battery-friendly choice.

**Does it send my data anywhere?**
No. The only network request it ever makes is checking for a new version.

## Building it yourself

The whole app is one Swift file. See **[DEVELOPING.md](DEVELOPING.md)** for
building, signing, and publishing releases.

## License

[MIT](LICENSE) © 2026 Kotabitus — free to use, change, and share.
