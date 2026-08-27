# Changelog

## 1.1.1 - 2026-08-27

- Fix the search field swallowing letters: the panel's key catcher claims
  `h`/`j`/`k`/`l` for navigation and `x` for delete, so typing "polish" into
  the layout search only ever reached it as "pois". The catcher now stands
  down while the field has focus, and Escape returns focus to the panel.
- Rebuild the panel on the shared Omarchy panel kit — `PanelHero`,
  `CursorSurface` rows, `PanelActionButton`, `Button`, `ToggleSwitch`, and
  the kit's `TextField` — instead of hand-rolled rectangles, so the popup
  follows the active theme's control tokens like every first-party panel.
- Replace the capture prompt's checkbox with a `ToggleSwitch`, which cannot
  take keyboard focus and so cannot swallow the keypress the prompt is
  waiting for.
- Name active layouts from the XKB catalogue ("PL Polish") rather than
  repeating the code back ("PL PL") after a refresh.
- Keyboard cursor now scrolls the selected row into view, and `x` removes the
  selected layout or remap.
- Reject a keymap that logs an XKB error but still compiles; `xkbcli` alone
  reports success for a bad rule inside an included file.
- Stop leaking the validation scratch directory on every applied remap.
- Retrigger a pending refresh when the `kb_variant` read is the last one to
  finish, and drop an unused retry timer.

## 1.1.0 - 2026-08-26

- Add a KEY REMAPPING section: press "+ Add a key remap" (or `A`), then press
  the key to remap and the key it should act as. Covers letters, digits,
  function keys, modifiers (left/right distinguished), and the navigation
  cluster. "Map both ways" turns the two keys into a swap, shown as one
  `Caps Lock ⇄ Escape` row. Existing mappings collapse into an expandable
  list.
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
