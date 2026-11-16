# bindaru

A pacman and AUR package store for [uQ](https://github.com/asafelobotomy/uq), in the family of
[Bindle](https://github.com/asafelobotomy/bindle) (the setup wizard and app catalog) and bindleUP
(the system updater). bindaru is the store: browse, install and remove. System upgrades stay in
bindleUP.

## Design (decided 2026-11-16)

- Own repo, Rust core, GUI with cxx-qt and Kirigami reading uQ's theme tokens (planned).
- Root only through its own `pkexec bindaru helper` with a polkit action (planned). AUR builds
  always run as you; the helper only runs `pacman -U` on the result.
- **AUR review gate:** every AUR install and update shows the PKGBUILD (a diff on updates), a
  scan for risky patterns, and trust signals (maintainer, votes, orphan, out of date). The user
  must confirm. There is no setting that turns the gate off.
- uQ app contract: `config show|set`, `--dry-run --json`, `--ndjson`, and a uQ Settings page
  (`uq_api` 3) later.

## Status

v0.0.2 (unreleased): the pure core (parsers, AUR flags, review scan and diff, planner, config) and a CLI that
searches, shows, reviews PKGBUILDs offline and prints install/remove plans with `--dry-run`.
The root helper (`pkexec bindaru helper`, polkit action in `packaging/polkit/`) now runs installs and removes; AUR installs stop at the review step until you pass `--ack <hash>` from `bindaru review --aur <pkg>` (or type the package name on a terminal). The GUI and the uQ page come next.

```
bindaru search firefox
bindaru install --aur paru-bin --dry-run --json
bindaru review PKGBUILD --old PKGBUILD.installed
bindaru config set aur_enabled false
```
