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
    property string filter: "all"
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

    readonly property var shown: {
        const searching = found !== null && query.trim() !== "";
        const source = searching ? Logic.markInstalled(found.packages, installed.packages) : installed.packages;
        const cfg = Object.assign({}, config, { start_filter_active: filter });
        return Logic.viewOf(source, cfg, searching ? "" : query);
    }
    readonly property var selectedPackage: {
        for (const p of shown)
            if (p.name === selected)
                return p;
        return null;
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
            store.filter = v.config.start_filter === "installed" || v.config.start_filter === "repos" || v.config.start_filter === "aur" ? v.config.start_filter : "all";
        });
        reloadInstalled();
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
        if (q.length < 2) {
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
        });
    }

    function select(name) {
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
