use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Source {
    /// A pacman sync repository (core, extra, multilib, ...).
    Repo,
    Aur,
}

/// One package as the store shows it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Package {
    pub name: String,
    pub version: String,
    /// Repository name, or "aur".
    pub repo: String,
    pub source: Source,
    pub description: String,
    pub installed: bool,
    pub url: Option<String>,
    pub licenses: Vec<String>,
    pub depends: Vec<String>,
    pub download_size: Option<String>,
    pub installed_size: Option<String>,
}

impl Package {
    pub fn new(name: &str, version: &str, repo: &str) -> Self {
        Package {
            name: name.into(),
            version: version.into(),
            repo: repo.into(),
            source: if repo == "aur" {
                Source::Aur
            } else {
                Source::Repo
            },
            description: String::new(),
            installed: false,
            url: None,
            licenses: vec![],
            depends: vec![],
            download_size: None,
            installed_size: None,
        }
    }
}
