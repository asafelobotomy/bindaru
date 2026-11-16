use bindaru_core::config::Config;
use std::path::PathBuf;

fn path() -> Result<PathBuf, String> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
        .ok_or("no HOME or XDG_CONFIG_HOME")?;
    Ok(base.join("bindaru/config.toml"))
}

pub fn load() -> Result<Config, String> {
    match std::fs::read_to_string(path()?) {
        Ok(t) => Config::parse(&t),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(Config::default()),
        Err(e) => Err(e.to_string()),
    }
}

pub fn save(c: &Config) -> Result<(), String> {
    let p = path()?;
    std::fs::create_dir_all(p.parent().expect("has parent")).map_err(|e| e.to_string())?;
    std::fs::write(&p, c.to_toml()).map_err(|e| format!("{}: {e}", p.display()))
}
