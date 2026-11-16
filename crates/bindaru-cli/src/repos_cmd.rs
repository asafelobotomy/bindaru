//! `bindaru repos ...`: list, add, remove and switch repositories.
use crate::{exec, sys};
use bindaru_core::{plan, repos};
use clap::Subcommand;

#[derive(Subcommand)]
pub enum ReposCmd {
    /// List every repository: official, added by bindaru, and other.
    List,
    /// Add a repository (HTTPS, signatures required). A signing key goes with --key.
    Add {
        name: String,
        server: String,
        /// The full 40-digit fingerprint of the key that signs the repository.
        #[arg(long)]
        key: Option<String>,
        #[arg(long)]
        dry_run: bool,
    },
    /// Remove a repository bindaru added.
    Remove {
        name: String,
        #[arg(long)]
        dry_run: bool,
    },
    /// Turn an official optional repository (multilib, testing) on or off.
    Official {
        name: String,
        /// "on" or "off".
        state: String,
        #[arg(long)]
        dry_run: bool,
    },
}

pub fn run(cmd: ReposCmd, json: bool, ndjson: bool) -> Result<(), exec::Failure> {
    let (conf, dropin) = sys::read_conf();
    let existing = repos::list(&conf, &dropin);
    let (p, dry) = match cmd {
        ReposCmd::List => {
            if json {
                println!("{}", serde_json::to_string(&existing).expect("serializes"));
            } else {
                for r in &existing {
                    println!(
                        "{} {} ({})",
                        if r.enabled { "on " } else { "off" },
                        r.name,
                        r.origin
                    );
                }
            }
            return Ok(());
        }
        ReposCmd::Add {
            name,
            server,
            key,
            dry_run,
        } => (
            plan::add_repo(&repos::NewRepo { name, server }, key.as_deref(), &existing)?,
            dry_run,
        ),
        ReposCmd::Remove { name, dry_run } => {
            if !existing
                .iter()
                .any(|r| r.name == name && r.origin == "added")
            {
                return Err(format!("{name} isn't a repository bindaru added").into());
            }
            (plan::remove_repo(&name)?, dry_run)
        }
        ReposCmd::Official {
            name,
            state,
            dry_run,
        } => {
            let on = match state.as_str() {
                "on" => true,
                "off" => false,
                _ => return Err("state is on or off".to_string().into()),
            };
            (plan::set_official_repo(&name, on)?, dry_run)
        }
    };
    crate::do_plan(&json, &ndjson, dry, None, &p)
}
