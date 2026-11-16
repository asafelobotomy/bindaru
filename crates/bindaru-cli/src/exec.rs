//! Runs a plan: user steps here, root steps through the helper session. AUR installs stop at
//! the review step unless `ack` is the hash of exactly the recipe that was reviewed.
use bindaru_core::plan::{Plan, Step, Who};
use bindaru_core::protocol::{BUILD_CACHE, Event, Request, VERSION};
use bindaru_core::review;
use sha2::{Digest, Sha256};
use std::io::{BufRead, BufReader, IsTerminal, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};

pub const REVIEW_REQUIRED: u8 = 3;

pub struct Opts {
    pub ndjson: bool,
    pub ack: Option<String>,
}

pub enum Failure {
    Msg(String),
    ReviewRequired,
}

impl From<String> for Failure {
    fn from(s: String) -> Self {
        Failure::Msg(s)
    }
}

struct Helper {
    child: Child,
    stdin: ChildStdin,
    out: BufReader<std::process::ChildStdout>,
}

impl Helper {
    fn start() -> Result<Helper, String> {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        let mut child = Command::new("/usr/bin/pkexec")
            .arg(exe)
            .arg("helper")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| format!("pkexec: {e}"))?;
        let stdin = child.stdin.take().expect("piped");
        let out = BufReader::new(child.stdout.take().expect("piped"));
        let mut h = Helper { child, stdin, out };
        h.request(
            &Request::Hello {
                version: VERSION.into(),
            },
            &mut |_| {},
        )?;
        Ok(h)
    }

    fn request(&mut self, req: &Request, on_out: &mut dyn FnMut(&str)) -> Result<(), String> {
        writeln!(
            self.stdin,
            "{}",
            serde_json::to_string(req).expect("serializes")
        )
        .map_err(|e| e.to_string())?;
        let mut line = String::new();
        loop {
            line.clear();
            if self.out.read_line(&mut line).map_err(|e| e.to_string())? == 0 {
                return Err("the helper stopped (was the password dialog cancelled?)".into());
            }
            match serde_json::from_str::<Event>(&line).map_err(|e| format!("helper: {e}"))? {
                Event::Hello { version } if version != VERSION => {
                    return Err(format!("helper is {version}, expected {VERSION}"));
                }
                Event::Hello { .. } => return Ok(()),
                Event::Output { line } => on_out(&line),
                Event::Done { ok: true, .. } => return Ok(()),
                Event::Done { code, .. } => return Err(format!("pacman exited with {code:?}")),
                Event::Error { message } => return Err(message),
            }
        }
    }
}

impl Drop for Helper {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn cache_dir(pkg: &str) -> Result<PathBuf, String> {
    let home = std::env::var_os("HOME").ok_or("no HOME")?;
    Ok(Path::new(&home).join(BUILD_CACHE).join(pkg))
}

fn pkg_of<'a>(step: &'a Step, prefix: &str) -> &'a str {
    step.id.strip_prefix(prefix).unwrap_or("")
}

/// Hash of everything the user must have read: the PKGBUILD and any `*.install` script.
pub fn recipe_hash(dir: &Path) -> Result<(String, String, String), String> {
    let mut text =
        std::fs::read_to_string(dir.join("PKGBUILD")).map_err(|e| format!("PKGBUILD: {e}"))?;
    let mut files: Vec<_> = std::fs::read_dir(dir)
        .map_err(|e| e.to_string())?
        .filter_map(Result::ok)
        .filter(|e| e.file_name().to_string_lossy().ends_with(".install"))
        .collect();
    files.sort_by_key(|e| e.file_name());
    for f in files {
        text.push_str(&format!(
            "\n# --- {} ---\n",
            f.file_name().to_string_lossy()
        ));
        text.push_str(&std::fs::read_to_string(f.path()).map_err(|e| e.to_string())?);
    }
    let hash = Sha256::digest(text.as_bytes())
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect();
    Ok((hash, text.clone(), text))
}

/// Download an AUR recipe fresh into the build cache; returns its folder.
pub fn fetch(pkg: &str) -> Result<PathBuf, String> {
    let dir = cache_dir(pkg)?;
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(dir.parent().expect("has parent")).map_err(|e| e.to_string())?;
    let url = format!("https://aur.archlinux.org/{pkg}.git");
    let st = Command::new("/usr/bin/git")
        .args(["clone", "--depth", "1", "--", &url])
        .arg(&dir)
        .stdout(Stdio::null())
        .status()
        .map_err(|e| format!("git: {e}"))?;
    if st.success() {
        Ok(dir)
    } else {
        Err(format!("could not download {pkg} from the AUR"))
    }
}

