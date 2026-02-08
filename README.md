<p align="center">
  <img src="assets/Assets.xcassets/AppIcon.appiconset/appicon_128.png" alt="appsmute icon" width="128" height="128" />
</p>

<h1 align="center">appsmute</h1>

<p align="center">Minimal macOS menu-bar app to mute/unmute only selected apps with hotkeys and quick controls.</p>

## Unique Features

- Select exactly which running apps should be muted
- ON/OFF status-bar control with instant toggle
- Add/remove custom hotkeys directly from the menu
- Built-in `Sounds` and `Language` submenus
- JSON-based `assets/langs/` localization (no `.strings` files)

## Requirements (Minimal)

- macOS 14+
- Xcode 15+ (to build)

## Build

Open `appsmute.xcodeproj` in Xcode and run.

## Localization

All user-visible strings live in `assets/langs/`.
Add a new `*.json` with `"language_name"` to create a new language.
