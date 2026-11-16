#!/bin/sh
# Runs the window's QML tests against a fake backend: tests/gui/run.sh [shots-dir]
# Builds a throwaway QML module from crates/bindaru-gui/qml (minus Main.qml, which needs the Rust
# backend) so the Theme singleton and every component resolve as they do in the app.
set -e
here=$(cd "$(dirname "$0")" && pwd)
src="$here/../../crates/bindaru-gui/qml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/mod"
for f in "$src"/*.qml "$src"/../Theme.qml "$src"/logic.js; do
  [ "$(basename "$f")" = Main.qml ] || sed "/^import org.bindaru.app$/d" "$f" > "$tmp/mod/$(basename "$f")"
done
cp "$here/FakeBackend.qml" "$tmp/mod/"
{
  echo "module mod"
  echo "singleton Theme 1.0 Theme.qml"
  for f in "$tmp"/mod/*.qml; do
    n=$(basename "$f" .qml)
    [ "$n" = Theme ] || echo "$n 1.0 $n.qml"
  done
} > "$tmp/mod/qmldir"
shots=${1:-}
sed -e 's|^import QtTest|import QtTest\nimport "mod"|' -e "s|property string shotsDir: \"\"|property string shotsDir: \"$shots\"|" "$here/tst_window.qml" > "$tmp/tst_window.qml"
[ -z "$shots" ] || mkdir -p "$shots"
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import "$tmp" -input "$tmp/tst_window.qml"
