//! JSON-lines protocol between the user-side client and the root helper (`pkexec bindaru helper`).
//! The helper trusts nothing in a request: it validates here, then builds argv itself.
use crate::names::check_names;
use serde::{Deserialize, Serialize};
use std::path::{Component, Path, PathBuf};

pub const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "kebab-case")]
pub enum Request {
    /// Version handshake; the helper answers with its own version.
    Hello { version: String },
    /// `pacman -S --needed` for repo packages, one transaction.
    Install { names: Vec<String> },
    /// `pacman -Rns`.
    Remove { names: Vec<String> },
    /// `pacman -U` of package files the user built under their bindaru build cache.
    InstallFiles { paths: Vec<String> },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "kebab-case")]
pub enum Event {
    Hello { version: String },
    Output { line: String },
    Done { ok: bool, code: Option<i32> },
    Error { message: String },
}

/// Where a user's builds live, relative to their home.
pub const BUILD_CACHE: &str = ".cache/bindaru/build";

fn clean_abs(p: &str) -> Option<PathBuf> {
    let path = Path::new(p);
    if !path.is_absolute()
        || path
            .components()
            .any(|c| matches!(c, Component::ParentDir | Component::CurDir))
    {
        return None;
    }
    Some(path.to_path_buf())
}

pub fn is_package_file(name: &str) -> bool {
    [".pkg.tar.zst", ".pkg.tar.xz"]
        .iter()
        .any(|e| name.ends_with(e))
        && !name.starts_with('-')
}

/// Check that every path is a package file inside `<home>/.cache/bindaru/build/`.
pub fn check_files(paths: &[String], home: &Path) -> Result<Vec<PathBuf>, String> {
    if paths.is_empty() {
        return Err("no package files".into());
    }
    let root = home.join(BUILD_CACHE);
    paths
        .iter()
        .map(|p| {
            let path = clean_abs(p).ok_or_else(|| format!("not a clean absolute path: {p:?}"))?;
            let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
            if !path.starts_with(&root) || !is_package_file(name) {
                return Err(format!(
                    "not a package file under {}: {p:?}",
                    root.display()
                ));
            }
            Ok(path)
        })
        .collect()
}

/// The user's home from `/etc/passwd` text, by uid.
pub fn passwd_home(passwd: &str, uid: u32) -> Option<PathBuf> {
    passwd.lines().find_map(|l| {
        let f: Vec<&str> = l.split(':').collect();
        (f.len() >= 6 && f[2].parse() == Ok(uid)).then(|| PathBuf::from(f[5]))
    })
}

/// The argv the helper runs for a request, once validated. `staged` are root-owned copies.
pub fn argv(req: &Request, staged: &[PathBuf]) -> Result<Vec<String>, String> {
    let mut v: Vec<String> = Vec::new();
    match req {
        Request::Hello { .. } => return Err("hello runs no command".into()),
        Request::Install { names } => {
            check_names(names)?;
            if names.is_empty() {
                return Err("nothing to install".into());
            }
            v.extend(["/usr/bin/pacman", "-S", "--needed", "--noconfirm", "--"].map(String::from));
            v.extend(names.iter().cloned());
        }
        Request::Remove { names } => {
            check_names(names)?;
            if names.is_empty() {
                return Err("nothing to remove".into());
            }
            v.extend(["/usr/bin/pacman", "-Rns", "--noconfirm", "--"].map(String::from));
            v.extend(names.iter().cloned());
        }
        Request::InstallFiles { .. } => {
            v.extend(["/usr/bin/pacman", "-U", "--noconfirm", "--"].map(String::from));
            v.extend(staged.iter().map(|p| p.display().to_string()));
        }
    }
    Ok(v)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn requests_roundtrip() {
        let r = Request::Install {
            names: vec!["htop".into()],
        };
        let j = serde_json::to_string(&r).unwrap();
        assert_eq!(j, r#"{"op":"install","names":["htop"]}"#);
        assert_eq!(serde_json::from_str::<Request>(&j).unwrap(), r);
        assert!(serde_json::from_str::<Request>(r#"{"op":"shell","cmd":"id"}"#).is_err());
    }
    #[test]
    fn argv_validates_names() {
        assert!(
            argv(
                &Request::Install {
                    names: vec!["--overwrite=*".into()]
                },
                &[]
            )
            .is_err()
        );
        let a = argv(
            &Request::Remove {
                names: vec!["htop".into()],
            },
            &[],
        )
        .unwrap();
        assert_eq!(a, ["/usr/bin/pacman", "-Rns", "--noconfirm", "--", "htop"]);
    }
    #[test]
    fn files_must_be_in_the_users_build_cache() {
        let home = Path::new("/home/u");
        let ok = "/home/u/.cache/bindaru/build/foo/foo-1-1-x86_64.pkg.tar.zst".to_string();
        assert!(check_files(&[ok], home).is_ok());
        for bad in [
            "/etc/passwd",
            "/home/u/.cache/bindaru/build/../../x.pkg.tar.zst",
            "/home/u/.cache/bindaru/build/foo/evil.sh",
            "/home/other/.cache/bindaru/build/a.pkg.tar.zst",
            "rel.pkg.tar.zst",
        ] {
            assert!(check_files(&[bad.to_string()], home).is_err(), "{bad}");
        }
        assert!(check_files(&[], home).is_err());
    }
    #[test]
    fn passwd_lookup() {
        let p = "root:x:0:0::/root:/bin/bash\nme:x:1000:1000:Me:/home/me:/bin/zsh\n";
        assert_eq!(passwd_home(p, 1000), Some(PathBuf::from("/home/me")));
        assert_eq!(passwd_home(p, 5), None);
    }
}