fn say(o: &Opts, step: &Step, state: &str, detail: &str) {
    if o.ndjson {
        println!(
            "{}",
            serde_json::json!({"event": "step", "id": step.id, "state": state, "detail": detail})
        );
    } else if state == "start" {
        println!("==> {}", step.title);
    } else if state == "output" {
        println!("    {detail}");
    }
}

fn confirm_on_tty(r: &review::Review, hash: &str) -> bool {
    if !std::io::stdin().is_terminal() {
        return false;
    }
    for f in &r.findings {
        eprintln!(
            "{:?} line {}: {}\n    {}",
            f.severity, f.line, f.text, f.snippet
        );
    }
    eprint!(
        "Review {} (recipe {}). Type the package name to install it: ",
        r.package,
        &hash[..12]
    );
    let mut a = String::new();
    std::io::stdin().read_line(&mut a).is_ok() && a.trim() == r.package
}

pub fn run(plan: &Plan, o: &Opts) -> Result<(), Failure> {
    let mut helper: Option<Helper> = None;
    for step in &plan.steps {
        say(o, step, "start", "");
        let mut out = |l: &str| say(o, step, "output", l);
        match (step.id.split('-').next().unwrap_or(""), step.who) {
            ("fetch", _) => {
                fetch(pkg_of(step, "fetch-"))?;
            }
            ("review", _) => {
                let pkg = pkg_of(step, "review-");
                let (hash, text, _) = recipe_hash(&cache_dir(pkg)?)?;
                let r = review::review(pkg, &text, None);
                if o.ack.as_deref() != Some(hash.as_str()) && !confirm_on_tty(&r, &hash) {
                    if o.ndjson {
                        println!(
                            "{}",
                            serde_json::json!({"event": "review-required", "hash": hash, "review": r})
                        );
                    } else {
                        eprintln!(
                            "bindaru: review required for {pkg}; run `bindaru review --aur {pkg}`, read it, then rerun with --ack {hash}"
                        );
                    }
                    return Err(Failure::ReviewRequired);
                }
            }
            ("build", _) => {
                if std::env::var("USER").as_deref() == Ok("root") {
                    return Err("refusing to build as root".to_string().into());
                }
                let dir = cache_dir(pkg_of(step, "build-"))?;
                let st = Command::new("/usr/bin/makepkg")
                    .args(["--syncdeps", "--noconfirm", "--needed"])
                    .current_dir(&dir)
                    .status()
                    .map_err(|e| format!("makepkg: {e}"))?;
                if !st.success() {
                    return Err("the build failed".to_string().into());
                }
            }
            ("install", Who::Root) if step.id.starts_with("install-") => {
                let dir = cache_dir(pkg_of(step, "install-"))?;
                let paths: Vec<String> = std::fs::read_dir(&dir)
                    .map_err(|e| e.to_string())?
                    .filter_map(Result::ok)
                    .map(|e| e.path())
                    .filter(|p| {
                        p.file_name()
                            .and_then(|n| n.to_str())
                            .is_some_and(bindaru_core::protocol::is_package_file)
                    })
                    .map(|p| p.display().to_string())
                    .collect();
                send(&mut helper, &Request::InstallFiles { paths }, &mut out)?;
            }
            (_, Who::Root) => {
                let req = if step.id == "remove" {
                    Request::Remove {
                        names: step.argv.iter().skip(4).cloned().collect(),
                    }
                } else {
                    Request::Install {
                        names: step.argv.iter().skip(5).cloned().collect(),
                    }
                };
                send(&mut helper, &req, &mut out)?;
            }
            _ => return Err(format!("unknown step {}", step.id).into()),
        }
        say(o, step, "done", "");
    }
    Ok(())
}

fn send(h: &mut Option<Helper>, req: &Request, out: &mut dyn FnMut(&str)) -> Result<(), String> {
    if h.is_none() {
        *h = Some(Helper::start()?);
    }
    h.as_mut().expect("started").request(req, out)
}
