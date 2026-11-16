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

test("settings are read with defaults and out-of-range words ignored", () => {
  const v = L.configView({ output: { view: "grid", sort: "bogus", sort_descending: true, scan_installs: "all", aur_enabled: "yes" } });
  assert.equal(v.values.view, "grid");
  assert.equal(v.values.sort, "name");
  assert.equal(v.values.sort_descending, true);
  assert.equal(v.values.scan_installs, "all");
  assert.equal(v.values.aur_enabled, true);
  assert.equal(v.problem, "");
  assert.notEqual(L.configView({ error: "boom" }).problem, "");
  assert.equal(L.configView({ cancelled: true, error: "Cancelled" }), null);
});

test("config-set takes every setting and only plain words", () => {
  for (const k of ["view", "sort", "group_by", "density", "search_in", "start_filter", "scan_installs", "sort_descending", "confirm_removals"]) assert.equal(L.argsProblem("config-set", [k, "off"]), "", k);
  for (const bad of [["--json", "true"], ["view", "grid; rm"], ["view", "x".repeat(21)], ["scan_installs", "A"]]) assert.notEqual(L.argsProblem("config-set", bad), "", bad.join(" "));
});

test("repositories are read defensively and only the right ones can be changed", () => {
  const v = L.reposView({ output: [
    { name: "core", enabled: true, origin: "official", servers: [] },
    { name: "multilib", enabled: false, origin: "official", servers: [] },
    { name: "mine", enabled: true, origin: "added", servers: ["https://example.org/$arch"] },
    { name: "Weird Name", enabled: true, origin: "other" },
    { name: "chaotic-aur", enabled: true, origin: "other" },
    null
  ] });
  assert.deepEqual(v.repos.map((r) => r.name), ["core", "multilib", "mine", "chaotic-aur"]);
  assert.deepEqual(v.repos.map((r) => r.switchable), [false, true, false, false]);
  assert.deepEqual(v.repos.map((r) => r.removable), [false, false, true, false]);
  assert.notEqual(L.reposView({ error: "no" }).problem, "");
});

test("repository arguments refuse anything but a plain name, an HTTPS server and a full key", () => {
  assert.equal(L.argsProblem("repo-add", ["my-repo", "https://example.org/$repo/os/$arch"]), "");
  assert.notEqual(L.argsProblem("repo-add", ["my-repo", "http://example.org/x"]), "");
  assert.notEqual(L.argsProblem("repo-add", ["--x", "https://example.org/x"]), "");
  assert.notEqual(L.argsProblem("repo-add", ["my-repo", "https://a b"]), "");
  assert.equal(L.argsProblem("repo-add-key", ["A".repeat(40), "my-repo", "https://example.org/x"]), "");
  assert.notEqual(L.argsProblem("repo-add-key", ["A".repeat(39), "my-repo", "https://example.org/x"]), "");
  assert.equal(L.argsProblem("repo-official", ["multilib", "on"]), "");
  assert.notEqual(L.argsProblem("repo-official", ["multilib", "yes"]), "");
});

test("every repository and scan change is confirmed with a preview", () => {
  for (const id of ["repo-add", "repo-add-key", "repo-remove", "repo-official", "scan-aur", "scan-all"]) {
    const c = manifest.command.find((x) => x.id === id);
    assert.ok(c.confirm && c.preview, `${id} needs confirm and preview`);
    const p = manifest.command.find((x) => x.id === c.preview);
    assert.ok(p.argv.includes("--dry-run"), `${c.preview} must not change anything`);
  }
});
