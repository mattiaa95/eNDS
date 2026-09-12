# eNDS

A Nintendo DS emulator for iPhone and iPad, built on the
[melonDS](https://github.com/melonDS-emu/melonDS) emulation core.

This repository contains the complete source code of the eNDS app as it is
built and distributed. It is published under the **GNU GPLv3** (see
`LICENSE`) — the same license as melonDS — so that anyone who receives the
app can study, build and modify exactly what runs on their device.

## Built with AI assistance

This project was written with heavy use of AI coding assistants (Anthropic's
Claude, driven from Claude Code). A large share of the Swift and
Objective-C++ in `Targets/` was drafted by a model and then read, corrected,
tested on real devices and shipped by a human — but it would be dishonest to
present it as hand-typed work, so it is said here plainly rather than left
for you to guess from the commit log.

What that does **not** cover: the emulation core. `Vendor/melonDS` is
unmodified upstream melonDS, written by Arisotura and the melonDS team, and
no AI touched it.

## What eNDS adds on top of melonDS

- A native SwiftUI/UIKit iOS frontend: ROM library (with each cartridge's
  real banner icon), dual-screen layouts, an on-screen controller with a
  visual layout/style editor, pause menu, save states and auto-save.
- Real microphone input (blow/speak) resampled to the DS mic rate.
- External display / AirPlay support (TV shows the top screen, the device
  becomes the touch screen + controls).
- Game Controller framework + hardware keyboard support with remapping.
- `.zip` / `.7z` / `.gz` archive import, cheat codes, display filters,
  ReplayKit clip recording, per-game profiles.
- A layout that follows the window rather than the device: it reflows on
  iPad Split View, Stage Manager and continuously resizable windows.

## Credits

- **[melonDS](https://melonds.org)** — © Arisotura and the melonDS team,
  GPLv3. eNDS uses the core unmodified (see `Vendor/melonDS`, pinned as a
  submodule to the upstream commit each release builds against).
- **FreeBIOS** — the built-in BIOS replacement inside melonDS, © Gilead
  Kutnick (BSD). No Nintendo BIOS, firmware or keys are included anywhere
  in this repository or in the shipped app.
- **[teakra](https://github.com/wwylele/teakra)** — DSi DSP emulation, MIT.
- **LZMA SDK** (7z extraction) — Igor Pavlov, public domain.
- **minizip** (zip extraction) — Gilles Vollant, zlib license.

See `THIRD_PARTY.md` for the full component inventory — including the
libraries melonDS itself vendors (blip-buf, xxHash, FatFs, tiny-AES-c,
SHA-1) — and `Targets/INDS/Resources/Legal/NOTICES.txt` for their verbatim
license texts, which also ship inside the app (Settings › About › Licenses).

## Building

See `BUILDING.md`. Short version: build the melonDS static libraries with
CMake (exact flags documented), then open `eNDS.xcworkspace` and build the
`eNDS` scheme. No account-specific secrets are needed to build; signing uses
your own team.

## Releases

Every build of eNDS that leaves this machine gets a tag here — `v1.0-b29`,
`v1.0-b30`, … — and each tag is the complete corresponding source for that
exact binary. The current one has release notes on the [releases
page](https://github.com/mattiaa95/eNDS/releases). `main` may carry later
work (comment translations, docs) that is not in any binary yet; when in
doubt, build a tag.

What ships is what you see here: no ads, no analytics and no tracking SDKs
of any kind. The app's privacy policy is at
[mattiaa95.github.io/privacy.html](https://mattiaa95.github.io/privacy.html).

## Legal

- eNDS is an unofficial project. It is **not** affiliated with, or endorsed
  by, the melonDS team, and **not** affiliated with Nintendo. "Nintendo DS"
  is a trademark of Nintendo Co., Ltd., used here only to describe
  compatibility.
- eNDS is also unrelated to earlier DS emulator projects for iOS that used
  similar names (such as the nds4ios/iNDS lineage) — it shares no code or
  authorship with them, and its emulation core is melonDS.
- eNDS does not include any games and does not link to ROM sites. Play only
  backups of cartridges you legally own.
