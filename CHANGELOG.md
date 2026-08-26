# Changelog

## 1.1.0 - 2026-08-26

- Add a KEY REMAPPING section: remap any key (letters, digits, function
  keys, modifiers, navigation cluster) to any other key, with an optional
  one-step "also remap the target back" swap.
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
