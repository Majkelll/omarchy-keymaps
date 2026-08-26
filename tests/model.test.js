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

console.log("model tests passed")
