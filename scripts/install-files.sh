#!/bin/sh
# Installs everything bindaru ships into DESTDIR (default /): the command, the window, the polkit
# action, the desktop entry and icon, and the uQ Settings page. Used by the PKGBUILD; also handy
# for a manual install:
#   cargo build --release --workspace && sudo scripts/install-files.sh
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)
d=${DESTDIR:-}
install -Dm755 "$here/target/release/bindaru" "$d/usr/bin/bindaru"
install -Dm755 "$here/target/release/bindaru-gui" "$d/usr/bin/bindaru-gui"
install -Dm644 "$here/packaging/desktop/io.github.asafelobotomy.bindaru.desktop" \
    "$d/usr/share/applications/io.github.asafelobotomy.bindaru.desktop"
install -Dm644 "$here/packaging/desktop/bindaru.svg" "$d/usr/share/icons/hicolor/scalable/apps/bindaru.svg"
install -Dm644 "$here/packaging/polkit/io.github.asafelobotomy.bindaru.policy" \
    "$d/usr/share/polkit-1/actions/io.github.asafelobotomy.bindaru.policy"
install -Dm644 -t "$d/usr/share/uq/settings/pages/software/" "$here"/uq/pages/software/*.qml \
    "$here/uq/pages/software/logic.js" "$here/uq/pages/software/page.toml"
install -Dm644 "$here/LICENSE" "$d/usr/share/licenses/bindaru/LICENSE" 2>/dev/null || true
