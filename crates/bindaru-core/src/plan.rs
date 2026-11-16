//! The planner: turns a request into the exact steps bindaru would run (what `--dry-run --json`
//! prints and what the uQ page previews). Pure: no process is started here.
use crate::names::check_names;
use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Who {
    /// Runs as the logged-in user.
    User,
    /// Runs in the polkit-gated root helper.
    Root,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Step {
    pub id: String,
    pub who: Who,
    pub title: String,
    pub argv: Vec<String>,
    /// The user must confirm a review before this step runs.
    pub needs_review: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Plan {
    pub action: &'static str,
    pub steps: Vec<Step>,
    /// Root is needed for at least one step (one password prompt for the whole plan).
    pub needs_root: bool,
}

fn s(v: &[&str]) -> Vec<String> {
    v.iter().map(|x| x.to_string()).collect()
}

fn finish(action: &'static str, steps: Vec<Step>) -> Plan {
    let needs_root = steps.iter().any(|x| x.who == Who::Root);
    Plan {
        action,
        steps,
        needs_root,
    }
}

/// Install repo packages (one transaction) and AUR packages (fetch, review, build as user, then
/// `pacman -U` in the helper). AUR builds never run as root.
pub fn install(repo: &[String], aur: &[String]) -> Result<Plan, String> {
    check_names(repo)?;
    check_names(aur)?;
    if repo.is_empty() && aur.is_empty() {
        return Err("nothing to install".into());
    }
    let mut steps = Vec::new();
    if !repo.is_empty() {
        let mut argv = s(&["/usr/bin/pacman", "-S", "--needed", "--noconfirm", "--"]);
        argv.extend(repo.iter().cloned());
        steps.push(Step {
            id: "repo-install".into(),
            who: Who::Root,
            title: format!("Install {}", repo.join(", ")),
            argv,
            needs_review: false,
        });
    }
    for p in aur {
        let url = format!("https://aur.archlinux.org/{p}.git");
        steps.push(Step {
            id: format!("fetch-{p}"),
            who: Who::User,
            title: format!("Download the build recipe for {p}"),
            argv: s(&[
                "/usr/bin/git",
                "clone",
                "--depth",
                "1",
                "--",
                &url,
                &format!("<cache>/{p}"),
            ]),
            needs_review: false,
        });
        steps.push(Step {
            id: format!("review-{p}"),
            who: Who::User,
            title: format!("Review {p}'s PKGBUILD"),
            argv: vec![],
            needs_review: true,
        });
        steps.push(Step {
            id: format!("build-{p}"),
            who: Who::User,
            title: format!("Build {p}"),
            argv: s(&["/usr/bin/makepkg", "--syncdeps", "--noconfirm", "--needed"]),
            needs_review: false,
        });
        steps.push(Step {
            id: format!("install-{p}"),
            who: Who::Root,
            title: format!("Install the built {p}"),
            argv: s(&[
                "/usr/bin/pacman",
                "-U",
                "--noconfirm",
                "--",
                &format!("<cache>/{p}/*.pkg.tar.zst"),
            ]),
            needs_review: false,
        });
    }
    Ok(finish("install", steps))
}

/// Remove packages with their now-unneeded dependencies and their own config (`-Rns`).
pub fn remove(names: &[String]) -> Result<Plan, String> {
    check_names(names)?;
    if names.is_empty() {
        return Err("nothing to remove".into());
    }
    let mut argv = s(&["/usr/bin/pacman", "-Rns", "--noconfirm", "--"]);
    argv.extend(names.iter().cloned());
    Ok(finish(
        "remove",
        vec![Step {
            id: "remove".into(),
            who: Who::Root,
            title: format!("Remove {}", names.join(", ")),
            argv,
            needs_review: false,
        }],
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn v(a: &[&str]) -> Vec<String> {
        a.iter().map(|x| x.to_string()).collect()
    }
    #[test]
    fn repo_install_is_one_root_transaction() {
        let p = install(&v(&["htop", "btop"]), &[]).unwrap();
        assert_eq!(p.steps.len(), 1);
        assert!(p.needs_root);
        assert_eq!(p.steps[0].argv.last().unwrap(), "btop");
        assert!(p.steps[0].argv.contains(&"--".to_string()));
    }
    #[test]
    fn aur_builds_as_user_and_review_precedes_build() {
        let p = install(&[], &v(&["paru-bin"])).unwrap();
        let ids: Vec<_> = p.steps.iter().map(|s| s.id.as_str()).collect();
        assert_eq!(
            ids,
            [
                "fetch-paru-bin",
                "review-paru-bin",
                "build-paru-bin",
                "install-paru-bin"
            ]
        );
        assert!(
            p.steps
                .iter()
                .filter(|s| s.argv.iter().any(|a| a.ends_with("makepkg")))
                .all(|s| s.who == Who::User)
        );
        assert!(p.steps[1].needs_review);
    }
    #[test]
    fn bad_names_never_reach_argv() {
        assert!(install(&v(&["--overwrite=*"]), &[]).is_err());
        assert!(remove(&v(&["a;b"])).is_err());
        assert!(install(&[], &[]).is_err());
    }
}
