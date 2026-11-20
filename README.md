# bindaru

A pacman and AUR package store for [uQ](https://github.com/asafelobotomy/uq), in the family of
[Bindle](https://github.com/asafelobotomy/bindle) (the setup wizard and app catalog) and bindleUP
(the system updater). bindaru is the store: browse, install and remove. System upgrades stay in
bindleUP.

## Design (decided 2026-11-16)

- Own repo, Rust core, GUI with cxx-qt and Kirigami reading uQ's theme tokens.
- Root only through its own `pkexec bindaru helper` with a polkit action. AUR builds
  always run as you; the helper only runs `pacman -U` on the result.
- **AUR review gate:** every AUR install and update shows the PKGBUILD (a diff on updates), a
  scan for risky patterns, and trust signals (maintainer, votes, orphan, out of date). The user
  must confirm. There is no setting that turns the gate off.
- uQ app contract: `config show|set`, `--dry-run --json`, `--ndjson`, and a uQ Settings page
  (`uq_api` 3) with Browse, Installed, Repositories, Scan and Settings tabs.

## Status

v0.1.4: the `bindaru` command (search, info, installed, review, install, remove, repos, scan, config),
the root helper (`pkexec bindaru helper`, polkit action in `packaging/polkit/`), the window
(`bindaru-gui`: sidebar, header search, list/grid/compact view, inspector, repositories, scan and
settings pages; Kirigami 6, coloured by uQ's theme tokens when uQ is running) and the uQ Settings page.
AUR installs stop at the review step until you pass `--ack <hash>` from `bindaru review --aur <pkg>`
(or type the package name on a terminal). When pacman fails, bindaru says why in plain words instead
of pacman's "Errors occurred, no packages were upgraded." (with `--ndjson`, a `failed` event carries
the reason); package lists older than the mirrors mean a full upgrade, so the window offers bindleUP.
The window needs Qt 6 and Kirigami 6, so it builds on Arch:
`cargo build --release --workspace`.

The window's sidebar has three groups: **On this computer** (Installed; the header search filters it),
**Find new software** (All sources, Arch repositories, The AUR; the header search asks them, and
the list stays empty until you search) and **Manage** (Software sources, Scan with oysterAV, Settings).
Thumbnails come from `bindaru icons` (the package's `.desktop` icon, else AppStream's cached icon,
else an icon named like the package); the inspector lists dependencies by kind: needs, optional,
to build (AUR), needed by, optional for.

```
bindaru search firefox
bindaru install --aur paru-bin --dry-run --json
bindaru review PKGBUILD --old PKGBUILD.installed
bindaru config set aur_enabled false
```

## Settings, repositories and oysterAV

- `bindaru config show|set`: AUR switches, how the list looks (`view`, `sort`, `sort_descending`, `group_by`, `density`, `show_inspector`, `search_in`, `start_filter`), behaviour, and `scan_installs` (`off`, `aur`, `all`).
- `bindaru repos list|add|remove|official`: switch multilib and the testing repos, add a repository (HTTPS, signatures required, optional `--key <40-digit fingerprint>`), remove one you added. pacman.conf is backed up first; run bindleUP afterwards for a full upgrade.
- `bindaru scan <pkg...>|--aur|--all`: hands the files packages installed to oysterAV (`oyst-cli scan --ndjson`). With `scan_installs` set, new installs are scanned automatically.
