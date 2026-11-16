# bindaru in uQ

`uq/pages/software/` adds a **Software** page under Apps in uQ Settings (`uq_api` 3): browse, install and
remove software with uQ's confirmation sheet and live progress, and the AUR review card (findings from
`bindaru review --aur`, then an install bound to that exact recipe's hash). Installed to
`/usr/share/uq/settings/pages/software/`; inert without uQ.

Tested with `uqctl integrations check uq/ --no-programs`, `node --test tests/uq/*.test.mjs` and
`tests/uq/tst_page.qml` (fake ctx). `tests/uq/shots.sh <dir>` saves a screenshot of each state.
