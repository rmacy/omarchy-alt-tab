import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../WindowModel.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const model = {}
vm.createContext(model)
vm.runInContext(source, model, { filename: "WindowModel.js" })

test("filters to switchable windows on one monitor and orders them by MRU", () => {
  const clients = [
    { address: "0x3", monitor: 1, mapped: true, acceptsInput: true, focusHistoryID: 3 },
    { address: "0x1", monitor: 1, mapped: true, acceptsInput: true, focusHistoryID: 0 },
    { address: "0x2", monitor: 2, mapped: true, acceptsInput: true, focusHistoryID: 1 },
    { address: "0x4", monitor: 1, mapped: false, acceptsInput: true, focusHistoryID: 2 },
    { address: "0x5", monitor: 1, mapped: true, acceptsInput: false, focusHistoryID: 1 },
    { address: "0x6", monitor: 1, mapped: true, acceptsInput: true, focusHistoryID: -1 }
  ]

  const result = model.switchableClients(clients, 1)
  assert.deepEqual(Array.from(result, client => client.address), ["0x1", "0x3", "0x6"])
})

test("restricts cycling to the active workspace on the focused monitor", () => {
  const clients = [
    { address: "0x1", monitor: 1, workspace: { id: 3 }, mapped: true, acceptsInput: true, focusHistoryID: 1 },
    { address: "0x2", monitor: 1, workspace: { id: 5 }, mapped: true, acceptsInput: true, focusHistoryID: 0 },
    { address: "0x3", monitor: 2, workspace: { id: 3 }, mapped: true, acceptsInput: true, focusHistoryID: 2 },
    { address: "0x4", monitor: 1, workspace: { id: -99 }, mapped: true, acceptsInput: true, focusHistoryID: 3 }
  ]

  const scoped = model.switchableClients(clients, 1, 3)
  assert.deepEqual(Array.from(scoped, client => client.address), ["0x1"])
  const special = model.switchableClients(clients, 1, -99)
  assert.deepEqual(Array.from(special, client => client.address), ["0x4"])
  const unscoped = model.switchableClients(clients, 1)
  assert.deepEqual(Array.from(unscoped, client => client.address), ["0x2", "0x1", "0x4"])
})

test("starts on the next MRU window and wraps in both directions", () => {
  assert.equal(model.initialIndex(1, 4), 1)
  assert.equal(model.initialIndex(-1, 4), 3)
  assert.equal(model.initialIndex(1, 1), 0)
  assert.equal(model.initialIndex(1, 0), -1)
  assert.equal(model.nextIndex(3, 1, 4), 0)
  assert.equal(model.nextIndex(0, -1, 4), 3)
})

test("turns application classes into readable fallback labels", () => {
  assert.equal(model.classLabel("com.mitchellh.ghostty"), "Ghostty")
  assert.equal(model.classLabel("org.example.my_app"), "My App")
  assert.equal(model.classLabel(""), "Application")
})

test("normalizes titles without breaking short labels", () => {
  assert.equal(model.shortenedTitle("  A   useful title  ", 20), "A useful title")
  assert.equal(model.shortenedTitle("A very long window title", 10), "A very lo…")
})
