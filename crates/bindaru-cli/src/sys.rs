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

pub fn info(name: &str) -> Result<Package, String> {
    if !is_valid_pkg_name(name) {
        return Err(format!("not a valid package name: {name:?}"));
    }
    let t = out("/usr/bin/pacman", &["-Si", "--", name])?;
    parse::parse_info(&t, false)
        .into_iter()
        .next()
        .ok_or_else(|| format!("{name}: not found in the repositories"))
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
