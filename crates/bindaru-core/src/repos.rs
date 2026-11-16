//! Repositories: reading `pacman.conf`, and the small set of edits bindaru may make to it.
//! bindaru never rewrites pacman.conf freely. It (1) comments or uncomments the official
//! optional repositories, and (2) keeps the repositories it adds in its own drop-in file,
//! `/etc/pacman.d/bindaru-repos.conf`, pulled in by one `Include` line.
//! Added repositories must be HTTPS and must verify signatures; there is no way to add one that
//! doesn't.
use serde::Serialize;

pub const DROPIN_PATH: &str = "/etc/pacman.d/bindaru-repos.conf";
const INCLUDE_LINE: &str = "Include = /etc/pacman.d/bindaru-repos.conf";
const MARK: &str = "# Managed by bindaru: repositories added in bindaru. Edit them there.";

/// Official repositories bindaru can switch on and off.
pub const OFFICIAL_OPTIONAL: &[&str] = &[
    "multilib",
    "core-testing",
    "extra-testing",
    "multilib-testing",
];
const OFFICIAL_ALL: &[&str] = &[
    "core",
    "extra",
    "multilib",
    "core-testing",
    "extra-testing",
    "multilib-testing",
];

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Repo {
    pub name: String,
    pub enabled: bool,
    /// "official", "added" (in bindaru's drop-in) or "other" (anything else in pacman.conf).
    pub origin: &'static str,
    pub servers: Vec<String>,
    pub includes: Vec<String>,
    pub sig_level: Option<String>,
}

fn section(line: &str) -> Option<&str> {
    let l = line.trim();
    l.strip_prefix('[')?.strip_suffix(']')
}

fn parse_into(text: &str, origin_of: &dyn Fn(&str) -> &'static str, out: &mut Vec<Repo>) {
    let mut cur: Option<Repo> = None;
    // A commented-out section header followed by its commented lines counts as a disabled repo.
    for raw in text.lines() {
        let line = raw.trim();
        let (enabled, body) = match line.strip_prefix('#') {
            Some(b) => (false, b.trim()),
            None => (true, line),
        };
        if let Some(name) = section(body) {
            if name == "options" || !is_repo_name(name) {
                if let Some(r) = cur.take() {
                    out.push(r);
                }
                continue;
            }
            // A commented header is only a repo if it is one pacman.conf ships commented.
            if !enabled && !OFFICIAL_ALL.contains(&name) {
                continue;
            }
            if let Some(r) = cur.take() {
                out.push(r);
            }
            cur = Some(Repo {
                name: name.into(),
                enabled,
                origin: origin_of(name),
                servers: vec![],
                includes: vec![],
                sig_level: None,
            });
            continue;
        }
        let Some(r) = cur.as_mut() else { continue };
        if !enabled && r.enabled {
            continue; // an ordinary comment inside an enabled repo
        }
        if let Some((k, v)) = body.split_once('=') {
            let (k, v) = (k.trim(), v.trim());
            match k {
                "Server" => r.servers.push(v.to_string()),
                "Include" => r.includes.push(v.to_string()),
                "SigLevel" => r.sig_level = Some(v.to_string()),
                _ => {}
            }
        }
    }
    if let Some(r) = cur.take() {
        out.push(r);
    }
}

fn origin_for(name: &str) -> &'static str {
    if OFFICIAL_ALL.contains(&name) {
        "official"
    } else {
        "other"
    }
}

/// Every repository, from pacman.conf and bindaru's drop-in (`dropin` may be empty).
pub fn list(conf: &str, dropin: &str) -> Vec<Repo> {
    let mut out = Vec::new();
    parse_into(conf, &origin_for, &mut out);
    parse_into(dropin, &|_| "added", &mut out);
    out
}

pub fn is_repo_name(s: &str) -> bool {
    let b = s.as_bytes();
    !b.is_empty()
        && b.len() <= 32
        && b[0].is_ascii_alphanumeric()
        && b.iter()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'-' || *c == b'_')
}

/// A repository bindaru may add.
#[derive(Debug, Clone, PartialEq)]
pub struct NewRepo {
    pub name: String,
    pub server: String,
}

