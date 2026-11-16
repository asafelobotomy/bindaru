//! The only place that starts processes: pacman and curl, run unprivileged with LC_ALL=C.
use bindaru_core::{aur, names::is_valid_pkg_name, parse, pkg::Package};
use std::process::Command;

fn out(prog: &str, args: &[&str]) -> Result<String, String> {
    let o = Command::new(prog)
        .args(args)
        .env("LC_ALL", "C")
        .output()
        .map_err(|e| format!("{prog}: {e}"))?;
    // pacman -Ss exits 1 when nothing matches; that is an empty result, not a failure.
    Ok(String::from_utf8_lossy(&o.stdout).into_owned())
}

pub fn search_repo(q: &str) -> Result<Vec<Package>, String> {
    Ok(parse::parse_search(&out(
        "/usr/bin/pacman",
        &["-Ss", "--", q],
    )?))
}

pub fn installed() -> Result<Vec<Package>, String> {
    Ok(parse::parse_info(&out("/usr/bin/pacman", &["-Qi"])?, true))
}

pub fn search_aur(q: &str) -> Result<Vec<Package>, String> {
    let url = format!(
        "https://aur.archlinux.org/rpc/v5/search/{}?by=name-desc",
        q.replace(
            |c: char| !c.is_ascii_alphanumeric() && c != '-' && c != '_',
            ""
        )
    );
    let body = out("/usr/bin/curl", &["-fsS", "--max-time", "10", &url])?;
    if body.is_empty() {
        return Err("could not reach the AUR".into());
    }
    Ok(aur::parse_reply(&body)?
        .into_iter()
        .filter(|a| is_valid_pkg_name(&a.name))
        .map(|a| {
            let mut p = Package::new(&a.name, &a.version, "aur");
            p.description = a.description.unwrap_or_default();
            p
        })
        .collect())
}

/// Names of packages that did not come from a sync repository (the AUR and manual installs).
pub fn foreign_names() -> Result<Vec<String>, String> {
    Ok(out("/usr/bin/pacman", &["-Qqm"])?
        .lines()
        .map(str::to_string)
        .filter(|n| is_valid_pkg_name(n))
        .collect())
}

pub fn installed_names() -> Result<Vec<String>, String> {
    Ok(out("/usr/bin/pacman", &["-Qq"])?
        .lines()
        .map(str::to_string)
        .filter(|n| is_valid_pkg_name(n))
        .collect())
}

/// `pacman -Ql` for these packages (names are validated by the caller).
pub fn files_of(names: &[String]) -> Result<Vec<String>, String> {
    let mut args = vec!["-Ql", "--"];
    args.extend(names.iter().map(String::as_str));
    Ok(bindaru_core::scan::package_files(&out(
        "/usr/bin/pacman",
        &args,
    )?))
}

pub fn read_conf() -> (String, String) {
    (
        std::fs::read_to_string("/etc/pacman.conf").unwrap_or_default(),
        std::fs::read_to_string(bindaru_core::repos::DROPIN_PATH).unwrap_or_default(),
    )
}

/// One package for the inspector: repo sync entry, else the installed entry, else the AUR's.
pub fn details(name: &str) -> Result<serde_json::Value, String> {
    if !is_valid_pkg_name(name) {
        return Err(format!("not a valid package name: {name:?}"));
    }
    let installed = parse::parse_info(&out("/usr/bin/pacman", &["-Qi", "--", name])?, true)
        .into_iter()
        .next();
    let repo = parse::parse_info(&out("/usr/bin/pacman", &["-Si", "--", name])?, false)
        .into_iter()
        .next();
    if let Some(mut p) = repo.or(installed) {
        p.installed = out("/usr/bin/pacman", &["-Qq", "--", name])
            .map(|o| !o.trim().is_empty())
            .unwrap_or(false);
        return Ok(serde_json::json!({"package": p, "aur": null}));
    }
    let url = format!("https://aur.archlinux.org/rpc/v5/info?arg[]={name}");
    let body = out("/usr/bin/curl", &["-fsS", "--max-time", "10", &url])?;
    let a = aur::parse_reply(&body)?
        .into_iter()
        .next()
        .ok_or_else(|| format!("{name}: not found"))?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0);
    let mut p = Package::new(&a.name, &a.version, "aur");
    p.description = a.description.clone().unwrap_or_default();
    p.depends = a.depends.clone();
    p.installed = out("/usr/bin/pacman", &["-Qq", "--", name])
        .map(|o| !o.trim().is_empty())
        .unwrap_or(false);
    Ok(
        serde_json::json!({"package": p, "aur": {"maintainer": a.maintainer, "votes": a.num_votes, "popularity": a.popularity, "flags": aur::flags(&a, now)}}),
    )
}
