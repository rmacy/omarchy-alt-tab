import assert from "node:assert/strict"
import { existsSync, readFileSync } from "node:fs"
import { test } from "node:test"

const root = new URL("../", import.meta.url)
const manifest = JSON.parse(readFileSync(new URL("manifest.json", root), "utf8"))

test("manifest publishes the scoped v1.4.1 service and overlay", () => {
  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "bitr0t.window-switcher")
  assert.equal(manifest.version, "1.4.1")
  assert.deepEqual(manifest.kinds, ["overlay", "service"])
  assert.equal(manifest.keepLoaded, true)
  assert.match(manifest.description, /active workspace/i)
  assert.match(manifest.description, /focused monitor/i)
  for (const entryPoint of Object.values(manifest.entryPoints)) {
    assert.ok(!entryPoint.startsWith("/") && !entryPoint.includes(".."))
    assert.ok(existsSync(new URL(entryPoint, root)), `missing entry point ${entryPoint}`)
  }
})

test("marketplace review artifacts are committed at root", () => {
  for (const file of ["README.md", "LICENSE", "preview.png"]) {
    assert.ok(existsSync(new URL(file, root)), `missing ${file}`)
  }
  assert.match(readFileSync(new URL("LICENSE", root), "utf8"), /^MIT License/)
  assert.match(readFileSync(new URL("README.md", root), "utf8"), /Capability disclosure/)
})
