// Pure layout parsing and list operations. Kept independent of Qt so it can
// be tested with Node as well as imported from QML.

function clean(value) {
  return String(value === undefined || value === null ? "" : value).trim()
}

function splitList(value) {
  var text = clean(value)
  if (text === "") return []
  return text.split(",").map(clean)
}

function optionString(raw) {
  try {
    var parsed = JSON.parse(String(raw || "{}"))
    return clean(parsed.str)
  } catch (error) {
    return ""
  }
}

function entryKey(entry) {
  return clean(entry.layout) + "|" + clean(entry.variant)
}

function baseLayoutCode(token) {
  var text = clean(token)
  var plusIndex = text.indexOf("+")
  return plusIndex === -1 ? text : text.slice(0, plusIndex)
}

function layoutEntries(layoutRaw, variantRaw) {
  var layouts = splitList(layoutRaw).map(baseLayoutCode)
  var variants = splitList(variantRaw)
  var entries = []

  for (var i = 0; i < layouts.length; i++) {
    entries.push({
      layout: layouts[i],
      variant: variants[i] || "",
      description: layouts[i].toUpperCase() + (variants[i] ? " - " + variants[i] : "")
    })
  }

  return entries
}

// Every XKB layout group needs its own copy of the augmentation (with an
// explicit 1-based :N group index - required once more than one group is
// present, harmless on a single group) so the remap stays active no matter
// which language layout is currently switched to. Verified empirically with
// `xkbcli compile-keymap`: omitting the :N index on multi-group layouts
// produces an "Illegal include statement" compile error.
function augmentLayouts(layoutsCsv, hasRemaps) {
  var tokens = splitList(layoutsCsv).map(baseLayoutCode)
  if (hasRemaps) {
    tokens = tokens.map(function(token, index) {
      return token + "+omarchy-keymaps(remap):" + (index + 1)
    })
  }
  return tokens.join(",")
}

function serializeEntries(entries) {
  var layouts = []
  var variants = []

  for (var i = 0; i < entries.length; i++) {
    layouts.push(clean(entries[i].layout))
    variants.push(clean(entries[i].variant))
  }

  return {
    layouts: layouts.join(","),
    variants: variants.join(",")
  }
}

