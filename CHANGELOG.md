# Changelog

## 1.1.0 - 2026-08-26

- Add a KEY REMAPPING section: press "+ Add a key remap" (or `A`), then press
  the key to remap and the key it should act as. Covers letters, digits,
  function keys, modifiers (left/right distinguished), and the navigation
  cluster, with an optional one-step "also map back" swap. Existing mappings
  collapse into an expandable list.
- Remaps are generated as an XKB symbols file under `~/.config/xkb/symbols/`
  and applied by augmenting `kb_layout`, validated with
  `xkbcli compile-keymap --test` before anything is written.

## 1.0.0 - 2026-08-26

First stable release.

- Bar widget showing the active Hyprland keyboard layout.
- Popup panel to activate, add, and remove layouts.
- Search over the installed XKB layout and variant catalogue.
- Full keyboard navigation (arrows, Enter, `/`, `R`).
- Layout changes are persisted to `~/.config/hypr/input.lua` and applied
  immediately through `hyprctl`.
