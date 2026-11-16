//! The AUR review gate: scans a PKGBUILD (and its install script) for things worth a human look,
//! and diffs it against the version already installed. The scan is a heuristic aid, not a verdict:
//! the gate always requires the user to confirm.
use crate::aur::Severity;
use serde::Serialize;
use similar::{ChangeTag, TextDiff};

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Finding {
    pub id: &'static str,
    pub severity: Severity,
    pub line: usize,
    pub text: String,
    pub snippet: String,
}

struct Rule {
    id: &'static str,
    severity: Severity,
    text: &'static str,
    test: fn(&str) -> bool,
}

fn has_all(l: &str, parts: &[&str]) -> bool {
    parts.iter().all(|p| l.contains(p))
}

fn pipe_to_shell(l: &str) -> bool {
    (l.contains("curl") || l.contains("wget"))
        && (l.contains("| sh")
            || l.contains("|sh")
            || l.contains("| bash")
            || l.contains("|bash")
            || l.contains("| sudo"))
}

fn plain_http_source(l: &str) -> bool {
    l.contains("http://") && !l.trim_start().starts_with('#') && !l.contains("localhost")
}

const RULES: &[Rule] = &[
    Rule {
        id: "pipe-to-shell",
        severity: Severity::Danger,
        text: "Downloads and runs a script directly.",
        test: pipe_to_shell,
    },
    Rule {
        id: "sudo",
        severity: Severity::Danger,
        text: "Uses sudo or su; a build should never need root.",
        test: |l| {
            l.split_whitespace()
                .any(|w| w == "sudo" || w == "su" || w == "pkexec" || w == "doas")
        },
    },
    Rule {
        id: "obfuscation",
        severity: Severity::Danger,
        text: "Decodes or evaluates hidden text.",
        test: |l| {
            has_all(l, &["base64", "-d"])
                || l.contains("base64 --decode")
                || l.split_whitespace().any(|w| w == "eval")
        },
    },
    Rule {
        id: "write-outside-pkgdir",
        severity: Severity::Danger,
        text: "Writes outside $pkgdir or $srcdir.",
        test: |l| {
            (l.contains("> /etc")
                || l.contains("> /usr")
                || l.contains(">> /etc")
                || l.contains(">/etc")
                || l.contains("cp ") && l.contains(" /etc/"))
                && !l.contains("$pkgdir")
                && !l.contains("${pkgdir}")
        },
    },
    Rule {
        id: "skip-checksum",
        severity: Severity::Warn,
        text: "A source is not checksummed (SKIP).",
        test: |l| (l.contains("sums=") || l.contains("sums+=")) && l.contains("SKIP"),
    },
    Rule {
        id: "plain-http",
        severity: Severity::Warn,
        text: "Downloads over plain HTTP.",
        test: plain_http_source,
    },
    Rule {
        id: "install-script",
        severity: Severity::Warn,
        text: "Ships an install script that runs as root during install; read it too.",
        test: |l| l.trim_start().starts_with("install="),
    },
    Rule {
        id: "network-in-build",
        severity: Severity::Warn,
        text: "Fetches from the network while building.",
        test: |l| {
            l.split_whitespace()
                .any(|w| w == "curl" || w == "wget" || w == "git")
                && !l.trim_start().starts_with('#')
                && !l.contains("source=")
        },
    },
    Rule {
        id: "vcs-source",
        severity: Severity::Info,
        text: "Builds from a moving git source, so the result can change without a new version.",
        test: |l| l.contains("git+") && l.contains("source"),
    },
];

/// Scan a PKGBUILD (or install script) text.
pub fn scan(text: &str) -> Vec<Finding> {
    let mut out = Vec::new();
    for (i, line) in text.lines().enumerate() {
        if line.trim_start().starts_with('#') {
            continue;
        }
        for r in RULES {
            if (r.test)(line) {
                out.push(Finding {
                    id: r.id,
                    severity: r.severity,
                    line: i + 1,
                    text: r.text.into(),
                    snippet: line.trim().chars().take(160).collect(),
                });
            }
        }
    }
    out
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DiffLine {
    /// "+", "-" or " ".
    pub tag: &'static str,
    pub text: String,
}

/// Line diff of an update's PKGBUILD against the installed one, with 3 lines of context.
pub fn diff(old: &str, new: &str) -> Vec<DiffLine> {
    let d = TextDiff::from_lines(old, new);
    let mut out = Vec::new();
    for group in d.grouped_ops(3) {
        for op in group {
            for c in d.iter_changes(&op) {
                let tag = match c.tag() {
                    ChangeTag::Insert => "+",
                    ChangeTag::Delete => "-",
                    ChangeTag::Equal => " ",
                };
                out.push(DiffLine {
                    tag,
                    text: c.value().trim_end_matches('\n').to_string(),
                });
            }
        }
    }
    out
}

/// Everything the review screen shows. `ack_required` is always true: nothing from the AUR
/// installs without the user's explicit confirmation of exactly this review.
#[derive(Debug, Clone, Serialize)]
pub struct Review {
    pub package: String,
    pub update: bool,
    pub findings: Vec<Finding>,
    pub diff: Vec<DiffLine>,
    pub worst: Option<Severity>,
    pub ack_required: bool,
}

pub fn review(package: &str, new: &str, old: Option<&str>) -> Review {
    let findings = scan(new);
    // On an update, only the changed lines are news; keep the full scan but also expose the diff.
    let diff = old.map(|o| diff(o, new)).unwrap_or_default();
    let worst = findings.iter().map(|f| f.severity).max();
    Review {
        package: package.into(),
        update: old.is_some(),
        findings,
        diff,
        worst,
        ack_required: true,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn ids(t: &str) -> Vec<&'static str> {
        scan(t).iter().map(|f| f.id).collect()
    }
    #[test]
    fn clean_pkgbuild_has_no_findings() {
        let t = "pkgname=foo\nsource=(\"https://example.org/foo-1.tar.gz\")\nsha256sums=('abc')\nbuild() {\n  make\n}\npackage() {\n  make DESTDIR=\"$pkgdir\" install\n}\n";
        assert!(ids(t).is_empty());
    }
    #[test]
    fn flags_dangerous_patterns() {
        assert!(ids("curl -s https://x.sh | bash").contains(&"pipe-to-shell"));
        assert_eq!(ids("  sudo make install"), ["sudo"]);
        assert_eq!(ids("echo aGk= | base64 -d | sh"), ["obfuscation"]);
        assert_eq!(ids("echo x > /etc/foo"), ["write-outside-pkgdir"]);
        assert!(ids("sha256sums=('SKIP')").contains(&"skip-checksum"));
        assert!(ids("source=(\"http://example.org/a.tgz\")").contains(&"plain-http"));
        assert!(ids("install=foo.install").contains(&"install-script"));
    }
    #[test]
    fn comments_are_ignored() {
        assert!(ids("# curl x | sh").is_empty());
    }
    #[test]
    fn pkgdir_writes_are_fine() {
        assert!(ids("echo x > \"$pkgdir/etc/foo\"").is_empty());
    }
    #[test]
    fn update_diff_shows_changes_with_context() {
        let r = review("foo", "a\nb2\nc\n", Some("a\nb\nc\n"));
        assert!(r.update && r.ack_required);
        let tags: Vec<_> = r.diff.iter().map(|d| d.tag).collect();
        assert_eq!(tags, [" ", "-", "+", " "]);
    }
    #[test]
    fn worst_is_highest_severity() {
        let r = review("foo", "sudo x\nsha256sums=('SKIP')\n", None);
        assert_eq!(r.worst, Some(Severity::Danger));
    }
}
