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
                "config-set": { code: 0, output: { aur_enabled: false } }
            })
        events: ({
                "install-aur": [
                    { event: "step", id: "fetch-btop-git", state: "start" },
                    { event: "step", id: "fetch-btop-git", state: "done" },
                    { event: "step", id: "build-btop-git", state: "start" },
                    { event: "step", id: "build-btop-git", state: "output", detail: "==> Making package: btop-git r123.abc-1" }
                ]
            })
        confirmed: ["install", "remove"]
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
    }
}
