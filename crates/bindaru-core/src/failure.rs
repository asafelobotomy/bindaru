//! Why a pacman transaction failed, in plain words. pacman ends most failed commits with
//! "Errors occurred, no packages were upgraded."; the cause is in the `error:` lines before it.
//! Run pacman with `LC_ALL=C` so these English messages are what we match.

/// A failed pacman run, explained.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Explained {
    pub message: String,
    /// The fix is a full system upgrade (bindleUP), not anything bindaru can do itself.
    pub needs_upgrade: bool,
}

const UPGRADE: &str = "Upgrade the system in bindleUP, then try again.";

/// `scummvm-2026.4.0-1-x86_64.pkg.tar.zst` -> `scummvm 2026.4.0-1`.
fn package_of(file: &str) -> String {
    let stem = file.split(".pkg.tar").next().unwrap_or(file);
    let parts: Vec<&str> = stem.rsplitn(4, '-').collect();
    match parts.as_slice() {
        [_arch, rel, ver, name] => format!("{name} {ver}-{rel}"),
        _ => file.to_string(),
    }
}

/// "a", "a and b", "a, b and 3 more".
fn some_of(items: &[String]) -> String {
    match items {
        [] => String::new(),
        [a] => a.clone(),
        [a, b] => format!("{a} and {b}"),
        [a, b, rest @ ..] => format!("{a}, {b} and {} more", rest.len()),
    }
}

fn quoted(line: &str) -> Option<&str> {
    let (_, rest) = line.split_once('\'')?;
    Some(rest.split_once('\'')?.0)
}

