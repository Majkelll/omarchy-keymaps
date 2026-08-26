const assert = require("assert")
const Model = require("../Model.js")

const xkb = [
  "layouts:",
  "- layout: 'pl'",
  "  variant: ''",
  "  description: Polish",
  "- layout: 'pl'",
  "  variant: 'dvorak'",
  "  description: Polish (Dvorak)",
  "- layout: 'pl'",
  "  variant: 'dvorak'",
  "  description: Polish (Dvorak duplicate)",
  "- layout: 'us'",
  "  variant: ''",
  "  description: English (US)",
  "- layout: 'us'",
  "  variant: 'intl'",
  "  description: English (US, intl.)",
  "- layout: 'us'",
  "  variant: 'dvorak'",
  "  description: English (US, Dvorak)"
].join("\n")

const rows = Model.parseXkb(xkb)
assert.deepStrictEqual(rows.map(Model.entryKey), ["us|dvorak", "us|intl", "us|", "pl|", "pl|dvorak"])
const polish = rows.find(row => row.layout === "pl" && row.variant === "")
assert.strictEqual(Model.labelFor(polish), "PL")

const configured = Model.layoutEntries("pl,us", ",intl")
assert.deepStrictEqual(Model.serializeEntries(configured), {
  layouts: "pl,us",
  variants: ",intl"
})

const available = Model.filterAvailable(rows, configured, "Polish (Dvorak)")
assert.deepStrictEqual(available.map(Model.entryKey), ["pl|dvorak"])
assert.deepStrictEqual(Model.filterAvailable(rows, configured, "Polish (Dvorak)").map(Model.entryKey), ["pl|dvorak"])

const searchResults = Model.filterAvailable(rows, [polish], "US")
assert.deepStrictEqual(searchResults.map(Model.entryKey), ["us|", "us|dvorak", "us|intl"])

assert.strictEqual(Model.optionString('{"option":"input:kb_layout","str":"pl,us"}'), "pl,us")
assert.strictEqual(Model.optionString("not json"), "")

// baseLayoutCode / augmentLayouts
assert.strictEqual(Model.baseLayoutCode("pl+omarchy-keymaps(remap)"), "pl")
assert.strictEqual(Model.baseLayoutCode("pl"), "pl")
assert.strictEqual(Model.augmentLayouts("pl,us", false), "pl,us")
assert.strictEqual(Model.augmentLayouts("pl,us", true), "pl+omarchy-keymaps(remap):1,us+omarchy-keymaps(remap):2")
assert.strictEqual(Model.augmentLayouts("pl+omarchy-keymaps(remap):1,us", true), "pl+omarchy-keymaps(remap):1,us+omarchy-keymaps(remap):2")

// layoutEntries strips an already-augmented kb_layout token before display/matching
assert.deepStrictEqual(Model.layoutEntries("pl+omarchy-keymaps(remap):1,us+omarchy-keymaps(remap):2", ",").map(e => e.layout), ["pl", "us"])

// remapPairsToSymbolsBody / parseSymbolsBody
const pairs = [{ from: "CAPS", to: "Escape" }, { from: "ESC", to: "Caps_Lock" }]
const body = Model.remapPairsToSymbolsBody(pairs)
assert.strictEqual(body, "  key <CAPS> { [ Escape ] };\n  key <ESC> { [ Caps_Lock ] };")
assert.deepStrictEqual(Model.parseSymbolsBody(body), pairs)
assert.deepStrictEqual(Model.parseSymbolsBody(""), [])

// a letter target keeps both keyboard levels (unshifted/shifted) but still round-trips
const letterBody = Model.remapPairsToSymbolsBody([{ from: "CAPS", to: "q" }])
assert.strictEqual(letterBody, "  key <CAPS> { [ q, Q ] };")
assert.deepStrictEqual(Model.parseSymbolsBody(letterBody), [{ from: "CAPS", to: "q" }])

// KEY_TABLE / filterKeys
assert.deepStrictEqual(Model.filterKeys("esc", []).map(k => k.code), ["ESC"])
assert.strictEqual(Model.keyLabel("CAPS"), "Caps Lock")
assert.strictEqual(Model.keysymLabel("Caps_Lock"), "Caps Lock")
assert.strictEqual(Model.keysymLabel("Escape"), "Escape")
assert.strictEqual(Model.keysymLabel("NoSuchSym"), "NoSuchSym")
assert.deepStrictEqual(Model.filterKeys("", ["CAPS"]).find(k => k.code === "CAPS"), undefined)

// keyByScan resolves the XKB keycode Qt reports, and tells left/right apart
assert.strictEqual(Model.keyByScan(66).code, "CAPS")
assert.strictEqual(Model.keyByScan(9).code, "ESC")
assert.strictEqual(Model.keyByScan(37).code, "LCTL")
assert.strictEqual(Model.keyByScan(105).code, "RCTL")
assert.strictEqual(Model.keyByScan(99999), null)

// groupRemapPairs: a matched forward+reverse pair collapses into one row
const swap = [{ from: "CAPS", to: "Escape" }, { from: "ESC", to: "Caps_Lock" }]
assert.deepStrictEqual(Model.groupRemapPairs(swap), [
  { from: "CAPS", to: "Escape", both: true, codes: ["CAPS", "ESC"] }
])

// one-way pairs stay separate rows
const oneWay = [{ from: "CAPS", to: "Escape" }, { from: "LCTL", to: "BackSpace" }]
assert.deepStrictEqual(Model.groupRemapPairs(oneWay), [
  { from: "CAPS", to: "Escape", both: false, codes: ["CAPS"] },
  { from: "LCTL", to: "BackSpace", both: false, codes: ["LCTL"] }
])

// a swap plus an unrelated one-way pair: grouped and ungrouped coexist
assert.deepStrictEqual(Model.groupRemapPairs(swap.concat([{ from: "LCTL", to: "BackSpace" }])), [
  { from: "CAPS", to: "Escape", both: true, codes: ["CAPS", "ESC"] },
  { from: "LCTL", to: "BackSpace", both: false, codes: ["LCTL"] }
])

// a key mapped to itself is not a swap
assert.deepStrictEqual(Model.groupRemapPairs([{ from: "ESC", to: "Escape" }]), [
  { from: "ESC", to: "Escape", both: false, codes: ["ESC"] }
])
assert.deepStrictEqual(Model.groupRemapPairs([]), [])

console.log("model tests passed")