function parseXkb(raw) {
  var rows = []
  var current = null
  var lines = String(raw || "").split("\n")

  function flush() {
    if (!current || !current.layout) return
    if (!current.description) {
      current.description = current.layout.toUpperCase()
        + (current.variant ? " - " + current.variant : "")
    }
    rows.push(current)
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var layoutMatch = line.match(/^- layout: ['"]?([^'"\s]+)['"]?\s*$/)
    if (layoutMatch) {
      flush()
      current = {
        layout: layoutMatch[1],
        variant: "",
        brief: "",
        description: ""
      }
      continue
    }
    if (!current) continue

    var variantMatch = line.match(/^\s+variant: ['"]?(.*?)['"]?\s*$/)
    if (variantMatch) {
      current.variant = variantMatch[1]
      continue
    }

    var briefMatch = line.match(/^\s+brief: ['"]?(.*?)['"]?\s*$/)
    if (briefMatch) {
      current.brief = briefMatch[1]
      continue
    }

    var descriptionMatch = line.match(/^\s+description: ['"]?(.*?)['"]?\s*$/)
    if (descriptionMatch) current.description = descriptionMatch[1]
  }
  flush()

  var unique = []
  var seen = {}
  for (var j = 0; j < rows.length; j++) {
    var key = entryKey(rows[j])
    if (seen[key]) continue
    seen[key] = true
    unique.push(rows[j])
  }

  return unique.sort(function(a, b) {
    return String(a.description).localeCompare(String(b.description))
  })
}

var POPULAR_KEYS = [
  "pl|", "us|", "gb|", "de|", "fr|", "es|", "it|", "cz|", "sk|", "ua|", "ru|"
]

function isConfigured(row, configured) {
  for (var i = 0; i < configured.length; i++) {
    if (entryKey(row) === entryKey(configured[i])) return true
  }
  return false
}

function matchScore(row, needle) {
  var layout = String(row.layout).toLowerCase()
  var variant = String(row.variant).toLowerCase()
  var description = String(row.description).toLowerCase()

  if (layout === needle && variant === "") return 0
  if (layout === needle) return 1
  if (layout.indexOf(needle) === 0) return 2
  if (variant.indexOf(needle) === 0) return 3
  if (description.indexOf(needle) !== -1) return 4
  return 5
}

function filterAvailable(rows, configured, query) {
  var needle = clean(query).toLowerCase()
  var filtered = rows.filter(function(row) {
    if (isConfigured(row, configured)) return false
    if (needle === "") return POPULAR_KEYS.indexOf(entryKey(row)) !== -1

    return String(row.layout).toLowerCase().indexOf(needle) !== -1
      || String(row.variant).toLowerCase().indexOf(needle) !== -1
      || String(row.description).toLowerCase().indexOf(needle) !== -1
  })

  if (needle !== "") {
    filtered.sort(function(a, b) {
      var scoreDifference = matchScore(a, needle) - matchScore(b, needle)
      if (scoreDifference !== 0) return scoreDifference

      var layoutDifference = String(a.layout).localeCompare(String(b.layout))
      if (layoutDifference !== 0) return layoutDifference

      var variantDifference = String(a.variant).localeCompare(String(b.variant))
      if (variantDifference !== 0) return variantDifference

      return String(a.description).localeCompare(String(b.description))
    })
  }

  return filtered.slice(0, 80)
}

function labelFor(entry) {
  return clean(entry.layout).toUpperCase()
}

// Curated, verified against `xkbcli compile-keymap --layout us` evdev
// keycode names and their default keysyms. Deliberately scoped to letters,
// digits, function keys, modifiers, common utility keys, and the navigation
// cluster - numpad and multimedia keys are out of scope for v1.
var KEY_TABLE = [
  { code: "AD01", keysym: "q", label: "Q" },
  { code: "AD02", keysym: "w", label: "W" },
  { code: "AD03", keysym: "e", label: "E" },
  { code: "AD04", keysym: "r", label: "R" },
  { code: "AD05", keysym: "t", label: "T" },
  { code: "AD06", keysym: "y", label: "Y" },
  { code: "AD07", keysym: "u", label: "U" },
  { code: "AD08", keysym: "i", label: "I" },
  { code: "AD09", keysym: "o", label: "O" },
  { code: "AD10", keysym: "p", label: "P" },
  { code: "AC01", keysym: "a", label: "A" },
  { code: "AC02", keysym: "s", label: "S" },
  { code: "AC03", keysym: "d", label: "D" },
  { code: "AC04", keysym: "f", label: "F" },
  { code: "AC05", keysym: "g", label: "G" },
  { code: "AC06", keysym: "h", label: "H" },
  { code: "AC07", keysym: "j", label: "J" },
  { code: "AC08", keysym: "k", label: "K" },
  { code: "AC09", keysym: "l", label: "L" },
  { code: "AB01", keysym: "z", label: "Z" },
  { code: "AB02", keysym: "x", label: "X" },
  { code: "AB03", keysym: "c", label: "C" },
  { code: "AB04", keysym: "v", label: "V" },
  { code: "AB05", keysym: "b", label: "B" },
  { code: "AB06", keysym: "n", label: "N" },
  { code: "AB07", keysym: "m", label: "M" },
  { code: "AE01", keysym: "1", label: "1" },
  { code: "AE02", keysym: "2", label: "2" },
  { code: "AE03", keysym: "3", label: "3" },
  { code: "AE04", keysym: "4", label: "4" },
  { code: "AE05", keysym: "5", label: "5" },
  { code: "AE06", keysym: "6", label: "6" },
  { code: "AE07", keysym: "7", label: "7" },
  { code: "AE08", keysym: "8", label: "8" },
  { code: "AE09", keysym: "9", label: "9" },
  { code: "AE10", keysym: "0", label: "0" },
  { code: "FK01", keysym: "F1", label: "F1" },
  { code: "FK02", keysym: "F2", label: "F2" },
  { code: "FK03", keysym: "F3", label: "F3" },
  { code: "FK04", keysym: "F4", label: "F4" },
  { code: "FK05", keysym: "F5", label: "F5" },
  { code: "FK06", keysym: "F6", label: "F6" },
  { code: "FK07", keysym: "F7", label: "F7" },
  { code: "FK08", keysym: "F8", label: "F8" },
  { code: "FK09", keysym: "F9", label: "F9" },
  { code: "FK10", keysym: "F10", label: "F10" },
  { code: "FK11", keysym: "F11", label: "F11" },
  { code: "FK12", keysym: "F12", label: "F12" },
  { code: "LCTL", keysym: "Control_L", label: "Left Ctrl" },
  { code: "RCTL", keysym: "Control_R", label: "Right Ctrl" },
  { code: "LALT", keysym: "Alt_L", label: "Left Alt" },
  { code: "RALT", keysym: "Alt_R", label: "Right Alt" },
  { code: "LFSH", keysym: "Shift_L", label: "Left Shift" },
  { code: "RTSH", keysym: "Shift_R", label: "Right Shift" },
  { code: "LWIN", keysym: "Super_L", label: "Left Super" },
  { code: "RWIN", keysym: "Super_R", label: "Right Super" },
  { code: "CAPS", keysym: "Caps_Lock", label: "Caps Lock" },
  { code: "ESC", keysym: "Escape", label: "Escape" },
  { code: "TAB", keysym: "Tab", label: "Tab" },
  { code: "RTRN", keysym: "Return", label: "Enter" },
  { code: "BKSP", keysym: "BackSpace", label: "Backspace" },
  { code: "SPCE", keysym: "space", label: "Space" },
  { code: "COMP", keysym: "Menu", label: "Menu" },
  { code: "HOME", keysym: "Home", label: "Home" },
  { code: "END", keysym: "End", label: "End" },
  { code: "PGUP", keysym: "Prior", label: "Page Up" },
  { code: "PGDN", keysym: "Next", label: "Page Down" },
  { code: "UP", keysym: "Up", label: "Up" },
  { code: "DOWN", keysym: "Down", label: "Down" },
  { code: "LEFT", keysym: "Left", label: "Left" },
  { code: "RGHT", keysym: "Right", label: "Right" },
  { code: "INS", keysym: "Insert", label: "Insert" },
  { code: "DELE", keysym: "Delete", label: "Delete" }
]

function keyByCode(code) {
  for (var i = 0; i < KEY_TABLE.length; i++) {
    if (KEY_TABLE[i].code === code) return KEY_TABLE[i]
  }
  return null
}

function keyLabel(code) {
  var entry = keyByCode(code)
  return entry ? entry.label : code
}

var POPULAR_KEY_CODES = [
  "CAPS", "ESC", "TAB", "BKSP", "LCTL", "RCTL", "LALT", "RALT", "LWIN", "RWIN"
]

function filterKeys(query, excludeCodes) {
  var needle = clean(query).toLowerCase()
  var exclude = excludeCodes || []
  var filtered = KEY_TABLE.filter(function(row) {
    if (exclude.indexOf(row.code) !== -1) return false
    if (needle === "") return POPULAR_KEY_CODES.indexOf(row.code) !== -1
    return row.label.toLowerCase().indexOf(needle) !== -1
      || row.code.toLowerCase().indexOf(needle) !== -1
  })
  return filtered.slice(0, 80)
}

function isLetterKeysym(keysym) {
  return /^[a-z]$/.test(keysym)
}

// pairs: {from, to}[] of KEY_TABLE codes/keysyms. Every token comes from the
// curated KEY_TABLE, never free text, so this has no injection surface.
function remapPairsToSymbolsBody(pairs) {
  var lines = []
  for (var i = 0; i < pairs.length; i++) {
    var from = clean(pairs[i].from)
    var to = clean(pairs[i].to)
    if (!from || !to) continue
    var symbols = isLetterKeysym(to) ? (to + ", " + to.toUpperCase()) : to
    lines.push("  key <" + from + "> { [ " + symbols + " ] };")
  }
  return lines.join("\n")
}

// Inverse of remapPairsToSymbolsBody. Only needs to round-trip that
// function's own output format, since this plugin owns the whole file.
function parseSymbolsBody(text) {
  var pairs = []
  var re = /key\s*<(\w+)>\s*\{\s*\[\s*([A-Za-z_][A-Za-z0-9_]*)/g
  var match
  while ((match = re.exec(String(text || ""))) !== null) {
    pairs.push({ from: match[1], to: match[2] })
  }
  return pairs
}

if (typeof module !== "undefined") {
  module.exports = {
    clean: clean,
    splitList: splitList,
    optionString: optionString,
    entryKey: entryKey,
    baseLayoutCode: baseLayoutCode,
    layoutEntries: layoutEntries,
    augmentLayouts: augmentLayouts,
    serializeEntries: serializeEntries,
    parseXkb: parseXkb,
    isConfigured: isConfigured,
    matchScore: matchScore,
    filterAvailable: filterAvailable,
    labelFor: labelFor,
    KEY_TABLE: KEY_TABLE,
    keyByCode: keyByCode,
    keyLabel: keyLabel,
    filterKeys: filterKeys,
    remapPairsToSymbolsBody: remapPairsToSymbolsBody,
    parseSymbolsBody: parseSymbolsBody
  }
}
