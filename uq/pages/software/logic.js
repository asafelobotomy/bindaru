.pragma library
// The Software page's pure logic: no Qt calls, so Node can test it (tests/uq/logic.test.mjs).
// Everything `bindaru` prints is untrusted: it is read defensively, lists are capped and strings
// cut. The words are the ones bindaru's own window uses.

var NAME = "^[a-z0-9@._+][a-z0-9@._+-]{0,254}$";
var LIMIT = 300;
var TEXT = 400;

/// The argument patterns of page.toml's [[command]] tables (tests check they are the same).
var PATTERNS = {
    "search": { "query": "^[A-Za-z0-9][A-Za-z0-9._+@ -]{1,63}$" },
    "review-aur": { "package": NAME },
    "preview-install": { "package": NAME },
    "preview-remove": { "package": NAME },
    "install": { "package": NAME },
    "install-aur": { "hash": "^[0-9a-f]{64}$", "package": NAME },
    "remove": { "package": NAME },
    "config-set": { "key": "^(aur_enabled|aur_update_diff|aur_show_risky)$", "value": "^(true|false)$" }
};

function cut(text, limit) {
    const s = String(text);
    return s.length > limit ? s.slice(0, limit - 1) + "…" : s;
}

function plural(n, one, many) {
    return n + " " + (n === 1 ? one : many);
}

function isCancelled(result) {
    return !!result && result.cancelled === true;
}

function argsProblem(command, args) {
    const patterns = PATTERNS[command];
    if (!patterns)
        return "";
    const names = Object.keys(patterns);
    if (args.length !== names.length)
        return "Wrong number of arguments for " + command;
    for (let i = 0; i < names.length; i++) {
        if (!new RegExp(patterns[names[i]]).test(String(args[i])))
            return "That isn't a valid " + names[i];
    }
    return "";
}

function withNote(notes, key, note) {
    const next = Object.assign({}, notes);
    if (note === null || note === undefined)
        delete next[key];
    else
        next[key] = note;
    return next;
}

function problemOf(result, what) {
    if (!result)
        return "bindaru gave no answer";
    if (result.error !== undefined)
        return cut(result.error, TEXT);
    return what + " gave an answer bindaru's page can't read";
}

/// A package list answer (`search`, `installed`) as {packages, problem}.
function packagesView(result) {
    if (isCancelled(result))
        return null;
    if (!result || result.error !== undefined || !Array.isArray(result.output))
        return { packages: [], problem: problemOf(result, "the package list") };
    const packages = [];
    for (const p of result.output.slice(0, 500)) {
        if (!p || typeof p.name !== "string" || typeof p.version !== "string")
            continue;
        packages.push({
            name: cut(p.name, 100),
            version: cut(p.version, 60),
            repo: typeof p.repo === "string" ? cut(p.repo, 40) : "",
            aur: p.source === "aur",
            description: typeof p.description === "string" ? cut(p.description, LIMIT) : "",
            installed: p.installed === true
        });
    }
    return { packages: packages, problem: "" };
}

/// Mark which search results are installed, from the installed list's names.
function markInstalled(results, installedNames) {
    const have = {};
    installedNames.forEach(n => { have[n] = true; });
    return results.map(p => Object.assign({}, p, { installed: p.installed || have[p.name] === true }));
}

function subtitleOf(p) {
    const bits = [p.version, p.aur ? "AUR" : p.repo];
    if (p.description !== "")
        bits.push(p.description);
    return bits.join(" · ");
}

/// `review --aur --json` as {name, hash, findings, worst, problem}. A bad answer has no hash,
/// so the page cannot offer to install from it.
function reviewView(result, name) {
    const bad = msg => ({ name: name, hash: "", findings: [], worst: "", problem: msg });
    if (isCancelled(result))
        return null;
    if (!result || result.error !== undefined)
        return bad(problemOf(result, "the review"));
    const out = result.output;
    if (!out || typeof out.hash !== "string" || !/^[0-9a-f]{64}$/.test(out.hash) || !out.review)
        return bad("bindaru's review could not be read");
    const findings = Array.isArray(out.review.findings) ? out.review.findings.slice(0, 50).map(f => ({
        severity: f.severity === "danger" || f.severity === "warn" ? f.severity : "info",
        line: typeof f.line === "number" ? f.line : 0,
        text: cut(f.text || "", LIMIT),
        snippet: cut(f.snippet || "", LIMIT)
    })) : [];
    const worst = findings.some(f => f.severity === "danger") ? "danger" : findings.some(f => f.severity === "warn") ? "warn" : "";
    return { name: name, hash: out.hash, findings: findings, worst: worst, problem: "" };
}

function reviewHeadline(r) {
    if (r.worst === "danger")
        return "Read this carefully: it does things a build should not need to.";
    if (r.worst === "warn")
        return plural(r.findings.length, "thing", "things") + " worth a look before you build this.";
    return "Nothing flagged. A scan can't read for you: look at the recipe before you build it.";
}

// ---- progress

function startProgress(kind) {
    return { kind: kind, line: "", steps: [], done: false, failed: "" };
}

/// Fold one ndjson event (`{"event":"step","id","state","detail"}`) into the progress state.
function reduce(state, ev) {
    if (!ev || typeof ev !== "object" || ev.event !== "step")
        return state;
    const next = Object.assign({}, state, { steps: state.steps.slice() });
    const id = typeof ev.id === "string" ? cut(ev.id, 80) : "";
    if (ev.state === "start") {
        next.steps.push({ id: id, state: "running" });
        next.line = "";
    } else if (ev.state === "output") {
        next.line = typeof ev.detail === "string" ? cut(ev.detail, LIMIT) : "";
    } else if (ev.state === "done") {
        next.steps = next.steps.map(s => s.id === id ? { id: id, state: "done" } : s);
    }
    return next;
}

function progressLine(state) {
    if (state.failed !== "")
        return state.failed;
    if (state.done)
        return "Finished.";
    const running = state.steps.filter(s => s.state === "running").length;
    return state.line !== "" ? state.line : (running > 0 ? "Working…" : "Starting…");
}

function fraction(state, totalSteps) {
    if (state.done)
        return 1;
    if (!totalSteps)
        return -1;
    return Math.min(1, state.steps.filter(s => s.state === "done").length / totalSteps);
}

/// Why a finished stream failed, "" when it didn't. A stream ends in `done` events for every
/// step; a refusal (bindaru's message) arrives as the result's error.
function streamProblem(state, result) {
    if (isCancelled(result))
        return "";
    if (result && result.error !== undefined)
        return cut(result.error, TEXT);
    return "";
}

// ---- settings

function configView(result) {
    const none = { aurEnabled: true, aurUpdateDiff: true, aurShowRisky: true, problem: "" };
    if (isCancelled(result))
        return null;
    if (!result || result.error !== undefined || !result.output || typeof result.output !== "object")
        return Object.assign({}, none, { problem: problemOf(result, "the settings") });
    const o = result.output;
    return {
        aurEnabled: o.aur_enabled !== false,
        aurUpdateDiff: o.aur_update_diff !== false,
        aurShowRisky: o.aur_show_risky !== false,
        problem: ""
    };
}
