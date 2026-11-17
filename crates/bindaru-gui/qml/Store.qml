// The window's state and every call to bindaru. `backend` offers run/stream (see Backend in
// src/backend.rs; FakeBackend in tests) and answers by signals, like uQ's ctx.command.
import QtQuick
import "logic.js" as Logic

QtObject {
    id: store

    property var backend
    property string page: "software"
    property var config: Logic.defaults()
    property string configProblem: ""
    property var installed: ({ packages: [], problem: "" })
    property var found: null
    property string query: ""
    /// What the Software page shows: "installed" is your own software; "all", "repos" and "aur"
    /// browse the catalogue, so they list search results only.
    property string filter: "installed"
    readonly property bool browsing: filter !== "installed"
    property var icons: ({})
    property var peeked: null
    property string selected: ""
    property var details: null
    property var review: null
    property var plan: null
    property var progress: null
    property bool busy: false
    property string note: ""
    property bool noteFailed: false
    property var repos: ({ repos: [], problem: "" })
    property var _calls: ({})
    property int _next: 1

    readonly property bool searching: found !== null && query.trim() !== ""
    readonly property var shown: {
        const cfg = Object.assign({}, config, { start_filter_active: filter });
        if (!browsing)
            return Logic.viewOf(installed.packages, cfg, query);
        return Logic.viewOf(searching ? Logic.markInstalled(found.packages, installed.packages) : [], cfg, "");
    }
    readonly property var installedNames: {
        const have = {};
        installed.packages.forEach(p => { have[p.name] = true; });
        return have;
    }
    readonly property var selectedPackage: {
        for (const p of shown)
            if (p.name === selected)
                return p;
        return peeked !== null && peeked.name === selected ? peeked : null;
    }

    /// The icon to try for a package (a theme icon name or a file URL); "" when there is none.
    function iconFor(name) {
        return Logic.iconSource(icons, name);
    }

    /// Open a page of the sidebar. On Software, `scope` is "installed", "all", "repos" or "aur";
    /// browsing with a search already typed runs it again for the new scope.
    function go(page, scope) {
        store.page = page;
        if (page !== "software")
            return;
        const before = store.browsing;
        store.filter = scope;
        if (store.browsing && !before && store.found === null && store.query.trim().length >= 2)
            store.search(store.query);
    }

    function _id() {
        return "r" + (store._next++);
    }

    /// Runs bindaru with `argv` and calls cb({output, error, cancelled}) with its JSON (or text).
    function run(argv, cb) {
        const id = _id();
        store._calls[id] = { cb: cb, lines: [] };
        store.backend.run(id, JSON.stringify(argv));
    }

    function stream(argv, onEvent, cb) {
        const id = _id();
        store._calls[id] = { cb: cb, onEvent: onEvent, lines: [] };
        store.backend.stream(id, JSON.stringify(argv));
    }

    property Connections _conn: Connections {
        target: store.backend

        function onDone(id, code, out, err) {
            const call = store._calls[id];
            if (!call)
                return;
            delete store._calls[id];
            let result;
            if (code !== 0) {
                result = { error: (err || out || "bindaru failed").trim(), code: code };
            } else {
                try {
                    result = { output: JSON.parse(out) };
                } catch (e) {
                    result = { output: out };
                }
            }
            call.cb(result);
        }

        function onLine(id, text) {
            const call = store._calls[id];
            if (call && call.onEvent) {
                try {
                    call.onEvent(JSON.parse(text));
                } catch (e) {
                    call.onEvent({ event: "step", id: "", state: "output", detail: text });
                }
            }
        }
    }

    function say(text, failed) {
        store.note = text;
        store.noteFailed = failed === true;
    }

    function load() {
        run(["config", "show", "--json"], r => {
            const v = Logic.configView(r);
            store.config = v.config;
            store.configProblem = v.problem;
            store.filter = v.config.start_filter === "repos" || v.config.start_filter === "aur" ? v.config.start_filter : "installed";
        });
        reloadInstalled();
        run(["icons", "--json"], r => { store.icons = Logic.iconsView(r); });
        run(["repos", "list", "--json"], r => { store.repos = Logic.reposView(r); });
    }

    /// System upgrades are bindleUP's job: this opens its window.
    function openBindleUp() {
        store.backend.openBindleup();
    }

    function reloadInstalled() {
        run(["installed", "--json"], r => {
            const v = Logic.packagesView(r);
            if (v !== null)
                store.installed = v;
        });
    }

    function search(text) {
        store.query = text;
        const q = text.trim();
        // Your own software is filtered on the spot; only browsing asks the repositories and the AUR.
        if (q.length < 2 || !store.browsing) {
            store.found = null;
            return;
        }
        run(["search", "--json", q], r => {
            if (store.query.trim() !== q)
                return;
            const v = Logic.packagesView(r);
            if (v === null)
                return;
            store.found = v;
            if (v.problem !== "")
                say(v.problem, true);
            // Thumbnails for what was found that isn't already known.
            const unknown = v.packages.map(p => p.name).filter(n => icons[n] === undefined && Logic.validName(n)).slice(0, 60);
            if (unknown.length > 0)
                run(["icons", "--json"].concat(unknown), ir => { store.icons = Object.assign({}, store.icons, Logic.iconsView(ir)); });
        });
    }

    function select(name) {
        if (store.peeked !== null && store.peeked.name !== name)
            store.peeked = null;
        store.selected = name;
        store.note = "";
        store.details = null;
        store.review = null;
        store.plan = null;
        if (name === "")
            return;
        const base = store.selectedPackage;
        run(["info", "--json", name], r => {
            if (store.selected === name && base)
                store.details = Logic.detailsView(r, base);
        });
    }

    /// Show a package from a dependency list, which may not be in the list on screen. Names that
    /// aren't a package of their own (a library or "sh", provided by something else) stay put.
    function openDependency(name) {
        const known = store.shown.some(p => p.name === name);
        if (known) {
            select(name);
            return;
        }
        run(["info", "--json", name], r => {
            if (!r.output || !r.output.package) {
                say(name + " is provided by another package, so it has no page of its own.", false);
                return;
            }
            store.peeked = Logic.packageOf(r.output.package, store.installedNames[name] === true);
            store.selected = name;
            store.review = null;
            store.plan = null;
            store.note = "";
            store.details = Logic.detailsView(r, store.peeked);
        });
    }

    function setConfig(key, value) {
        run(["config", "set", "--json", key, Logic.configArg(value)], r => {
            if (r.error !== undefined) {
                say(r.error, true);
                return;
            }
            const next = Object.assign({}, store.config);
            next[key] = value;
            store.config = next;
        });
    }

    /// Show what an install or removal would do before asking to confirm it.
    function ask(action, pkg) {
        store.review = null;
        run([action, "--dry-run", "--json", pkg.name], r => {
            if (r.error !== undefined) {
                say(r.error, true);
                return;
            }
            store.plan = { action: action, name: pkg.name, doc: r.output };
            if (action === "remove" && !store.config.confirm_removals)
                confirmPlan();
        });
    }

    function confirmPlan() {
        const p = store.plan;
        store.plan = null;
        if (!p)
            return;
        runStream([p.action, "--ndjson", p.name], p.name);
    }

    function runStream(argv, subject) {
        store.busy = true;
        store.progress = Logic.startProgress();
        store.note = "";
        stream(argv, ev => { store.progress = Logic.reduce(store.progress, ev); }, r => {
            store.busy = false;
            store.progress = null;
            if (r.error !== undefined)
                say(r.error, true);
            else
                say("Done: " + subject, false);
            reloadInstalled();
            run(["repos", "list", "--json"], rr => { store.repos = Logic.reposView(rr); });
        });
    }

    function reviewAur(pkg) {
        store.plan = null;
        store.busy = true;
        run(["review", "--json", "--aur", pkg.name], r => {
            store.busy = false;
            const v = Logic.reviewView(r, pkg.name);
            if (v !== null)
                store.review = v;
        });
    }

    function acceptReview() {
        const r = store.review;
        store.review = null;
        if (r && r.hash !== "")
            runStream(["install", "--aur", "--ndjson", "--ack", r.hash, r.name], r.name);
    }

    function addRepo(name, server, key) {
        const argv = ["repos", "add", name, server, "--ndjson"];
        if (key !== "")
            argv.push("--key", key);
        runStream(argv, name);
    }

    function removeRepo(name) {
        runStream(["repos", "remove", name, "--ndjson"], name);
    }

    function setOfficial(name, on) {
        runStream(["repos", "official", name, on ? "on" : "off", "--ndjson"], name);
    }

    function scan(args, subject) {
        runStream(["scan", "--ndjson"].concat(args), subject);
    }
}
