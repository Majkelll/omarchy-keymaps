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

function layoutEntries(layoutRaw, variantRaw) {
  var layouts = splitList(layoutRaw)
  var variants = splitList(variantRaw)
  var entries = []

  for (var i = 0; i < layouts.length; i++) {
    entries.push({
      layout: layouts[i],
      variant: variants[i] || "",
      description: layouts[i].toUpperCase() + (variants[i] ? " · " + variants[i] : "")
    })
  }

  return entries
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
        + (current.variant ? " · " + current.variant : "")
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

function filterAvailable(rows, configured, query) {
  var needle = clean(query).toLowerCase()
  var filtered = rows.filter(function(row) {
    if (isConfigured(row, configured)) return false
    if (needle === "") return POPULAR_KEYS.indexOf(entryKey(row)) !== -1

    return String(row.layout).toLowerCase().indexOf(needle) !== -1
      || String(row.variant).toLowerCase().indexOf(needle) !== -1
      || String(row.description).toLowerCase().indexOf(needle) !== -1
  })

  return filtered.slice(0, 80)
}

function labelFor(entry) {
  return clean(entry.layout).toUpperCase()
}

function variantLabel(entry) {
  return clean(entry.variant) === "" ? "Default" : clean(entry.variant)
}

if (typeof module !== "undefined") {
  module.exports = {
    clean: clean,
    splitList: splitList,
    optionString: optionString,
    entryKey: entryKey,
    layoutEntries: layoutEntries,
    serializeEntries: serializeEntries,
    parseXkb: parseXkb,
    isConfigured: isConfigured,
    filterAvailable: filterAvailable,
    labelFor: labelFor,
    variantLabel: variantLabel
  }
}
