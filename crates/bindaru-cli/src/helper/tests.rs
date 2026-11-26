//! Tests for the root helper: request handling, staging and editing the repositories.

use super::*;

struct Fake(Vec<Vec<String>>);
impl Runner for Fake {
    fn run(&mut self, argv: &[String], out: &mut dyn FnMut(String)) -> Result<Option<i32>, String> {
        self.0.push(argv.to_vec());
        out("working".into());
        Ok(Some(0))
    }
}

fn events(buf: &[u8]) -> Vec<Event> {
    String::from_utf8_lossy(buf)
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect()
}

#[test]
fn install_runs_validated_argv_and_streams() {
    let (mut f, mut out) = (Fake(vec![]), Vec::new());
    handle(
        &Request::Install {
            names: vec!["htop".into()],
        },
        Some(1000),
        "",
        Path::new("/nonexistent"),
        &mut f,
        &mut out,
    );
    assert_eq!(f.0[0].last().unwrap(), "htop");
    assert_eq!(
        events(&out),
        [
            Event::Output {
                line: "working".into()
            },
            Event::Done {
                ok: true,
                code: Some(0)
            }
        ]
    );
}

#[test]
fn repo_edits_keep_a_backup_and_never_write_unsigned_repos() {
    let dir = std::env::temp_dir().join(format!("bindaru-repo-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let (conf, drop) = (dir.join("pacman.conf"), dir.join("bindaru-repos.conf"));
    std::fs::write(
        &conf,
        "[options]\n\n[core]\nInclude = /m\n\n#[multilib]\n#Include = /m\n",
    )
    .unwrap();
    let add = Request::AddRepo {
        name: "mine".into(),
        server: "https://e.org/$arch".into(),
    };
    edit_repos(&add, &conf, &drop).unwrap();
    let d = std::fs::read_to_string(&drop).unwrap();
    assert!(d.contains("SigLevel = Required DatabaseRequired") && d.contains("[mine]"));
    assert!(
        std::fs::read_to_string(&conf)
            .unwrap()
            .contains("Include = /etc/pacman.d/bindaru-repos.conf")
    );
    assert!(dir.join("pacman.conf.bindaru.bak").exists());
    assert!(edit_repos(&add, &conf, &drop).is_err(), "no duplicate");
    edit_repos(
        &Request::SetOfficialRepo {
            name: "multilib".into(),
            enabled: true,
        },
        &conf,
        &drop,
    )
    .unwrap();
    assert!(
        std::fs::read_to_string(&conf)
            .unwrap()
            .contains("\n[multilib]\n")
    );
    edit_repos(
        &Request::RemoveRepo {
            name: "mine".into(),
        },
        &conf,
        &drop,
    )
    .unwrap();
    assert!(!std::fs::read_to_string(&drop).unwrap().contains("[mine]"));
    assert!(
        edit_repos(
            &Request::AddRepo {
                name: "x".into(),
                server: "http://e.org".into()
            },
            &conf,
            &drop
        )
        .is_err()
    );
    std::fs::remove_dir_all(dir).unwrap();
}

#[test]
fn trusting_a_key_needs_a_full_fingerprint() {
    let (mut f, mut out) = (Fake(vec![]), Vec::new());
    handle(
        &Request::TrustKey {
            fingerprint: "ABCD".into(),
        },
        None,
        "",
        Path::new("/x"),
        &mut f,
        &mut out,
    );
    assert!(f.0.is_empty());
    handle(
        &Request::TrustKey {
            fingerprint: "AB12".repeat(10),
        },
        None,
        "",
        Path::new("/x"),
        &mut f,
        &mut out,
    );
    assert_eq!(f.0.len(), 2);
    assert_eq!(f.0[1][1], "--lsign-key");
}

#[test]
fn hello_answers_once_without_done() {
    let (mut f, mut out) = (Fake(vec![]), Vec::new());
    handle(
        &Request::Hello {
            version: "x".into(),
        },
        None,
        "",
        Path::new("/nonexistent"),
        &mut f,
        &mut out,
    );
    assert_eq!(
        events(&out),
        [Event::Hello {
            version: protocol::VERSION.into()
        }]
    );
}

#[test]
fn bad_request_runs_nothing() {
    let (mut f, mut out) = (Fake(vec![]), Vec::new());
    handle(
        &Request::Remove {
            names: vec!["-rf".into()],
        },
        None,
        "",
        Path::new("/nonexistent"),
        &mut f,
        &mut out,
    );
    assert!(f.0.is_empty());
    assert!(matches!(events(&out)[0], Event::Error { .. }));
}

#[test]
fn files_outside_the_build_cache_are_refused_and_copies_are_made_only_for_good_ones() {
    let (mut f, mut out) = (Fake(vec![]), Vec::new());
    let passwd = "me:x:1000:1000::/home/me:/bin/sh\n";
    handle(
        &Request::InstallFiles {
            paths: vec!["/etc/shadow".into()],
        },
        Some(1000),
        passwd,
        Path::new("/nonexistent"),
        &mut f,
        &mut out,
    );
    assert!(f.0.is_empty());
    let dir = std::env::temp_dir().join(format!("bindaru-test-{}", std::process::id()));
    let build = dir.join(protocol::BUILD_CACHE).join("foo");
    std::fs::create_dir_all(&build).unwrap();
    let pkg = build.join("foo-1-1-x86_64.pkg.tar.zst");
    std::fs::write(&pkg, b"x").unwrap();
    let passwd = format!("me:x:1000:1000::{}:/bin/sh\n", dir.display());
    let (mut f, mut out) = (Fake(vec![]), Vec::new());
    let stage_dir = dir.join("stage");
    handle(
        &Request::InstallFiles {
            paths: vec![pkg.display().to_string()],
        },
        Some(1000),
        &passwd,
        &stage_dir,
        &mut f,
        &mut out,
    );
    assert_eq!(f.0[0][1], "-U");
    assert!(
        f.0[0]
            .last()
            .unwrap()
            .starts_with(stage_dir.to_str().unwrap())
    );
    std::fs::remove_dir_all(dir).unwrap();
}
