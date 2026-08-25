# omarchy-keymaps

An Omarchy bar plugin for managing Hyprland keyboard layouts.

## Features

- Shows the active layout in the bar.
- Opens a native Omarchy-style popup with configured layouts.
- Activates, adds, and removes layouts without editing files manually.
- Searches the installed XKB layout and variant catalogue.
- Persists `kb_layout` and `kb_variant` in `~/.config/hypr/input.lua`.
- Applies changes immediately through Hyprland.

The plugin intentionally manages Hyprland only. It does not require `sudo` and
does not change `localectl`, the virtual console, or fcitx5 profiles.

## Install

```bash
omarchy plugin add https://github.com/Majkelll/omarchy-keymaps.git --enable --yes
omarchy bar move io.github.majkelll.omarchy-keymaps --after omarchy.clock
```

To remove it and restore the built-in widget:

```bash
omarchy plugin remove io.github.majkelll.omarchy-keymaps --yes
```

## Usage

Click the layout label in the bar. The active layouts are listed first. Click a
layout to activate it, use the search field to find another XKB layout or
variant, and click `+` to add it. The last remaining layout cannot be removed.

Keyboard navigation is available with the arrow keys and Enter. Press `/` to
focus the search field and `R` to reload the XKB catalogue.

## Development

```bash
omarchy plugin validate .
node tests/model.test.js
```

The plugin runs inside `omarchy-shell` and can execute the bundled layout
writer. Review changes before enabling plugins from repositories you do not
control.
