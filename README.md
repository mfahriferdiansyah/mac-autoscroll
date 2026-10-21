# AutoScroll

Tiny macOS menu bar app that scrolls for you.

- **Fully auto**: smooth continuous scroll at the chosen speed.
- **Delay**: scrolls a chunk every N seconds (1–20s), chunk size follows the speed.
- **Speed**, **direction** and **hotkey** are set from the menu bar icon and remembered.
- **Hotkey** toggles start/stop: `⌃⌥S` (default), `F13`, `F14` or `F15`. Map a mouse/keyboard macro button to it.
- **Quit** from the menu (`⌘Q` while the menu is open).

It scrolls whatever is under the mouse pointer.

## Build & run

```sh
./build.sh
```

Builds `AutoScroll.app`, installs it to `~/Applications` and launches it. Needs the Xcode Command Line Tools.

On first start macOS asks for **Accessibility** access (System Settings → Privacy & Security → Accessibility). Scrolling does nothing until it is granted. The app is ad-hoc signed, so after a rebuild remove and re-add it in that list.
