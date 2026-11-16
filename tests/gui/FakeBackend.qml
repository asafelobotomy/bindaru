// A stand-in for the Rust Backend: answers run/stream from canned replies, later (never during the
// call), like the real one. `calls` records every request.
import QtQuick

QtObject {
    id: fake

    signal done(string id, int code, string out, string err)
    signal line(string id, string text)

    property var calls: []
    /// JSON.stringify(argv).join key -> {code, out, err}; the key is the argv joined by a space,
    /// or only its first two words when the full one isn't listed.
    property var replies: ({})
    property var events: ({})

    function reply(argv) {
        const full = argv.join(" ");
        if (replies[full] !== undefined)
            return replies[full];
        for (let n = argv.length - 1; n >= 1; n--) {
            const k = argv.slice(0, n).join(" ");
            if (replies[k] !== undefined)
                return replies[k];
        }
        return { code: 1, out: "", err: "no canned reply for " + full };
    }

    function run(id, argvJson) {
        const argv = JSON.parse(argvJson);
        fake.calls.push(["run", argv]);
        Qt.callLater(() => {
            const r = fake.reply(argv);
            fake.done(id, r.code, r.out, r.err);
        });
    }

    function stream(id, argvJson) {
        const argv = JSON.parse(argvJson);
        fake.calls.push(["stream", argv]);
        Qt.callLater(() => {
            const evs = fake.events[argv.slice(0, 2).join(" ")] || [];
            evs.forEach(e => fake.line(id, JSON.stringify(e)));
            const r = fake.reply(argv);
            fake.done(id, r.code, r.out, r.err);
        });
    }
}
