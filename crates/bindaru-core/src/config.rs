//! `~/.config/bindaru/config.toml`: validated keys only, `config show|set` of the shared CLI contract.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    /// Search and install from the AUR at all.
    pub aur_enabled: bool,
    /// Show a PKGBUILD diff for updates of packages already installed from the AUR.
    pub aur_update_diff: bool,
    /// Offer AUR packages that are orphaned or flagged out of date in search results.
    pub aur_show_risky: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            aur_enabled: true,
            aur_update_diff: true,
            aur_show_risky: true,
        }
    }
}

pub const KEYS: &[&str] = &["aur_enabled", "aur_update_diff", "aur_show_risky"];

impl Config {
    pub fn parse(text: &str) -> Result<Config, String> {
        toml::from_str(text).map_err(|e| format!("config: {e}"))
    }

    pub fn to_toml(&self) -> String {
        toml::to_string_pretty(self).expect("config serializes")
    }

    pub fn get(&self, key: &str) -> Option<String> {
        match key {
            "aur_enabled" => Some(self.aur_enabled.to_string()),
            "aur_update_diff" => Some(self.aur_update_diff.to_string()),
            "aur_show_risky" => Some(self.aur_show_risky.to_string()),
            _ => None,
        }
    }

    /// There is deliberately no key that turns the review gate off.
    pub fn set(&mut self, key: &str, value: &str) -> Result<(), String> {
        let b: bool = value
            .parse()
            .map_err(|_| format!("{key} takes true or false, not {value:?}"))?;
        match key {
            "aur_enabled" => self.aur_enabled = b,
            "aur_update_diff" => self.aur_update_diff = b,
            "aur_show_risky" => self.aur_show_risky = b,
            _ => return Err(format!("unknown key {key:?}; known: {}", KEYS.join(", "))),
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn roundtrip_and_set() {
        let mut c = Config::default();
        c.set("aur_enabled", "false").unwrap();
        assert_eq!(Config::parse(&c.to_toml()).unwrap(), c);
        assert_eq!(c.get("aur_enabled").as_deref(), Some("false"));
    }
    #[test]
    fn rejects_bad_input() {
        let mut c = Config::default();
        assert!(c.set("aur_enabled", "maybe").is_err());
        assert!(c.set("review_required", "false").is_err());
        assert!(Config::parse("review_required = false").is_err());
    }
}
