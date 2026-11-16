//! Package-name validation. Every name that reaches pacman, git or a path passes through here.

/// Arch package names: lowercase letters, digits and `@ . _ + -`; never empty, never start with
/// `-` or `.`, at most 255 characters.
pub fn is_valid_pkg_name(s: &str) -> bool {
    let b = s.as_bytes();
    if b.is_empty() || b.len() > 255 || matches!(b[0], b'-' | b'.') {
        return false;
    }
    b.iter()
        .all(|c| matches!(c, b'a'..=b'z' | b'0'..=b'9' | b'@' | b'.' | b'_' | b'+' | b'-'))
}

pub fn check_names(names: &[String]) -> Result<(), String> {
    match names.iter().find(|n| !is_valid_pkg_name(n)) {
        Some(bad) => Err(format!("not a valid package name: {bad:?}")),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn accepts_real_names() {
        for n in [
            "firefox",
            "lib32-glibc",
            "gtk4",
            "python-pip",
            "c++utilities",
            "a.b_c@d",
        ] {
            assert!(is_valid_pkg_name(n), "{n}");
        }
    }
    #[test]
    fn rejects_dangerous_names() {
        for n in [
            "",
            "-rf",
            "--noconfirm",
            ".hidden",
            "a b",
            "a/b",
            "../x",
            "A",
            "a;b",
            "a\nb",
        ] {
            assert!(!is_valid_pkg_name(n), "{n:?}");
        }
    }
}
