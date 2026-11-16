// Tests for the Software page (uq/pages/software/): logic.js and the manifest.
//   node --test 'tests/uq/*.test.mjs'
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { loadLogic } from "./load-logic.mjs";
import { parseToml } from "./toml-lite.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const pageDir = join(here, "..", "..", "uq", "pages", "software");
const L = loadLogic(join(pageDir, "logic.js"));
const manifest = parseToml(readFileSync(join(pageDir, "page.toml"), "utf8"));
const read = (f) => readFileSync(join(pageDir, f), "utf8");
const qml = readdirSync(pageDir).filter((f) => f.endsWith(".qml")).map(read).join("\n") + read("logic.js");

test("the page is uq_api 3, never forces anything and every command is used", () => {
  assert.equal(manifest.uq_api, 3);
  assert.equal(manifest.id, "software");
  const previews = new Set(manifest.command.map((c) => c.preview).filter(Boolean));
  for (const c of manifest.command) {
    if (!previews.has(c.id)) assert.ok(qml.includes(`"${c.id}"`), `command ${c.id} is never used`);
    for (const flag of ["--force", "--yes", "--noconfirm", "--overwrite", "--skipreview"]) assert.ok(!c.argv.includes(flag), `${c.id} passes ${flag}`);
  }
});

test("only AUR installs carry an acknowledgement, and it is a hash", () => {
  for (const c of manifest.command) assert.equal(c.argv.includes("--ack"), c.id === "install-aur");
  assert.equal(L.argsProblem("install-aur", ["a".repeat(64), "paru-bin"]), "");
  assert.notEqual(L.argsProblem("install-aur", ["yes", "paru-bin"]), "");
});

test("argument patterns are the same in logic.js and page.toml", () => {
  for (const c of manifest.command) {
    for (const a of c.args ?? []) assert.equal(a.pattern, L.PATTERNS[c.id]?.[a.name], `${c.id}.${a.name}`);
    assert.equal((c.args ?? []).length, Object.keys(L.PATTERNS[c.id] ?? {}).length, `${c.id}: argument count`);
  }
});

test("hostile package names are refused", () => {
  for (const bad of ["-rf", "--overwrite=*", "a b", "A", "", "../x", "$(id)", "a\nb"]) assert.notEqual(L.argsProblem("install", [bad]), "", bad);
  assert.equal(L.argsProblem("install", ["lib32-glibc"]), "");
});

test("package lists are read defensively", () => {
  const v = L.packagesView({ output: [{ name: "htop", version: "3.4", repo: "extra", source: "repo", description: "x", installed: true }, { name: 5 }, null, { name: "p", version: "1", source: "aur" }] });
  assert.equal(v.packages.length, 2);
  assert.equal(v.packages[1].aur, true);
  assert.notEqual(L.packagesView({ error: "boom" }).problem, "");
  assert.equal(L.packagesView({ cancelled: true, error: "Cancelled" }), null);
  assert.deepEqual(L.markInstalled([{ name: "a", installed: false }], ["a"])[0].installed, true);
});

test("a review without a valid hash cannot be accepted", () => {
  const f = [{ severity: "danger", line: 3, text: "sudo", snippet: "sudo make" }];
  const ok = L.reviewView({ output: { hash: "a".repeat(64), review: { findings: f } } }, "x");
  assert.equal(ok.worst, "danger");
  assert.equal(ok.hash, "a".repeat(64));
  for (const out of [{ review: { findings: [] } }, { hash: "nothex", review: {} }, null]) {
    assert.equal(L.reviewView({ output: out }, "x").hash, "");
  }
  assert.notEqual(L.reviewView({ error: "could not download" }, "x").problem, "");
});

test("progress follows step events", () => {
  let s = L.startProgress("install");
  s = L.reduce(s, { event: "step", id: "fetch-x", state: "start" });
  s = L.reduce(s, { event: "step", id: "fetch-x", state: "output", detail: "Cloning" });
  assert.equal(L.progressLine(s), "Cloning");
  s = L.reduce(s, { event: "step", id: "fetch-x", state: "done" });
  assert.equal(s.steps[0].state, "done");
  assert.equal(L.reduce(s, "junk"), s);
});
