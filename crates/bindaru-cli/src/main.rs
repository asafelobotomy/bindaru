//! `bindaru`: the CLI of the pacman and AUR store. Follows the uQ app contract:
//! `config show|set`, `--dry-run --json`, `--ndjson` (one JSON event per line).
mod cfg;
mod exec;
mod helper;
mod sys;

use bindaru_core::{config::Config, plan, review};
use clap::{Parser, Subcommand};
use std::process::ExitCode;

#[derive(Parser)]
#[command(name = "bindaru", version, about = "pacman and AUR package store")]
struct Cli {
    /// Print JSON instead of text.
    #[arg(long, global = true)]
    json: bool,
    /// Print one JSON event per line (progress-friendly).
    #[arg(long, global = true)]
    ndjson: bool,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Search the repositories and, unless disabled, the AUR.
    Search {
        query: String,
        #[arg(long)]
        no_aur: bool,
    },
    /// Show one package.
    Info { name: String },
    /// List installed packages.
    Installed,
    /// Review a PKGBUILD file offline: findings, and a diff when --old is given.
    Review {
        /// A PKGBUILD file; or use --aur.
        pkgbuild: Option<String>,
        #[arg(long)]
        old: Option<String>,
        /// Download this AUR package's recipe and review it; prints the hash for `install --ack`.
        #[arg(long)]
        aur: Option<String>,
    },
    /// Root helper (started by pkexec; not for direct use).
    #[command(hide = true)]
    Helper,
    /// Install packages (AUR ones go through the review gate).
    Install {
        names: Vec<String>,
        #[arg(long)]
        aur: bool,
        #[arg(long)]
        dry_run: bool,
        /// Hash printed by `review --aur`: confirms you read exactly that recipe.
        #[arg(long)]
        ack: Option<String>,
    },
    /// Remove packages and their unneeded dependencies.
    Remove {
        names: Vec<String>,
        #[arg(long)]
        dry_run: bool,
    },
    /// Show or change settings.
    Config {
        #[command(subcommand)]
        action: ConfigCmd,
    },
}

#[derive(Subcommand)]
enum ConfigCmd {
    Show,
    Set { key: String, value: String },
}

fn emit(v: &impl serde::Serialize) {
    println!("{}", serde_json::to_string(v).expect("serializes"));
}

fn run(cli: Cli) -> Result<(), exec::Failure> {
    let cfg = cfg::load()?;
    match cli.cmd {
        Cmd::Config {
            action: ConfigCmd::Show,
        } => {
            if cli.json {
                emit(&cfg)
            } else {
                print!("{}", cfg.to_toml())
            }
        }
        Cmd::Config {
            action: ConfigCmd::Set { key, value },
        } => {
            let mut c: Config = cfg;
            c.set(&key, &value)?;
            cfg::save(&c)?;
            if cli.json {
                emit(&c)
            } else {
                println!("{key} = {value}")
            }
        }
        Cmd::Search { query, no_aur } => {
            let mut found = sys::search_repo(&query)?;
            if cfg.aur_enabled && !no_aur {
                found.extend(sys::search_aur(&query)?);
            }
            if cli.json || cli.ndjson {
                if cli.ndjson {
                    found.iter().for_each(emit)
                } else {
                    emit(&found)
                }
            } else {
                for p in &found {
                    println!(
                        "{}/{} {}{}\n    {}",
                        p.repo,
                        p.name,
                        p.version,
                        if p.installed { " [installed]" } else { "" },
                        p.description
                    );
                }
            }
        }
        Cmd::Info { name } => {
            let p = sys::info(&name)?;
            if cli.json {
                emit(&p)
            } else {
                println!("{}/{} {}\n{}", p.repo, p.name, p.version, p.description)
            }
        }
        Cmd::Installed => {
            let v = sys::installed()?;
            if cli.json {
                emit(&v)
            } else {
                v.iter().for_each(|p| println!("{} {}", p.name, p.version))
            }
        }
        Cmd::Helper => helper::main()?,
        Cmd::Review { pkgbuild, old, aur } => {
            let read = |p: &str| std::fs::read_to_string(p).map_err(|e| format!("{p}: {e}"));
            let (name, new, hash) = match (&pkgbuild, &aur) {
                (Some(f), None) => (f.clone(), read(f)?, None),
                (None, Some(pkg)) => {
                    bindaru_core::names::check_names(std::slice::from_ref(pkg))?;
                    let (hash, text, _) = exec::recipe_hash(&exec::fetch(pkg)?)?;
                    (pkg.clone(), text, Some(hash))
                }
                _ => return Err("give a PKGBUILD file or --aur <package>".to_string().into()),
            };
            let old = old.as_deref().map(read).transpose()?;
            let r = review::review(&name, &new, old.as_deref());
            if cli.json {
                emit(&serde_json::json!({"review": r, "hash": hash}))
            } else {
                if let Some(h) = &hash {
                    println!("Recipe hash (pass to `install --ack`): {h}");
                }
                for f in &r.findings {
                    println!(
                        "{:?} line {}: {}\n    {}",
                        f.severity, f.line, f.text, f.snippet
                    )
                }
                for d in &r.diff {
                    println!("{} {}", d.tag, d.text)
                }
                if r.findings.is_empty() {
                    println!("No findings. You still have to read it.")
                }
            }
        }
        Cmd::Install {
            names,
            aur,
            dry_run,
            ack,
        } => {
            let (repo, aur_names) = if aur {
                (vec![], names)
            } else {
                (names, vec![])
            };
            let p = plan::install(&repo, &aur_names)?;
            do_plan(&cli.json, &cli.ndjson, dry_run, ack, &p)?;
        }
        Cmd::Remove { names, dry_run } => {
            let p = plan::remove(&names)?;
            do_plan(&cli.json, &cli.ndjson, dry_run, None, &p)?;
        }
    }
    Ok(())
}

fn do_plan(
    json: &bool,
    ndjson: &bool,
    dry_run: bool,
    ack: Option<String>,
    p: &plan::Plan,
) -> Result<(), exec::Failure> {
    if !dry_run {
        return exec::run(
            p,
            &exec::Opts {
                ndjson: *ndjson,
                ack,
            },
        );
    }
    if *ndjson {
        p.steps.iter().for_each(emit);
    } else if *json {
        emit(&plan::preview(p));
    } else {
        for s in &p.steps {
            let who = if s.who == plan::Who::Root {
                "root"
            } else {
                "you "
            };
            println!(
                "[{who}] {}{}",
                s.title,
                if s.needs_review {
                    "  (needs your review)"
                } else {
                    ""
                }
            );
        }
    }
    Ok(())
}

fn main() -> ExitCode {
    match run(Cli::parse()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(exec::Failure::ReviewRequired) => ExitCode::from(exec::REVIEW_REQUIRED),
        Err(exec::Failure::Msg(e)) => {
            eprintln!("bindaru: {e}");
            ExitCode::FAILURE
        }
    }
}
