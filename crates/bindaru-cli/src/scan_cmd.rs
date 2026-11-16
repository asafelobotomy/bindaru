//! `bindaru scan`: hand installed software to oysterAV (`oyst-cli scan`), in batches.
use crate::{exec, sys};
use bindaru_core::{names::check_names, scan};
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};

pub fn run(
    names: Vec<String>,
    aur: bool,
    all: bool,
    dry_run: bool,
    json: bool,
    ndjson: bool,
) -> Result<(), exec::Failure> {
    check_names(&names)?;
    let chosen = if !names.is_empty() {
        names
    } else if aur {
        sys::foreign_names()?
    } else if all {
        sys::installed_names()?
    } else {
        return Err("say what to scan: package names, --aur or --all"
            .to_string()
            .into());
    };
    let files = sys::files_of(&chosen)?;
    let batches = scan::batches(&files);
    if dry_run {
        let doc = serde_json::json!({"packages": chosen.len(), "files": files.len(), "batches": batches.len(), "scanner": scan::OYST_CLI});
        if json || ndjson {
            println!("{doc}")
        } else {
            println!(
                "{} packages, {} files, {} batches for oysterAV",
                chosen.len(),
                files.len(),
                batches.len()
            )
        }
        return Ok(());
    }
    if !std::path::Path::new(scan::OYST_CLI).exists() {
        return Err(
            "oysterAV isn't installed (oyst-cli not found); install oysterav-security first"
                .to_string()
                .into(),
        );
    }
    let mut failed = 0;
    for (i, b) in batches.iter().enumerate() {
        let mut child = Command::new(scan::OYST_CLI)
            .args(["scan", "--ndjson"])
            .args(b)
            .stdout(Stdio::piped())
            .spawn()
            .map_err(|e| format!("oyst-cli: {e}"))?;
        for line in BufReader::new(child.stdout.take().expect("piped"))
            .lines()
            .map_while(Result::ok)
        {
            if ndjson {
                // Tag oysterAV's own events with the batch so a UI can draw overall progress.
                println!(
                    "{}",
                    serde_json::json!({"event": "scan", "batch": i + 1, "of": batches.len(), "oyst": serde_json::from_str::<serde_json::Value>(&line).unwrap_or(serde_json::Value::String(line))})
                );
            } else {
                println!("{line}");
            }
        }
        if !child.wait().map_err(|e| e.to_string())?.success() {
            failed += 1;
        }
    }
    if failed > 0 {
        Err(format!(
            "oysterAV reported a problem in {failed} of {} batches",
            batches.len()
        )
        .into())
    } else {
        Ok(())
    }
}
