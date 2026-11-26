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

const CONF: &str = "/etc/pacman.conf";

/// Apply a repository edit to the two files. Each file is replaced atomically (write a temp file
/// beside it, then rename) after the old pacman.conf is kept as `pacman.conf.bindaru.bak`.
pub fn edit_repos(req: &Request, conf_path: &Path, dropin_path: &Path) -> Result<(), String> {
    use bindaru_core::repos::{self, NewRepo};
    let conf =
        std::fs::read_to_string(conf_path).map_err(|e| format!("{}: {e}", conf_path.display()))?;
    let dropin = std::fs::read_to_string(dropin_path).unwrap_or_default();
    let existing = repos::list(&conf, &dropin);
    let mut managed = repos::parse_dropin(&dropin);
    let mut new_conf = None;
    match req {
        Request::AddRepo { name, server } => {
            let r = NewRepo {
                name: name.clone(),
                server: server.clone(),
            };
            repos::check_new(&r, &existing)?;
            managed.push(r);
            new_conf = repos::with_include(&conf);
        }
        Request::RemoveRepo { name } => {
            let before = managed.len();
            managed.retain(|r| &r.name != name);
            if managed.len() == before {
                return Err(format!("{name} isn't a repository bindaru added"));
            }
        }
        Request::SetOfficialRepo { name, enabled } => {
            new_conf = repos::set_official(&conf, name, *enabled)?
        }
        _ => return Err("not a repository request".into()),
    }
    if !matches!(req, Request::SetOfficialRepo { .. }) {
        write_atomic(dropin_path, &repos::render_dropin(&managed))?;
    }
    if let Some(c) = new_conf {
        let bak = conf_path.with_extension("conf.bindaru.bak");
        std::fs::copy(conf_path, &bak).map_err(|e| format!("{}: {e}", bak.display()))?;
        write_atomic(conf_path, &c)?;
    }
    Ok(())
}

fn write_atomic(path: &Path, text: &str) -> Result<(), String> {
    let tmp = path.with_extension("bindaru.tmp");
    std::fs::write(&tmp, text).map_err(|e| format!("{}: {e}", tmp.display()))?;
    std::fs::rename(&tmp, path).map_err(|e| format!("{}: {e}", path.display()))
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
        if let Request::TrustKey { fingerprint } = req {
            bindaru_core::repos::check_fingerprint(fingerprint)?;
            for flag in ["--recv-keys", "--lsign-key"] {
                let argv: Vec<String> = ["/usr/bin/pacman-key", flag, fingerprint]
                    .map(String::from)
                    .to_vec();
                match runner.run(&argv, &mut |line| send(w, &Event::Output { line }))? {
                    Some(0) => {}
                    code => return Ok(code),
                }
            }
            return Ok(Some(0));
        }
        if matches!(
            req,
            Request::AddRepo { .. } | Request::RemoveRepo { .. } | Request::SetOfficialRepo { .. }
        ) {
            edit_repos(
                req,
                Path::new(CONF),
                Path::new(bindaru_core::repos::DROPIN_PATH),
            )?;
            return Ok(Some(0));
        }
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
mod tests;
