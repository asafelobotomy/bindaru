//! The QML-facing `Backend`: runs `bindaru` (the CLI next to this binary, else on PATH) on worker
//! threads and answers by signals, the way uQ's `ctx.command` does. The window holds no logic of
//! its own about packages: everything it knows comes from the CLI's JSON.

use std::io::{BufRead, BufReader};
use std::pin::Pin;
use std::process::{Command, Stdio};

use cxx_qt::Threading;
use cxx_qt_lib::QString;

use crate::theme;

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    #[auto_cxx_name]
    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(QString, theme_json)]
        type Backend = super::BackendRust;

        /// Run `bindaru <args>` (a JSON array of strings); `done` follows with its output.
        #[qinvokable]
        fn run(self: Pin<&mut Backend>, id: &QString, args: &QString);
        /// Like `run`, with a `line` signal for each line of output as it arrives.
        #[qinvokable]
        fn stream(self: Pin<&mut Backend>, id: &QString, args: &QString);

        #[qsignal]
        fn done(self: Pin<&mut Backend>, id: QString, code: i32, out: QString, err: QString);
        #[qsignal]
        fn line(self: Pin<&mut Backend>, id: QString, text: QString);
    }

    impl cxx_qt::Threading for Backend {}
    impl cxx_qt::Initialize for Backend {}
}

use qobject::Backend;

#[derive(Default)]
pub struct BackendRust {
    theme_json: QString,
}

impl cxx_qt::Initialize for Backend {
    fn initialize(mut self: Pin<&mut Self>) {
        let path = theme::tokens_path();
        self.as_mut()
            .set_theme_json(QString::from(&theme::load(path.as_ref()).to_string()));
        let qt = self.qt_thread();
        theme::watch(path, move |tokens| {
            qt.queue(move |b| b.set_theme_json(QString::from(&tokens)))
                .is_ok()
        });
    }
}

/// The CLI: `bindaru` beside this executable, else the one on PATH.
fn cli() -> std::path::PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.join("bindaru")))
        .filter(|p| p.exists())
        .unwrap_or_else(|| "bindaru".into())
}

/// Only an array of strings is accepted as arguments; anything else runs nothing.
fn parse_args(json: &str) -> Option<Vec<String>> {
    serde_json::from_str::<Vec<String>>(json).ok()
}

impl Backend {
    fn spawn(self: Pin<&mut Self>, id: &QString, args: &QString, streaming: bool) {
        let id = id.to_string();
        let qt = self.qt_thread();
        let Some(args) = parse_args(&args.to_string()) else {
            let _ = qt.queue(move |mut b| {
                b.as_mut().done(
                    QString::from(&id),
                    2,
                    QString::from(""),
                    QString::from("bad arguments"),
                )
            });
            return;
        };
        std::thread::spawn(move || {
            let child = Command::new(cli())
                .args(&args)
                .stdin(Stdio::null())
                .stdout(Stdio::piped())
                .stderr(Stdio::piped())
                .spawn();
            let (code, out, err) = match child {
                Err(e) => (127, String::new(), format!("bindaru: {e}")),
                Ok(mut child) => {
                    let stderr = child.stderr.take().expect("piped");
                    let err_thread = std::thread::spawn(move || {
                        std::io::read_to_string(stderr).unwrap_or_default()
                    });
                    let mut out = String::new();
                    for l in BufReader::new(child.stdout.take().expect("piped"))
                        .lines()
                        .map_while(Result::ok)
                    {
                        if streaming {
                            let (id, l) = (id.clone(), l.clone());
                            if qt
                                .queue(move |mut b| {
                                    b.as_mut().line(QString::from(&id), QString::from(&l))
                                })
                                .is_err()
                            {
                                break;
                            }
                        }
                        out.push_str(&l);
                        out.push('\n');
                    }
                    let code = child.wait().ok().and_then(|s| s.code()).unwrap_or(-1);
                    (code, out, err_thread.join().unwrap_or_default())
                }
            };
            let _ = qt.queue(move |mut b| {
                b.as_mut().done(
                    QString::from(&id),
                    code,
                    QString::from(&out),
                    QString::from(&err),
                )
            });
        });
    }

    fn run(self: Pin<&mut Self>, id: &QString, args: &QString) {
        self.spawn(id, args, false);
    }

    fn stream(self: Pin<&mut Self>, id: &QString, args: &QString) {
        self.spawn(id, args, true);
    }
}

#[cfg(test)]
mod tests {
    use super::parse_args;

    #[test]
    fn only_string_arrays_are_arguments() {
        assert_eq!(
            parse_args(r#"["search","--json","htop"]"#),
            Some(vec!["search".into(), "--json".into(), "htop".into()])
        );
        for bad in ["", "{}", "[1]", r#""search""#, r#"[["a"]]"#] {
            assert_eq!(parse_args(bad), None, "{bad}");
        }
    }
}
