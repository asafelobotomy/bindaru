# Agent notes for bindaru

| Path | What |
|---|---|
| `crates/bindaru-core` | pure: `parse` (pacman text), `aur` (RPC + trust flags), `review` (PKGBUILD scan + diff), `plan` (steps, who runs them), `config`, `names` (validation) |
| `crates/bindaru-cli` | `bindaru` binary; `sys.rs` is the only file that starts processes |

Rules: keep `bindaru-core` pure; every name reaching argv goes through `names`; AUR builds never run as
root; no setting may disable the review gate; keep files under ~400 lines. Verify: `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`.
