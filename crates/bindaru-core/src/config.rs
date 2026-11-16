//! `~/.config/bindaru/config.toml`: validated keys only, `config show|set` of the shared CLI contract.
//! Every key is a bool or one of a fixed set of words, so `config set` can check each value.
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct Config {
    // ---- the AUR
    /// Search and install from the AUR at all.
    pub aur_enabled: bool,
    /// Show a PKGBUILD diff for updates of packages already installed from the AUR.
    pub aur_update_diff: bool,
    /// Offer AUR packages that are orphaned or flagged out of date in search results.
    pub aur_show_risky: bool,
    // ---- how the app list looks
    /// "list", "grid" or "compact".
    pub view: String,
    /// "name", "size", "version", "repo" or "popularity".
    pub sort: String,
    pub sort_descending: bool,
    /// "none", "repo" or "source" (repositories and the AUR).
    pub group_by: String,
    /// "comfortable" or "compact".
    pub density: String,
    /// Show the inspector (details) beside the list when a package is selected.
    pub show_inspector: bool,
    /// "name" or "name-description".
    pub search_in: String,
    /// "all", "installed", "repos" or "aur": what the main view starts on.
    pub start_filter: String,
    // ---- behaviour
    /// Ask before removing, even for one package.
    pub confirm_removals: bool,
    /// Also show packages that other packages only needed (dependencies) in the installed list.
    pub show_dependencies: bool,
    // ---- oysterAV
    /// Scan new installs with oysterAV: "off", "aur" (AUR builds only) or "all".
    pub scan_installs: String,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            aur_enabled: true,
            aur_update_diff: true,
            aur_show_risky: true,
            view: "list".into(),
            sort: "name".into(),
            sort_descending: false,
            group_by: "none".into(),
            density: "comfortable".into(),
            show_inspector: true,
            search_in: "name-description".into(),
            start_filter: "all".into(),
            confirm_removals: true,
            show_dependencies: false,
            scan_installs: "aur".into(),
        }
    }
}

enum Kind {
    Bool,
    Words(&'static [&'static str]),
}

const KEYS: &[(&str, Kind)] = &[
    ("aur_enabled", Kind::Bool),
    ("aur_update_diff", Kind::Bool),
    ("aur_show_risky", Kind::Bool),
    ("view", Kind::Words(&["list", "grid", "compact"])),
    (
        "sort",
        Kind::Words(&["name", "size", "version", "repo", "popularity"]),
    ),
    ("sort_descending", Kind::Bool),
    ("group_by", Kind::Words(&["none", "repo", "source"])),
    ("density", Kind::Words(&["comfortable", "compact"])),
    ("show_inspector", Kind::Bool),
    ("search_in", Kind::Words(&["name", "name-description"])),
    (
        "start_filter",
        Kind::Words(&["all", "installed", "repos", "aur"]),
    ),
    ("confirm_removals", Kind::Bool),
    ("show_dependencies", Kind::Bool),
    ("scan_installs", Kind::Words(&["off", "aur", "all"])),
];

pub fn key_names() -> Vec<&'static str> {
    KEYS.iter().map(|(k, _)| *k).collect()
}

impl Config {
    pub fn parse(text: &str) -> Result<Config, String> {
        let c: Config = toml::from_str(text).map_err(|e| format!("config: {e}"))?;
        // A hand-edited file gets the same checks as `config set`.
        let mut checked = Config::default();
        for k in key_names() {
            checked.set(k, &c.get(k).expect("known key"))?;
        }
        Ok(checked)
    }

    pub fn to_toml(&self) -> String {
        toml::to_string_pretty(self).expect("config serializes")
    }

    pub fn get(&self, key: &str) -> Option<String> {
        Some(match key {
            "aur_enabled" => self.aur_enabled.to_string(),
            "aur_update_diff" => self.aur_update_diff.to_string(),
            "aur_show_risky" => self.aur_show_risky.to_string(),
            "view" => self.view.clone(),
            "sort" => self.sort.clone(),
            "sort_descending" => self.sort_descending.to_string(),
            "group_by" => self.group_by.clone(),
            "density" => self.density.clone(),
            "show_inspector" => self.show_inspector.to_string(),
            "search_in" => self.search_in.clone(),
            "start_filter" => self.start_filter.clone(),
            "confirm_removals" => self.confirm_removals.to_string(),
            "show_dependencies" => self.show_dependencies.to_string(),
            "scan_installs" => self.scan_installs.clone(),
            _ => return None,
        })
    }

    /// There is deliberately no key that turns the AUR review gate off.
    pub fn set(&mut self, key: &str, value: &str) -> Result<(), String> {
        let Some((_, kind)) = KEYS.iter().find(|(k, _)| *k == key) else {
            return Err(format!(
                "unknown key {key:?}; known: {}",
                key_names().join(", ")
            ));
        };
        let b = match kind {
            Kind::Bool => Some(
                value
                    .parse::<bool>()
                    .map_err(|_| format!("{key} takes true or false, not {value:?}"))?,
            ),
            Kind::Words(w) if w.contains(&value) => None,
            Kind::Words(w) => {
                return Err(format!(
                    "{key} takes one of {}, not {value:?}",
                    w.join(", ")
                ));
            }
        };
        let s = value.to_string();
        match key {
            "aur_enabled" => self.aur_enabled = b.unwrap(),
            "aur_update_diff" => self.aur_update_diff = b.unwrap(),
            "aur_show_risky" => self.aur_show_risky = b.unwrap(),
            "sort_descending" => self.sort_descending = b.unwrap(),
            "show_inspector" => self.show_inspector = b.unwrap(),
            "confirm_removals" => self.confirm_removals = b.unwrap(),
            "show_dependencies" => self.show_dependencies = b.unwrap(),
            "view" => self.view = s,
            "sort" => self.sort = s,
            "group_by" => self.group_by = s,
            "density" => self.density = s,
            "search_in" => self.search_in = s,
            "start_filter" => self.start_filter = s,
            "scan_installs" => self.scan_installs = s,
            _ => unreachable!("every key is handled above"),
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
        c.set("sort", "size").unwrap();
        assert_eq!(Config::parse(&c.to_toml()).unwrap(), c);
        assert_eq!(c.get("sort").as_deref(), Some("size"));
    }
    #[test]
    fn rejects_bad_input() {
        let mut c = Config::default();
        assert!(c.set("aur_enabled", "maybe").is_err());
        assert!(c.set("sort", "random").is_err());
        assert!(c.set("review_required", "false").is_err());
        assert!(Config::parse("review_required = false").is_err());
        assert!(Config::parse("view = \"cube\"").is_err());
    }
    #[test]
    fn every_key_has_a_default_that_validates() {
        let c = Config::default();
        for k in key_names() {
            let mut d = Config::default();
            d.set(k, &c.get(k).unwrap()).unwrap();
        }
    }
}
