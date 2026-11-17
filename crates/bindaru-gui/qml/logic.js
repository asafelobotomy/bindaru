.pragma library
// The window's pure logic: no Qt calls, so Node tests it (tests/gui/logic.test.mjs).
// Everything `bindaru` prints is untrusted: read defensively, lists capped, strings cut.

var LIMIT = 300;

function cut(text, limit) {
    const s = String(text === undefined || text === null ? "" : text);
    return s.length > limit ? s.slice(0, limit - 1) + "…" : s;
}

function plural(n, one, many) {
    return n + " " + (n === 1 ? one : many);
}

/// "470.00 KiB" -> bytes; 0 when unknown.
function parseSize(text) {
    const m = /^([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB)$/.exec(String(text || "").trim());
    if (!m)
        return 0;
    const unit = { "B": 1, "KiB": 1024, "MiB": 1048576, "GiB": 1073741824, "TiB": 1099511627776 }[m[2]];
    return Math.round(parseFloat(m[1]) * unit);
}

function sizeText(bytes) {
    if (!bytes)
        return "";
    const units = ["B", "KB", "MB", "GB"];
    let v = bytes, i = 0;
    while (v >= 1000 && i < units.length - 1) {
        v /= 1000;
        i++;
    }
    return (i === 0 ? v : v.toFixed(v < 10 ? 1 : 0)) + " " + units[i];
}

/// A package list answer (`search`, `installed`) as {packages, problem}; null when cancelled.
function packagesView(result) {
    if (!result)
        return { packages: [], problem: "bindaru gave no answer" };
    if (result.cancelled === true)
        return null;
    if (result.error !== undefined || !Array.isArray(result.output))
        return { packages: [], problem: cut(result.error !== undefined ? result.error : "the package list could not be read", 400) };
    const packages = [];
    for (const p of result.output.slice(0, 3000)) {
        if (!p || typeof p.name !== "string" || typeof p.version !== "string")
            continue;
        packages.push({
            name: cut(p.name, 100),
            version: cut(p.version, 60),
            repo: typeof p.repo === "string" ? cut(p.repo, 40) : "",
            aur: p.source === "aur",
            description: typeof p.description === "string" ? cut(p.description, LIMIT) : "",
            installed: p.installed === true,
            size: parseSize(p.installed_size),
            votes: typeof p.votes === "number" ? p.votes : 0,
            popularity: typeof p.popularity === "number" ? p.popularity : 0
        });
    }
    return { packages: packages, problem: "" };
}

/// One package as the list holds it, from a single `info` package object.
function packageOf(p, installed) {
    return {
        name: cut(p.name, 100), version: cut(p.version, 60), repo: typeof p.repo === "string" ? cut(p.repo, 40) : "",
        aur: p.source === "aur", description: typeof p.description === "string" ? cut(p.description, LIMIT) : "",
        installed: installed === true || p.installed === true, size: parseSize(p.installed_size), votes: 0, popularity: 0
    };
}

function sourceOf(p) {
    return p.aur ? "AUR" : (p.repo === "local" || p.repo === "" ? "Installed" : p.repo);
}

/// Keep what the filter and the search ask for. filter: all, installed, repos, aur.
function filterPackages(list, filter, query, searchIn) {
    const q = String(query || "").trim().toLowerCase();
    return list.filter(p => {
        if (filter === "installed" && !p.installed)
            return false;
        if (filter === "repos" && p.aur)
            return false;
        if (filter === "aur" && !p.aur)
            return false;
        if (q === "")
            return true;
        return p.name.toLowerCase().indexOf(q) >= 0 || (searchIn === "name-description" && p.description.toLowerCase().indexOf(q) >= 0);
    });
}

/// Mark which results are installed, from the installed list's names.
function markInstalled(results, installed) {
    const have = {};
    installed.forEach(p => { have[p.name] = true; });
    return results.map(p => Object.assign({}, p, { installed: p.installed || have[p.name] === true }));
}

var SORTS = ["name", "size", "version", "repo", "popularity"];

function compare(a, b, key) {
    switch (key) {
    case "size":
        return a.size - b.size;
    case "popularity":
        return (a.popularity - b.popularity) || (a.votes - b.votes);
    case "version":
        return a.version.localeCompare(b.version, undefined, { numeric: true });
    case "repo":
        return sourceOf(a).localeCompare(sourceOf(b)) || a.name.localeCompare(b.name);
    default:
        return a.name.localeCompare(b.name);
    }
}

/// A sorted copy; ties break on the name so the order is steady.
function sortPackages(list, key, descending) {
    const out = list.slice().sort((a, b) => (compare(a, b, key) || a.name.localeCompare(b.name)) * (descending ? -1 : 1));
    return out;
}

/// Adds `section` to each package for a grouped list: by repo, by source (Repositories or AUR).
function groupPackages(list, by) {
    return list.map(p => Object.assign({}, p, {
        section: by === "repo" ? sourceOf(p) : by === "source" ? (p.aur ? "AUR" : "Repositories") : ""
    }));
}

/// What the main view shows: filtered, sorted and grouped (grouping sorts by group first).
function viewOf(list, cfg, query) {
    const filtered = filterPackages(list, cfg.start_filter_active || "all", query, cfg.search_in);
    let sorted = sortPackages(filtered, cfg.sort, cfg.sort_descending);
    if (cfg.group_by !== "none") {
        const grouped = groupPackages(sorted, cfg.group_by);
        const order = {};
        grouped.forEach(p => { if (order[p.section] === undefined) order[p.section] = Object.keys(order).length; });
        sorted = grouped.slice().sort((a, b) => order[a.section] - order[b.section]);
    }
    return sorted;
}

function defaults() {
    return {
        aur_enabled: true, aur_update_diff: true, aur_show_risky: true,
        view: "list", sort: "name", sort_descending: false, group_by: "none", density: "comfortable",
        show_inspector: true, search_in: "name-description", start_filter: "all",
        confirm_removals: true, show_dependencies: false, scan_installs: "aur"
    };
}

/// `config show --json` over the defaults: unknown or ill-typed keys are ignored.
function configView(result) {
    const base = defaults();
    if (!result || result.error !== undefined || !result.output || typeof result.output !== "object")
        return { config: base, problem: result && result.error !== undefined ? cut(result.error, 300) : "" };
    const cfg = Object.assign({}, base);
    for (const k of Object.keys(base)) {
        if (typeof result.output[k] === typeof base[k])
            cfg[k] = result.output[k];
    }
    return { config: cfg, problem: "" };
}

/// `repos list --json` as {repos, problem}.
function reposView(result) {
    if (!result || result.error !== undefined || !Array.isArray(result.output))
        return { repos: [], problem: result && result.error !== undefined ? cut(result.error, 300) : "the repositories could not be read" };
    return { repos: result.output.filter(r => r && typeof r.name === "string").slice(0, 100).map(r => ({
        name: cut(r.name, 40), enabled: r.enabled === true,
        origin: r.origin === "official" || r.origin === "added" ? r.origin : "other",
        servers: Array.isArray(r.servers) ? r.servers.slice(0, 3).map(s => cut(s, 200)) : [],
        signed: !(r.sig_level && /Never|Optional/.test(r.sig_level))
    })), problem: "" };
}

var REPO_HELP = {
    official: "Part of Arch. Core and extra are always on.",
    added: "Added in bindaru: HTTPS, and packages must be signed.",
    other: "Set up by hand in pacman.conf."
};

/// A capped list of cut strings; anything that isn't a list is empty.
function strings(list, limit) {
    return Array.isArray(list) ? list.slice(0, 80).filter(x => typeof x === "string").map(x => cut(x, limit)) : [];
}

/// One dependency as pacman writes it: `name`, `name>=1.2`, or (optional) `name: why`.
/// Returns {name, constraint, reason}.
function depEntry(text) {
    const t = String(text);
    const colon = t.indexOf(": ");
    const head = colon >= 0 ? t.slice(0, colon) : t;
    const m = /^([^<>=\s]+)\s*((?:[<>]=?|=).*)?$/.exec(head.trim());
    return { name: m ? m[1] : head.trim(), constraint: m && m[2] ? m[2] : "", reason: colon >= 0 ? t.slice(colon + 2).trim() : "" };
}

/// The dependency lists of a package, ready to show: {key, title, hint, entries}, empty ones left out.
/// `have` maps names that are installed to true.
function depGroups(pkg, have) {
    const mark = e => Object.assign(e, { installed: have[e.name] === true });
    const groups = [
        { key: "needs", title: "Needs", hint: "Installed together with it", items: pkg.depends || [] },
        { key: "optional", title: "Optional", hint: "Add features; not installed unless you pick them", items: pkg.optDepends || [] },
        { key: "build", title: "To build", hint: "Only needed while building from the AUR", items: pkg.makeDepends || [] },
        { key: "needed-by", title: "Needed by", hint: "Installed software that depends on it", items: pkg.requiredBy || [] },
        { key: "optional-for", title: "Optional for", hint: "Installed software that can use it", items: pkg.optionalFor || [] }
    ];
    return groups.filter(g => g.items.length > 0).map(g => ({
        key: g.key, title: g.title, hint: g.hint,
        entries: g.items.map(depEntry).map(mark).sort((a, b) => (a.installed === b.installed ? 0 : a.installed ? 1 : -1) || a.name.localeCompare(b.name))
    }));
}

/// The icon file `bindaru icons` found for a package, as a URL; "" when there is none. Only files
/// in the system's icon folders are used.
function iconSource(icons, name) {
    const found = icons && typeof icons[name] === "string" ? icons[name] : "";
    const ok = /^\/(usr\/share|usr\/local\/share|var\/lib)\/[^\0]*\.(png|svg)$/.test(found) && found.indexOf("..") < 0;
    return ok ? "file://" + found : "";
}

/// An `icons --json` answer as a name -> string map; anything else is empty.
function iconsView(result) {
    const out = {};
    if (!result || result.error !== undefined || !result.output || typeof result.output !== "object" || Array.isArray(result.output))
        return out;
    for (const k of Object.keys(result.output).slice(0, 20000))
        if (typeof result.output[k] === "string")
            out[k] = result.output[k];
    return out;
}

/// `info --json` for the inspector.
function detailsView(result, fallback) {
    if (!result || result.error !== undefined || !result.output || !result.output.package)
        return { pkg: fallback, aur: null, problem: result && result.error !== undefined ? cut(result.error, 300) : "" };
    const p = result.output.package;
    const aur = result.output.aur && typeof result.output.aur === "object" ? {
        maintainer: typeof result.output.aur.maintainer === "string" ? cut(result.output.aur.maintainer, 60) : "",
        votes: result.output.aur.votes | 0,
        popularity: +result.output.aur.popularity || 0,
        flags: Array.isArray(result.output.aur.flags) ? result.output.aur.flags.slice(0, 10).map(f => ({ severity: f.severity === "warn" ? "warn" : "info", text: cut(f.text, 200) })) : []
    } : null;
    return {
        problem: "",
        aur: aur,
        pkg: Object.assign({}, fallback, {
            url: typeof p.url === "string" ? cut(p.url, 200) : "",
            licenses: Array.isArray(p.licenses) ? p.licenses.slice(0, 8).map(l => cut(l, 60)) : [],
            depends: strings(p.depends, 80),
            optDepends: strings(p.opt_depends, 160),
            makeDepends: strings(p.make_depends, 80),
            requiredBy: strings(p.required_by, 80),
            optionalFor: strings(p.optional_for, 80),
            provides: strings(p.provides, 80),
            conflicts: strings(p.conflicts, 80),
            downloadSize: cut(p.download_size || "", 30),
            installedSize: cut(p.installed_size || "", 30),
            description: typeof p.description === "string" && p.description !== "" ? cut(p.description, 600) : fallback.description
        })
    };
}

/// `review --aur --json` as {name, hash, findings, worst, problem}; no valid hash, no install.
function reviewView(result, name) {
    const bad = msg => ({ name: name, hash: "", findings: [], worst: "", problem: msg });
    if (!result)
        return bad("bindaru gave no answer");
    if (result.cancelled === true)
        return null;
    if (result.error !== undefined)
        return bad(cut(result.error, 400));
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

/// One ndjson progress event folded into {line, steps, scanning}.
function reduce(state, ev) {
    if (!ev || typeof ev !== "object")
        return state;
    const next = Object.assign({}, state, { steps: state.steps.slice() });
    if (ev.event === "step") {
        const id = cut(ev.id || "", 80);
        if (ev.state === "start") {
            next.steps.push({ id: id, state: "running" });
            next.line = "";
        } else if (ev.state === "output") {
            next.line = cut(ev.detail || "", LIMIT);
        } else if (ev.state === "done") {
            next.steps = next.steps.map(s => s.id === id ? { id: id, state: "done" } : s);
        }
    } else if (ev.event === "scan") {
        next.line = "oysterAV: batch " + (ev.batch | 0) + " of " + (ev.of | 0);
    }
    return next;
}

function startProgress() {
    return { line: "", steps: [] };
}

function progressLine(s) {
    return s.line !== "" ? s.line : (s.steps.length > 0 ? "Working…" : "Starting…");
}

/// Args for `config set` from a value of any type.
function configArg(value) {
    return typeof value === "boolean" ? (value ? "true" : "false") : String(value);
}

var NAME = /^[a-z0-9@._+][a-z0-9@._+-]{0,254}$/;
function validName(n) {
    return NAME.test(String(n));
}
