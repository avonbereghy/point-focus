# PointFocus

A tiny macOS menu-bar utility that warps the mouse cursor to a configurable point in the focused window every time you Cmd+Tab.

- **Global default** focus point (default: center).
- **Per-app overrides** set via a screenshot-tool-style picker — click anywhere on the target window, stored as a relative `(x, y)` so it stays meaningful across resizes.
- Menu-bar toggle to pause/resume.
- Optional launch at login.

## Requirements

- macOS 14 (Sonoma) or later.
- Accessibility permission (to read the focused window's frame).
- Input Monitoring permission (to detect Cmd+Tab).

## Build & install

```bash
chmod +x build.sh
./build.sh
```

Produces `build/PointFocus.app` and installs it to `~/Applications/PointFocus.app` (ad-hoc signed, universal binary).

## First run

1. Launch `~/Applications/PointFocus.app`.
2. An onboarding window lists the two required permissions. Click **Grant…** for each — macOS shows its native prompt and routes you to **System Settings → Privacy & Security**. Toggle PointFocus on, then return to the app; the window auto-dismisses once both are granted.
3. A `scope` icon appears in the menu bar.

## Usage

- **Cmd+Tab** as you normally would — the cursor lands on the configured point of the window you switched to.
- **Click** the menu-bar icon to open the settings popover. Everything lives here:
  - Toggle PointFocus on/off.
  - Edit the global default `(x, y)` directly, or click **Pick on screen…** to set it visually.
  - Click **Add app…** to pick an app from `/Applications` and assign a per-app focus point. The picker overlays the target app's focused window with a translucent tint and a live edge-to-edge crosshair — click anywhere to save, Esc to cancel.
  - Per-app rows let you **Re-pick** or **Remove** an override at any time.
  - Launch-at-login checkbox.

## Known limitations

- Apps that don't register with macOS's standard focus APIs (some Rust/Tauri menu-bar utilities) are invisible to the AX system-wide focused-window query and can't be targeted without Screen Recording permission, which PointFocus doesn't currently request.
- Only `Cmd`-held switching is handled; Mission Control and Spaces transitions are out of scope for V1.

## Uninstall

```bash
rm -rf ~/Applications/PointFocus.app
defaults delete com.avb.pointfocus.v1
```

Remove the Accessibility and Input Monitoring entries from **System Settings → Privacy & Security** if desired.

## Architecture

See [`specs/point_focus.spec.md`](specs/point_focus.spec.md) for the full feature spec and [`plans/point_focus_agent_plan.md`](plans/point_focus_agent_plan.md) for the layered architecture and wave-by-wave build plan.
