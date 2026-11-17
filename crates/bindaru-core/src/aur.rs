//! AUR RPC v5 answers (`/rpc/v5/info`, `/rpc/v5/search`) and the flags the review gate shows.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct AurInfo {
    pub name: String,
    pub package_base: String,
    pub version: String,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub maintainer: Option<String>,
    #[serde(default)]
    pub num_votes: u32,
    #[serde(default)]
    pub popularity: f64,
    /// Unix time the package was flagged out of date, if it was.
    #[serde(default)]
    pub out_of_date: Option<i64>,
    #[serde(default)]
    pub first_submitted: i64,
    #[serde(default)]
    pub last_modified: i64,
    #[serde(default)]
    pub depends: Vec<String>,
    #[serde(default)]
    pub make_depends: Vec<String>,
    #[serde(default)]
    pub check_depends: Vec<String>,
    #[serde(default)]
    pub opt_depends: Vec<String>,
}

#[derive(Deserialize)]
struct Reply {
    #[serde(default)]
    results: Vec<AurInfo>,
    #[serde(default)]
    error: Option<String>,
}

pub fn parse_reply(json: &str) -> Result<Vec<AurInfo>, String> {
    let r: Reply = serde_json::from_str(json).map_err(|e| format!("AUR reply: {e}"))?;
    match r.error {
        Some(e) => Err(format!("AUR error: {e}")),
        None => Ok(r.results),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "kebab-case")]
pub enum Severity {
    Info,
    Warn,
    Danger,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Flag {
    pub id: &'static str,
    pub severity: Severity,
    pub text: String,
}

const DAY: i64 = 86_400;

/// Trust signals about the package itself (not its PKGBUILD). `now` is a Unix time.
pub fn flags(a: &AurInfo, now: i64) -> Vec<Flag> {
    let mut f = Vec::new();
    let mut add = |id, severity, text: String| f.push(Flag { id, severity, text });
    if a.maintainer.is_none() {
        add(
            "orphan",
            Severity::Warn,
            "Nobody maintains this package (orphaned).".into(),
        );
    }
    if a.out_of_date.is_some() {
        add(
            "out-of-date",
            Severity::Warn,
            "Flagged out of date upstream.".into(),
        );
    }
    if now - a.first_submitted < 30 * DAY {
        add(
            "new",
            Severity::Warn,
            "Submitted less than 30 days ago.".into(),
        );
    }
    if a.num_votes < 5 && a.popularity < 0.05 {
        add(
            "unpopular",
            Severity::Warn,
            format!(
                "Few users: {} votes, popularity {:.2}.",
                a.num_votes, a.popularity
            ),
        );
    }
    if now - a.last_modified > 365 * 2 * DAY {
        add(
            "stale",
            Severity::Info,
            "Not updated for over two years.".into(),
        );
    }
    f
}

#[cfg(test)]
mod tests {
    use super::*;
    const J: &str = r#"{"version":5,"type":"multiinfo","resultcount":1,"results":[{"Name":"paru-bin","PackageBase":"paru-bin","Version":"2.0.4-1","Description":"AUR helper","Maintainer":null,"NumVotes":3,"Popularity":0.01,"OutOfDate":1700000000,"FirstSubmitted":1700000000,"LastModified":1700000500,"Depends":["git"]}]}"#;
    #[test]
    fn parses_and_flags() {
        let r = parse_reply(J).unwrap();
        assert_eq!(r[0].name, "paru-bin");
        let ids: Vec<_> = flags(&r[0], 1700000000 + DAY)
            .iter()
            .map(|f| f.id)
            .collect();
        assert_eq!(ids, ["orphan", "out-of-date", "new", "unpopular"]);
    }
    #[test]
    fn error_reply() {
        assert!(
            parse_reply(r#"{"type":"error","error":"Too many requests","results":[]}"#).is_err()
        );
    }
}