/// Explain pacman's output, or `None` when nothing in it is recognised as an error.
pub fn explain<S: AsRef<str>>(lines: &[S]) -> Option<Explained> {
    let lines: Vec<&str> = lines.iter().map(|l| l.as_ref().trim()).collect();
    let has = |s: &str| lines.iter().any(|l| l.contains(s));
    let say = |message: String, needs_upgrade: bool| {
        Some(Explained {
            message,
            needs_upgrade,
        })
    };

    if has("unable to lock database") {
        return say(
            "Another package manager is running (pacman's database is locked). Wait for it to finish, then try again.".into(),
            false,
        );
    }

    // A 404 for a file the sync database names: the database is older than the mirror.
    let gone: Vec<String> = lines
        .iter()
        .filter(|l| l.starts_with("error: failed retrieving file") && l.contains("404"))
        .filter_map(|l| quoted(l))
        .filter(|f| f.contains(".pkg.tar"))
        .map(package_of)
        .collect();
    if !gone.is_empty() {
        let are = if gone.len() == 1 { "is" } else { "are" };
        return say(
            format!(
                "The package lists are out of date: {} {are} no longer on the mirrors. {UPGRADE}",
                some_of(&gone)
            ),
            true,
        );
    }
    if has("failed to retrieve some files") || has("failed retrieving file") {
        return say(
            "Some packages could not be downloaded. Check the network connection and the mirrors, then try again.".into(),
            false,
        );
    }

    let missing: Vec<String> = lines
        .iter()
        .filter_map(|l| l.strip_prefix("error: target not found: "))
        .map(String::from)
        .collect();
    if !missing.is_empty() {
        return say(
            format!(
                "{} is not in the package lists. They may be out of date. {UPGRADE}",
                some_of(&missing)
            ),
            true,
        );
    }

    if has("invalid or corrupted package (PGP signature)")
        || has("is unknown trust")
        || has("is marked invalid")
        || has("unknown public key")
    {
        return say(
            format!(
                "A package signature could not be verified; the keyring may be out of date. {UPGRADE}"
            ),
            true,
        );
    }

    if has("(conflicting files)") {
        let files: Vec<String> = lines
            .iter()
            .filter(|l| l.ends_with(" exists in filesystem"))
            .map(|l| l.trim_end_matches(" exists in filesystem").to_string())
            .collect();
        return say(
            format!(
                "Files already on disk are in the way: {}. Remove or move them, then try again.",
                some_of(&files)
            ),
            false,
        );
    }

    if has("could not satisfy dependencies") || has("unresolvable package conflicts") {
        let why: Vec<String> = lines
            .iter()
            .filter_map(|l| l.strip_prefix(":: "))
            .filter(|l| l.contains("dependency") || l.contains("conflict"))
            .map(String::from)
            .collect();
        let detail = if why.is_empty() {
            String::new()
        } else {
            format!(" ({})", some_of(&why))
        };
        return say(
            format!("The dependencies don't fit what is installed{detail}. {UPGRADE}"),
            true,
        );
    }

    if has("not enough free disk space") {
        return say(
            "There is not enough free disk space. Free some, then try again.".into(),
            false,
        );
    }

    let errors: Vec<String> = lines
        .iter()
        .filter_map(|l| l.strip_prefix("error: "))
        .map(String::from)
        .collect();
    (!errors.is_empty()).then(|| Explained {
        message: format!("pacman: {}", some_of(&errors)),
        needs_upgrade: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Captured from `pacman -S --needed --noconfirm scummvm` against the 2026-11-15 extra.db.
    const STALE: &[&str] = &[
        "resolving dependencies...",
        " scummvm-2026.4.0-1-x86_64 downloading...",
        "error: failed retrieving file 'scummvm-2026.4.0-1-x86_64.pkg.tar.zst' from geo.mirror.pkgbuild.com : The requested URL returned error: 404",
        "error: failed retrieving file 'glycin-2.2.6-1-x86_64.pkg.tar.zst' from geo.mirror.pkgbuild.com : The requested URL returned error: 404",
        "error: failed retrieving file 'mesa-1:26.2.7-1-x86_64.pkg.tar.zst' from geo.mirror.pkgbuild.com : The requested URL returned error: 404",
        "warning: too many errors from geo.mirror.pkgbuild.com, skipping for the remainder of this transaction",
        "warning: failed to retrieve some files",
        "error: failed to commit transaction (unexpected error)",
        "Errors occurred, no packages were upgraded.",
    ];

    #[test]
    fn a_stale_database_asks_for_a_system_upgrade() {
        let e = explain(STALE).unwrap();
        assert!(e.needs_upgrade);
        assert_eq!(
            e.message,
            "The package lists are out of date: scummvm 2026.4.0-1, glycin 2.2.6-1 and 1 more are no longer on the mirrors. Upgrade the system in bindleUP, then try again."
        );
        assert!(!e.message.contains("Errors occurred"));
    }

    #[test]
    fn package_names_keep_their_dashes_and_epochs() {
        assert_eq!(
            package_of("lib32-mesa-1:26.2.7-1-x86_64.pkg.tar.zst"),
            "lib32-mesa 1:26.2.7-1"
        );
        assert_eq!(package_of("odd"), "odd");
    }

    #[test]
    fn a_network_failure_is_not_an_upgrade() {
        let e = explain(&[
            "error: failed retrieving file 'x-1-1-any.pkg.tar.zst' from m : Could not resolve host: m",
            "Errors occurred, no packages were upgraded.",
        ])
        .unwrap();
        assert!(!e.needs_upgrade);
        assert!(e.message.contains("network"));
    }

    #[test]
    fn conflicting_files_are_named() {
        let e = explain(&[
            "error: failed to commit transaction (conflicting files)",
            "foo: /usr/bin/foo exists in filesystem",
            "Errors occurred, no packages were upgraded.",
        ])
        .unwrap();
        assert_eq!(
            e.message,
            "Files already on disk are in the way: foo: /usr/bin/foo. Remove or move them, then try again."
        );
    }

    #[test]
    fn locks_keys_targets_and_dependencies() {
        assert!(
            explain(&["error: failed to init transaction (unable to lock database)"])
                .unwrap()
                .message
                .contains("locked")
        );
        assert!(
            explain(&["error: target not found: nope"])
                .unwrap()
                .needs_upgrade
        );
        assert!(
            explain(&[
                "error: scummvm: signature from \"X\" is unknown trust",
                "error: failed to commit transaction (invalid or corrupted package (PGP signature))"
            ])
            .unwrap()
            .message
            .contains("keyring")
        );
        let d = explain(&[
            "error: failed to prepare transaction (could not satisfy dependencies)",
            ":: installing icu (78-1) breaks dependency 'libicuuc.so=76' required by harfbuzz",
        ])
        .unwrap();
        assert!(d.needs_upgrade && d.message.contains("breaks dependency"));
    }

    #[test]
    fn unknown_errors_pass_through_and_quiet_output_is_none() {
        assert_eq!(
            explain(&["error: something new"]).unwrap().message,
            "pacman: something new"
        );
        assert_eq!(explain(&["all fine"]), None);
    }
}