pub fn check_new(r: &NewRepo, existing: &[Repo]) -> Result<(), String> {
    if !is_repo_name(&r.name) || r.name == "options" {
        return Err(format!("not a valid repository name: {:?}", r.name));
    }
    if OFFICIAL_ALL.contains(&r.name.as_str()) || existing.iter().any(|e| e.name == r.name) {
        return Err(format!("a repository called {} already exists", r.name));
    }
    check_server(&r.server)
}

/// HTTPS only, no spaces or shell/line characters, only the `$repo` and `$arch` variables.
pub fn check_server(s: &str) -> Result<(), String> {
    let rest = s
        .strip_prefix("https://")
        .ok_or("the server must start with https://")?;
    if rest.is_empty() || s.len() > 300 {
        return Err("the server address is empty or too long".into());
    }
    if !rest
        .bytes()
        .all(|c| c.is_ascii_alphanumeric() || b"-._~:/%@+$".contains(&c))
    {
        return Err("the server address has characters that aren't allowed".into());
    }
    let mut vars = rest.split('$').skip(1);
    if vars.any(|v| !(v.starts_with("repo") || v.starts_with("arch"))) {
        return Err("only $repo and $arch may be used in a server address".into());
    }
    Ok(())
}

/// A key fingerprint: 40 hex digits (uppercase), nothing shorter: short ids can be forged.
pub fn check_fingerprint(s: &str) -> Result<(), String> {
    if s.len() == 40
        && s.bytes()
            .all(|c| c.is_ascii_digit() || (b'A'..=b'F').contains(&c))
    {
        Ok(())
    } else {
        Err("a key fingerprint is 40 hex digits (A to F, 0 to 9)".into())
    }
}

/// The drop-in's text for the repositories bindaru manages.
pub fn render_dropin(repos: &[NewRepo]) -> String {
    let mut s = format!("{MARK}\n");
    for r in repos {
        s.push_str(&format!(
            "\n[{}]\nSigLevel = Required DatabaseRequired\nServer = {}\n",
            r.name, r.server
        ));
    }
    s
}

/// The repositories in a drop-in as `NewRepo`s (so add and remove start from what is there).
pub fn parse_dropin(dropin: &str) -> Vec<NewRepo> {
    list("", dropin)
        .into_iter()
        .filter(|r| r.enabled)
        .filter_map(|r| {
            Some(NewRepo {
                name: r.name,
                server: r.servers.first()?.clone(),
            })
        })
        .collect()
}

/// `pacman.conf` with the drop-in's Include line added at the end, if it isn't there.
pub fn with_include(conf: &str) -> Option<String> {
    if conf.lines().any(|l| l.trim() == INCLUDE_LINE) {
        return None;
    }
    let mut s = conf.trim_end().to_string();
    s.push_str(&format!("\n\n{MARK}\n{INCLUDE_LINE}\n"));
    Some(s)
}

/// Switch an official optional repository on or off by (un)commenting its section. `None` when
/// it is already so or isn't in the file.
pub fn set_official(conf: &str, name: &str, enabled: bool) -> Result<Option<String>, String> {
    if !OFFICIAL_OPTIONAL.contains(&name) {
        return Err(format!(
            "{name} can't be switched here; core and extra are always on"
        ));
    }
    let mut out = Vec::new();
    let mut inside = false;
    let mut found = false;
    let mut changed = false;
    for line in conf.lines() {
        let t = line.trim();
        let body = t.strip_prefix('#').map(str::trim).unwrap_or(t);
        if let Some(n) = section(body) {
            inside = n == name;
            found |= inside;
        } else if inside
            && !(t.starts_with("Include")
                || t.starts_with("#Include")
                || t.starts_with("Server")
                || t.starts_with("#Server")
                || t.starts_with("SigLevel")
                || t.starts_with("#SigLevel"))
        {
            // Leaving the repo's block at the first unrelated line.
            if !t.is_empty() && !t.starts_with('#') {
                inside = false;
            }
        }
        if inside && !t.is_empty() {
            let commented = t.starts_with('#');
            let is_content = section(body).is_some()
                || body.starts_with("Include")
                || body.starts_with("Server")
                || body.starts_with("SigLevel");
            if is_content && enabled && commented {
                out.push(body.to_string());
                changed = true;
                continue;
            }
            if is_content && !enabled && !commented {
                out.push(format!("#{t}"));
                changed = true;
                continue;
            }
        }
        out.push(line.to_string());
    }
    if !found {
        return Err(format!("{name} isn't in pacman.conf"));
    }
    Ok(changed.then(|| out.join("\n") + "\n"))
}

