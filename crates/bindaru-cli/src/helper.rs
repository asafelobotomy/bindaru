//! `bindaru helper`: runs as root under pkexec. Reads one JSON request per line on stdin and
//! answers with JSON events on stdout. Every request is validated by `bindaru_core::protocol`;
//! package files are copied into a root-owned directory before `pacman -U` sees them.
use bindaru_core::protocol::{self, Event, Request};
use std::io::{BufRead, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const STAGE: &str = "/var/lib/bindaru/stage";

/// Runs a command and reports its output lines; abstracted so tests need no root or pacman.
pub trait Runner {
    fn run(&mut self, argv: &[String], out: &mut dyn FnMut(String)) -> Result<Option<i32>, String>;
}

pub struct Real;

impl Runner for Real {
    fn run(&mut self, argv: &[String], out: &mut dyn FnMut(String)) -> Result<Option<i32>, String> {
        // pacman's stderr is merged into stdout through the shell-less `2>&1` equivalent below.
        let mut child = Command::new(&argv[0])
            .args(&argv[1..])
            .env_clear()
            .env("LC_ALL", "C")
            .env("PATH", "/usr/bin")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("{}: {e}", argv[0]))?;
        let stderr = child.stderr.take().expect("piped");
        let (tx, rx) = std::sync::mpsc::channel::<String>();
        let tx2 = tx.clone();
        let t = std::thread::spawn(move || {
            std::io::BufReader::new(stderr)
                .lines()
                .map_while(Result::ok)
                .for_each(|l| {
                    let _ = tx2.send(l);
                })
        });
        let stdout = child.stdout.take().expect("piped");
        let t2 = std::thread::spawn(move || {
            std::io::BufReader::new(stdout)
                .lines()
                .map_while(Result::ok)
                .for_each(|l| {
                    let _ = tx.send(l);
                })
        });
        for l in rx {
            out(l);
        }
        let _ = (t.join(), t2.join());
        Ok(child.wait().map_err(|e| e.to_string())?.code())
    }
}

fn send(w: &mut impl Write, e: &Event) {
    let _ = writeln!(w, "{}", serde_json::to_string(e).expect("serializes"));
    let _ = w.flush();
}

/// Copy the user's package files to a root-owned directory and return the copies.
fn stage(files: &[PathBuf], stage_dir: &Path) -> Result<Vec<PathBuf>, String> {
    let _ = std::fs::remove_dir_all(stage_dir);
    std::fs::create_dir_all(stage_dir).map_err(|e| format!("{}: {e}", stage_dir.display()))?;
    let mut out = Vec::new();
    for f in files {
        let meta = std::fs::symlink_metadata(f).map_err(|e| format!("{}: {e}", f.display()))?;
        if !meta.is_file() {
            return Err(format!("{} is not a regular file", f.display()));
        }
        let dest = stage_dir.join(f.file_name().expect("checked"));
        std::fs::copy(f, &dest).map_err(|e| format!("{}: {e}", f.display()))?;
        out.push(dest);
    }
    Ok(out)
}

/// Handle one request. `uid` is the invoking user (pkexec sets `PKEXEC_UID`).
pub fn handle(
    req: &Request,
    uid: Option<u32>,
    passwd: &str,
    stage_dir: &Path,
    runner: &mut dyn Runner,
    w: &mut impl Write,
) {
    if let Request::Hello { .. } = req {
        // The handshake answers with one event and no `done`, so the stream stays in step.
        send(
            w,
            &Event::Hello {
                version: protocol::VERSION.into(),
            },
        );
        return;
    }
    let result: Result<Option<i32>, String> = (|| {
        let staged = match req {
            Request::InstallFiles { paths } => {
                let home = uid
                    .and_then(|u| protocol::passwd_home(passwd, u))
                    .ok_or("cannot tell whose files these are")?;
                stage(&protocol::check_files(paths, &home)?, stage_dir)?
            }
            _ => vec![],
        };
        let argv = protocol::argv(req, &staged)?;
        runner.run(&argv, &mut |line| send(w, &Event::Output { line }))
    })();
    match result {
        Ok(code) => send(
            w,
            &Event::Done {
                ok: code == Some(0),
                code,
            },
        ),
        Err(message) => send(w, &Event::Error { message }),
    }
}

pub fn main() -> Result<(), String> {
    let uid = std::env::var("PKEXEC_UID")
        .ok()
        .and_then(|u| u.parse().ok());
    let passwd = std::fs::read_to_string("/etc/passwd").unwrap_or_default();
    let stdin = std::io::stdin();
    let mut out = std::io::stdout();
    for line in stdin.lock().lines() {
        let line = line.map_err(|e| e.to_string())?;
        match serde_json::from_str::<Request>(&line) {
            Ok(req) => handle(&req, uid, &passwd, Path::new(STAGE), &mut Real, &mut out),
            Err(e) => send(
                &mut out,
                &Event::Error {
                    message: format!("bad request: {e}"),
                },
            ),
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fake(Vec<Vec<String>>);
    impl Runner for Fake {
        fn run(
            &mut self,
            argv: &[String],
            out: &mut dyn FnMut(String),
        ) -> Result<Option<i32>, String> {
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
}
