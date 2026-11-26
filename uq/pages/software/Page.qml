// bindaru's Software page in uQ Settings (docs/settings-pages.md in the uQ repository): find,
// install and remove software, with the AUR review shown before anything from the AUR is built.
// Everything goes through the commands declared in page.toml; logic.js words the answers.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.uq.settings
import "logic.js" as Logic

SettingsPage {
    id: page

    property var ctx
    property var theme
    property string highlight
    /// Installed packages (Logic.packagesView), null until `installed` answers.
    property var installedView: null
    /// The last search (Logic.packagesView) and what was searched.
    property var found: null
    property string searched: ""
    property var config: null
    /// The repositories (Logic.reposView), null until `repos` answers.
    property var reposInfo: null
    /// The AUR review waiting for a decision (Logic.reviewView), or null.
    property var pending: null
    property var progress: null
    property bool streaming: false
    property string workingKey: ""
    readonly property bool busy: page.streaming || page.workingKey !== ""
    property var notes: ({})
    property var openedWith: null
    property string filter: ""

    pageId: "software"

    function noteFor(key) {
        return page.notes[key] || null;
    }

    function color(name, fallback) {
        const colors = page.ctx && page.ctx.theme ? page.ctx.theme.colors : null;
        return (colors && colors[name]) || fallback;
    }

    function errorColor() {
        return page.color("error", "red");
    }

    function textColor() {
        return page.color("text", "black");
    }

    function installedNames() {
        return page.installedView ? page.installedView.packages.map(p => p.name) : [];
    }

    function search(query) {
        const q = query.trim();
        const why = Logic.argsProblem("search", [q]);
        if (!page.ctx || page.busy || why !== "") {
            page.notes = Logic.withNote(page.notes, "search", q === "" ? null : { message: why || "Busy", failed: true });
            return;
        }
        page.notes = Logic.withNote(page.notes, "search", null);
        page.workingKey = "search";
        page.ctx.command.run("search", [q], result => {
            page.workingKey = "";
            const view = Logic.packagesView(result);
            if (view === null)
                return;
            page.searched = q;
            page.found = view;
            if (view.problem !== "")
                page.notes = Logic.withNote(page.notes, "search", { message: view.problem, failed: true });
        });
    }

    function runStream(command, args, key) {
        const why = Logic.argsProblem(command, args);
        if (why !== "") {
            page.notes = Logic.withNote(page.notes, key, { message: why, failed: true });
            return;
        }
        page.notes = Logic.withNote(page.notes, key, null);
        page.progress = Logic.startProgress(command);
        page.streaming = true;
        page.ctx.command.stream(command, args, event => {
            page.progress = Logic.reduce(page.progress, event);
        }, result => {
            page.streaming = false;
            if (Logic.isCancelled(result)) {
                page.progress = null;
                return;
            }
            const problem = Logic.streamProblem(page.progress, result);
            page.progress = Object.assign({}, page.progress, { done: problem === "", failed: problem });
            if (problem !== "")
                page.notes = Logic.withNote(page.notes, key, { message: problem, failed: true });
            page.reload();
        });
    }

    /// Repo packages install behind uQ's confirmation sheet (with the preview); AUR packages go
    /// through the review card first.
    function install(pkg) {
        if (page.busy || !page.ctx)
            return;
        if (!pkg.aur) {
            page.runStream("install", [pkg.name], pkg.name);
            return;
        }
        const why = Logic.argsProblem("review-aur", [pkg.name]);
        if (why !== "") {
            page.notes = Logic.withNote(page.notes, pkg.name, { message: why, failed: true });
            return;
        }
        page.pending = null;
        page.workingKey = "review:" + pkg.name;
        page.ctx.command.run("review-aur", [pkg.name], result => {
            page.workingKey = "";
            const view = Logic.reviewView(result, pkg.name);
            if (view !== null)
                page.pending = view;
        });
    }

    function acceptReview() {
        const r = page.pending;
        page.pending = null;
        if (r && r.hash !== "")
            page.runStream("install-aur", [r.hash, r.name], r.name);
    }

    function remove(pkg) {
        if (!page.busy && page.ctx)
            page.runStream("remove", [pkg.name], pkg.name);
    }

    function setting(key) {
        return page.config !== null ? page.config.values[key] : Logic.CONFIG_DEFAULTS[key];
    }

    /// A switch gives true or false, a choice its word.
    function setConfig(key, value) {
        const text = value === true ? "true" : value === false ? "false" : String(value);
        if (page.busy || !page.ctx || Logic.argsProblem("config-set", [key, text]) !== "")
            return;
        page.workingKey = "config";
        page.ctx.command.run("config-set", [key, text], result => {
            page.workingKey = "";
            if (result && result.error !== undefined)
                page.notes = Logic.withNote(page.notes, "config", { message: Logic.cut(result.error, 300), failed: true });
        });
    }

    function switchRepo(name, on) {
        page.runStream("repo-official", [name, on ? "on" : "off"], "repos");
    }

    function removeRepo(name) {
        page.runStream("repo-remove", [name], "repos");
    }

    function addRepo(name, server, fingerprint) {
        const key = fingerprint.trim();
        if (key === "")
            page.runStream("repo-add", [name.trim(), server.trim()], "repo-add");
        else
            page.runStream("repo-add-key", [key, name.trim(), server.trim()], "repo-add");
    }

    function scan(everything) {
        page.runStream(everything ? "scan-all" : "scan-aur", [], "scan");
    }

    function reload() {
        if (page.ctx)
            page.ctx.command.run("installed", [], r => {
                const v = Logic.packagesView(r);
                if (v !== null)
                    page.installedView = v;
            });
    }

    onCtxChanged: {
        if (page.ctx && page.ctx !== page.openedWith) {
            page.openedWith = page.ctx;
            page.ctx.command.watch("installed", r => {
                const v = Logic.packagesView(r);
                if (v !== null)
                    page.installedView = v;
            });
            page.ctx.command.watch("repos", r => {
                const v = Logic.reposView(r);
                if (v !== null)
                    page.reposInfo = v;
            });
            page.ctx.command.watch("config", r => {
                const v = Logic.configView(r);
                if (v !== null)
                    page.config = v;
            });
        }
    }

    SettingsTab {
        title: "Browse"
        iconName: "system-software-install"

        SettingsCard {
            title: "Find software"
            iconName: "edit-find"
            help: "Searches the Arch repositories and, when it is on, the AUR. Software from the AUR is reviewed by you before it is built."
            wide: true
            Layout.fillWidth: true

            SettingRow {
                settingId: "browse"
                label: "What are you looking for?"
                highlight: page.highlight
                Layout.fillWidth: true

                QQC2.TextField {
                    id: query
                    objectName: "query"
                    placeholderText: "Name or description"
                    implicitWidth: 260
                    enabled: !page.busy
                    onAccepted: page.search(query.text)
                }
                QQC2.Button {
                    objectName: "search"
                    text: "Search"
                    icon.name: "edit-find"
                    enabled: !page.busy && query.text.trim().length > 1
                    onClicked: page.search(query.text)
                }
            }
            Outcome {
                host: page
                noteKey: "search"
                Layout.fillWidth: true
            }
        }

        SettingsCard {
            title: "Review before building"
            iconName: "security-medium"
            visible: page.pending !== null
            wide: true
            Layout.fillWidth: true

            ReviewCard {
                host: page
                review: page.pending !== null ? page.pending : ({ name: "", hash: "", findings: [], worst: "", problem: "" })
                onAccepted: page.acceptReview()
                onDismissed: page.pending = null
                Layout.fillWidth: true
            }
        }

        ProgressCard {
            host: page
            Layout.fillWidth: true
        }

        SettingsCard {
            title: page.found !== null ? Logic.plural(page.found.packages.length, "result", "results") + " for “" + page.searched + "”" : ""
            iconName: "view-list-details"
            visible: page.found !== null && page.found.packages.length > 0
            wide: true
            Layout.fillWidth: true

            Repeater {
                model: page.found !== null ? Logic.markInstalled(page.found.packages, page.installedNames()) : []

                PackageRow {
                    required property var modelData

                    host: page
                    pkg: modelData
                    Layout.fillWidth: true
                }
            }
        }
    }

    SettingsTab {
        title: "Installed"
        iconName: "view-list-details"

        SettingsCard {
            title: page.installedView !== null ? Logic.plural(page.installedView.packages.length, "package", "packages") : "Installed software"
            iconName: "package"
            help: "Removing also removes what only that package needed, and its settings."
            wide: true
            Layout.fillWidth: true

            SettingRow {
                settingId: "installed"
                label: "Installed software"
                highlight: page.highlight
                Layout.fillWidth: true

                QQC2.TextField {
                    objectName: "filter"
                    placeholderText: "Filter"
                    implicitWidth: 220
                    onTextChanged: page.filter = text
                }
            }
            ErrorCard {
                title: "Couldn't read the installed software"
                detail: page.installedView ? page.installedView.problem : ""
                visible: page.installedView !== null && page.installedView.problem !== ""
                Layout.fillWidth: true
            }
            Repeater {
                model: page.installedView !== null ? page.installedView.packages.filter(p => p.name.indexOf(page.filter.toLowerCase()) >= 0).slice(0, 100) : []

                PackageRow {
                    required property var modelData

                    host: page
                    pkg: modelData
                    Layout.fillWidth: true
                }
            }
        }
    }

    ReposTab {
        host: page
    }

    SettingsTab {
        title: "Scan"
        iconName: "security-medium"

        SettingsCard {
            title: "Scan what is installed"
            iconName: "security-medium"
            help: "oysterAV looks at the programs, libraries and settings files each package installed. Software from the AUR is the best place to start."
            wide: true
            Layout.fillWidth: true

            SettingRow {
                label: "Scan now"
                Layout.fillWidth: true
                QQC2.Button {
                    objectName: "scan-aur"
                    text: "AUR and other outside packages"
                    enabled: !page.busy
                    onClicked: page.scan(false)
                }
                QQC2.Button {
                    objectName: "scan-all"
                    text: "Everything installed"
                    enabled: !page.busy
                    onClicked: page.scan(true)
                }
            }
            SettingRow {
                settingId: "scan-installs"
                label: "Scan new installs"
                highlight: page.highlight
                Layout.fillWidth: true

                UqComboBox {
                    objectName: "set-scan_installs"
                    model: ["Never", "AUR builds only", "Everything I install"]
                    currentIndex: ["off", "aur", "all"].indexOf(page.setting("scan_installs"))
                    onActivated: i => page.setConfig("scan_installs", ["off", "aur", "all"][i])
                }
            }
            Outcome {
                host: page
                noteKey: "scan"
                Layout.fillWidth: true
            }
        }

        ProgressCard {
            host: page
            Layout.fillWidth: true
        }
    }

    PreferencesTab {
        host: page
    }
}