#[cfg(test)]
mod tests {
    use super::*;
    const CONF: &str = "[options]\nHoldPkg = pacman glibc\n\n[core]\nInclude = /etc/pacman.d/mirrorlist\n\n[extra]\nInclude = /etc/pacman.d/mirrorlist\n\n#[multilib-testing]\n#Include = /etc/pacman.d/mirrorlist\n\n#[multilib]\n#Include = /etc/pacman.d/mirrorlist\n\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n";
    #[test]
    fn lists_enabled_disabled_and_other() {
        let r = list(CONF, "");
        let names: Vec<_> = r
            .iter()
            .map(|r| (r.name.as_str(), r.enabled, r.origin))
            .collect();
        assert_eq!(
            names,
            [
                ("core", true, "official"),
                ("extra", true, "official"),
                ("multilib-testing", false, "official"),
                ("multilib", false, "official"),
                ("chaotic-aur", true, "other")
            ]
        );
        assert_eq!(r[0].includes, ["/etc/pacman.d/mirrorlist"]);
    }
    #[test]
    fn multilib_toggles_both_ways() {
        let on = set_official(CONF, "multilib", true).unwrap().unwrap();
        assert!(on.contains("\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n"));
        assert!(on.contains("#[multilib-testing]"), "only multilib changes");
        assert!(
            list(&on, "")
                .iter()
                .any(|r| r.name == "multilib" && r.enabled)
        );
        let off = set_official(&on, "multilib", false).unwrap().unwrap();
        assert_eq!(off, CONF);
        assert_eq!(set_official(CONF, "multilib", false).unwrap(), None);
    }
    #[test]
    fn core_cannot_be_switched() {
        assert!(set_official(CONF, "core", false).is_err());
        assert!(set_official(CONF, "extra", false).is_err());
    }
    #[test]
    fn added_repos_are_https_signed_and_unique() {
        let ok = NewRepo {
            name: "myrepo".into(),
            server: "https://example.org/$repo/os/$arch".into(),
        };
        assert!(check_new(&ok, &list(CONF, "")).is_ok());
        for bad in [
            "http://example.org/x",
            "https://a b",
            "https://x/$evil",
            "ftp://x",
            "https://x\nServer=y",
            "https://",
        ] {
            assert!(check_server(bad).is_err(), "{bad:?}");
        }
        let dup = NewRepo {
            name: "chaotic-aur".into(),
            ..ok.clone()
        };
        assert!(check_new(&dup, &list(CONF, "")).is_err());
        assert!(
            check_new(
                &NewRepo {
                    name: "core".into(),
                    ..ok.clone()
                },
                &[]
            )
            .is_err()
        );
        assert!(
            check_new(
                &NewRepo {
                    name: "Bad Name".into(),
                    ..ok
                },
                &[]
            )
            .is_err()
        );
    }
    #[test]
    fn dropin_roundtrips_and_requires_signatures() {
        let rs = vec![
            NewRepo {
                name: "a".into(),
                server: "https://a.example/$arch".into(),
            },
            NewRepo {
                name: "b".into(),
                server: "https://b.example/$arch".into(),
            },
        ];
        let d = render_dropin(&rs);
        assert!(d.contains("SigLevel = Required DatabaseRequired"));
        assert_eq!(parse_dropin(&d), rs);
        assert!(list("", &d).iter().all(|r| r.origin == "added"));
    }
    #[test]
    fn include_line_is_added_once() {
        let once = with_include(CONF).unwrap();
        assert!(once.ends_with("Include = /etc/pacman.d/bindaru-repos.conf\n"));
        assert_eq!(with_include(&once), None);
    }
    #[test]
    fn fingerprints_must_be_full_length() {
        assert!(check_fingerprint(&"AB12".repeat(10)).is_ok());
        for bad in ["", "ABCD1234", &"ab12".repeat(10), &"G".repeat(40)] {
            assert!(check_fingerprint(bad).is_err());
        }
    }
}
