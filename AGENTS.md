# Agent notes for bindaru

| Path | What |
|---|---|
| `crates/bindaru-core` | pure: `parse` (pacman text), `aur` (RPC + trust flags), `review` (PKGBUILD scan + diff), `plan` (steps, who runs them), `config` (bool and word keys, validated), `names`, `repos` (pacman.conf reading, official toggles, bindaru's HTTPS+signed drop-in), `scan` (oysterAV batches), `protocol` (helper requests) |
| `crates/bindaru-cli` | `bindaru` binary; `sys.rs` is the only file that starts processes |

Rules: keep `bindaru-core` pure; every name reaching argv goes through `names`; AUR builds never run as
root; no setting may disable the review gate; keep files under ~400 lines. Verify: `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`.

Repos rule: bindaru only edits pacman.conf to (un)comment multilib/testing and to add one Include line; added repos live in `/etc/pacman.d/bindaru-repos.conf`, HTTPS only, `SigLevel = Required DatabaseRequired`. Trusting a key needs a full 40-digit fingerprint and its own plan step.
