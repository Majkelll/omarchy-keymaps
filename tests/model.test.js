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
assert.deepStrictEqual(Model.filterKeys("", ["CAPS"]).find(k => k.code === "CAPS"), undefined)

console.log("model tests passed")
