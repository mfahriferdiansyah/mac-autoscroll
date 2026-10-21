<p align="center"><img src="assets/icon.png" width="128" alt="AutoScroll icon"></p>

<h1 align="center">AutoScroll</h1>

<p align="center">Hands-free scrolling from your Mac's menu bar.</p>

<p align="center">
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-orange?style=flat-square">
  <img alt="menu bar app" src="https://img.shields.io/badge/menu%20bar-app-blue?style=flat-square">
</p>

## What it does

AutoScroll is a small menu bar app that scrolls the window under your mouse pointer, so you can read a long page hands-free. Pick a mode and a speed, press the hotkey once to start and again to stop. It works in any app, because it posts real scroll events rather than driving a particular window.

## Features

Everything is set inline in the menu bar menu: no submenus.

| Setting | Control | Notes |
| --- | --- | --- |
| Mode | Auto / Delay | Auto scrolls continuously. Delay scrolls a short eased burst (4 s worth of the speed, over 0.3 s), then waits. |
| Speed | Slider, 10-400 px/s | Logarithmic, so the slow end is fine-grained. Default 90 px/s. |
| Delay | Slider, 1-30 s | Wait between bursts in Delay mode. Default 3 s. |
| Direction | Down / Up | Default Down. |
| Hotkey | Change… | Record any shortcut with ⌘, ⌃ or ⌥ (or a single F-key). Reset to default restores ⌃⌥S. |
| Stop when I use the mouse | On / Off | On by default: moving the mouse, clicking or scrolling yourself stops it. |

Changes apply immediately, even while scrolling, and are remembered between launches. Quit from the menu (⌘Q while the menu is open).

## Download

Grab `AutoScroll.zip` from the latest [release](../../releases/latest), unzip it and move `AutoScroll.app` to `/Applications`. It is a universal app (Apple Silicon and Intel) for macOS 13 or later.

The app is not notarized by Apple, so the first launch is blocked. Right-click the app and choose **Open**, or go to System Settings → Privacy & Security and click **Open Anyway**. You only do this once.

## Build from source

You need macOS 13 or later and the Xcode Command Line Tools:

```sh
xcode-select --install
```

Then build and install:

```sh
git clone https://github.com/mfahriferdiansyah/mac-autoscroll.git
cd mac-autoscroll
./build.sh
```

`build.sh` compiles and ad-hoc signs `AutoScroll.app`, copies it to `~/Applications` and launches it. If you only want the app bundle in `build/`, run `./build.sh --build-only`.

## First run: Accessibility

AutoScroll posts scroll events to the system, which macOS only allows for apps trusted with Accessibility access. On first launch the app asks for it; you can also open System Settings → Privacy & Security → Accessibility and add AutoScroll there. The menu shows a "Grant Accessibility access" item whenever access is missing.

The app is ad-hoc signed, so every rebuild changes its signature: remove AutoScroll from that list and add it again after you rebuild. Until you do, scrolling silently does nothing.

## Use it with a macro button

The hotkey is an ordinary system hotkey, so you can trigger it from a mouse or keyboard macro. Map a button in Logitech Options+, BetterTouchTool, Karabiner-Elements or a similar tool to a shortcut, then record the same shortcut with Hotkey → Change… in the menu. F13-F19 are a good choice because nothing else uses them. One press starts scrolling, the next stops it.

Extra mouse buttons are not watched by "Stop when I use the mouse", so a macro button never stops and restarts the scroll by accident.

## Troubleshooting

- **Nothing scrolls.** Accessibility access is missing or stale after a rebuild. See First run above: remove and re-add AutoScroll in the Accessibility list.
- **It scrolls the wrong way.** Flip Direction in the menu.
- **The build fails with "redefinition of module 'SwiftBridging'" or "this SDK is not supported by the compiler".** Your Command Line Tools install has a stale module map that clashes with the SDK. `build.sh` already works around this; reinstalling the Command Line Tools fixes it properly.
- **The hotkey does nothing.** Another app owns that key. Record a different shortcut with Hotkey → Change…; F13-F19 are rarely taken.

## How it works

- A 60 Hz timer on the main run loop (in common modes, so it keeps running while menus are open) drives the scroll.
- Each tick posts a pixel-unit `CGEvent` scroll event at the HID tap, with sub-pixel accumulation so slow speeds stay smooth.
- The hotkey uses Carbon's `RegisterEventHotKey`, which needs no extra permission beyond Accessibility.
- "Stop when I use the mouse" is a global `NSEvent` monitor that ignores the app's own scroll events and the first half second after starting.
- No third-party dependencies and no network access: only AppKit and Carbon.
- Settings live in `UserDefaults`.

## Project layout

```
Sources/main.swift       the whole app
Info.plist               bundle metadata (LSUIElement menu bar app)
build.sh                 compile, sign, install
assets/                  icon used by this README
scripts/make-icon.swift  generates the icon
```
