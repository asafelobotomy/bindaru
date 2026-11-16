//! The planner: turns a request into the exact steps bindaru would run (what `--dry-run --json`
//! prints and what the uQ page previews). Pure: no process is started here.
use crate::names::check_names;
use crate::protocol::Request;
use crate::repos::{self, NewRepo};
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
    /// What the root helper is asked to do, for root steps that go to it as one request.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub request: Option<Request>,
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
            request: Some(Request::Install {
                names: repo.to_vec(),
            }),
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
            request: None,
        });
        steps.push(Step {
            id: format!("review-{p}"),
            who: Who::User,
            title: format!("Review {p}'s PKGBUILD"),
            argv: vec![],
            needs_review: true,
            request: None,
        });
        steps.push(Step {
            id: format!("build-{p}"),
            who: Who::User,
            title: format!("Build {p}"),
            argv: s(&["/usr/bin/makepkg", "--syncdeps", "--noconfirm", "--needed"]),
            needs_review: false,
            request: None,
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
            request: None,
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
            request: Some(Request::Remove {
                names: names.to_vec(),
            }),
        }],
    ))
}

fn repo_step(id: &str, title: String, request: Request) -> Step {
    Step {
        id: id.into(),
        who: Who::Root,
        title,
        argv: vec![],
        needs_review: false,
        request: Some(request),
    }
}

/// Add a repository (and, when given, trust its signing key), then refresh the databases.
pub fn add_repo(r: &NewRepo, key: Option<&str>, existing: &[repos::Repo]) -> Result<Plan, String> {
    repos::check_new(r, existing)?;
    let mut steps = Vec::new();
    if let Some(k) = key {
        repos::check_fingerprint(k)?;
        steps.push(repo_step(
            "repo-key",
            format!("Trust key {k} for {}", r.name),
            Request::TrustKey {
                fingerprint: k.into(),
            },
        ));
    }
    steps.push(repo_step(
        "repo-add",
        format!("Add the repository {}", r.name),
        Request::AddRepo {
            name: r.name.clone(),
            server: r.server.clone(),
        },
    ));
    steps.push(repo_step(
        "repo-sync",
        "Refresh the package databases".into(),
        Request::Sync,
    ));
    Ok(finish("add-repo", steps))
}

pub fn remove_repo(name: &str) -> Result<Plan, String> {
    if !repos::is_repo_name(name) {
        return Err(format!("not a valid repository name: {name:?}"));
    }
    Ok(finish(
        "remove-repo",
        vec![
            repo_step(
                "repo-remove",
                format!("Remove the repository {name}"),
                Request::RemoveRepo { name: name.into() },
            ),
            repo_step(
                "repo-sync",
                "Refresh the package databases".into(),
                Request::Sync,
            ),
        ],
    ))
}

pub fn set_official_repo(name: &str, enabled: bool) -> Result<Plan, String> {
    if !repos::OFFICIAL_OPTIONAL.contains(&name) {
        return Err(format!("{name} can't be switched here"));
    }
    let verb = if enabled { "Turn on" } else { "Turn off" };
    Ok(finish(
        "set-repo",
        vec![
            repo_step(
                "repo-official",
                format!("{verb} {name}"),
                Request::SetOfficialRepo {
                    name: name.into(),
                    enabled,
                },
            ),
            repo_step(
                "repo-sync",
                "Refresh the package databases".into(),
                Request::Sync,
            ),
        ],
    ))
}

/// The packages an install plan installs, as (name, from_aur).
pub fn installed_by(plan: &Plan) -> Vec<(String, bool)> {
    let mut v = Vec::new();
    for step in &plan.steps {
        if let Some(Request::Install { names }) = &step.request {
            v.extend(names.iter().map(|n| (n.clone(), false)));
        } else if let Some(n) = step.id.strip_prefix("install-") {
            v.push((n.to_string(), true));
        }
    }
    v
}

/// One line of the confirmation sheet (the uQ settings-page preview document).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Change {
    pub group: String,
    pub label: String,
    pub detail: String,
    pub reversible: bool,
}

/// What `--dry-run --json` prints: the uQ preview document, plus the exact steps.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Preview {
    pub summary: String,
    pub changes: Vec<Change>,
    pub would_refuse: bool,
    pub reason: String,
    pub plan: Plan,
}

fn names_of(step: &Step) -> Vec<String> {
    let skip = if step.id == "remove" { 4 } else { 5 };
    step.argv.iter().skip(skip).cloned().collect()
}

pub fn preview(plan: &Plan) -> Preview {
    let mut changes = Vec::new();
    for step in &plan.steps {
        let ch = |group: &str, label: &str, detail: &str, reversible| Change {
            group: group.into(),
            label: label.into(),
            detail: detail.into(),
            reversible,
        };
        if step.id == "repo-install" {
            changes.extend(names_of(step).iter().map(|n| {
                ch(
                    "Installed from the repositories",
                    n,
                    "and the packages it needs",
                    true,
                )
            }));
        } else if step.id == "remove" {
            changes.extend(names_of(step).iter().map(|n| {
                ch(
                    "Removed",
                    n,
                    "with its settings and any packages nothing else needs",
                    true,
                )
            }));
        } else if step.id.starts_with("repo-")
            && step.id != "repo-install"
            && step.id != "repo-sync"
        {
            let reversible = step.id != "repo-key";
            let detail = if step.id == "repo-key" {
                "lets packages signed with this key install without a warning"
            } else {
                "pacman.conf is backed up first"
            };
            changes.push(ch("Repositories", &step.title, detail, reversible));
        } else if let Some(n) = step.id.strip_prefix("install-") {
            changes.push(ch(
                "Built from the AUR and installed",
                n,
                "built as you from a recipe you reviewed",
                true,
            ));
        }
    }
    let summary = match changes.len() {
        1 => "1 change".to_string(),
        n => format!("{n} changes"),
    };
    Preview {
        summary,
        changes,
        would_refuse: false,
        reason: String::new(),
        plan: plan.clone(),
    }
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
    #[test]
    fn preview_lists_each_package() {
        let p = preview(&install(&v(&["htop"]), &v(&["paru-bin"])).unwrap());
        assert_eq!(p.changes.len(), 2);
        assert_eq!(p.changes[1].group, "Built from the AUR and installed");
        let r = preview(&remove(&v(&["htop", "btop"])).unwrap());
        assert_eq!(r.summary, "2 changes");
        assert!(!r.would_refuse);
    }
}
