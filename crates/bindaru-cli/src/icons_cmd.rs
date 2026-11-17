//! `bindaru icons --json`: package name -> icon (a theme icon name, or the path of a cached AppStream
//! icon). Installed packages use their `.desktop` file's icon; the rest use AppStream's catalogue
//! when it is installed (archlinux-appstream-data).
use bindaru_core::icons;
use std::collections::BTreeMap;
use std::fs;

const LOCAL: &str = "/var/lib/pacman/local";
const CATALOGUE: &str = "/usr/share/swcatalog";

fn desktop_icons() -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    let Ok(dirs) = fs::read_dir(LOCAL) else {
        return map;
    };
    for d in dirs.flatten() {
        let dir = d.file_name().to_string_lossy().into_owned();
        let Some(name) = icons::local_pkg_name(&dir) else {
            continue;
        };
        let Ok(files) = fs::read_to_string(d.path().join("files")) else {
            continue;
        };
        for f in icons::desktop_files(&files) {
            if let Some(icon) = fs::read_to_string(format!("/{f}"))
                .ok()
                .and_then(|t| icons::desktop_icon(&t))
            {
                map.entry(name.to_string()).or_insert(icon);
                break;
            }
        }
    }
    map
}

fn catalogue_icons() -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    let Ok(files) = fs::read_dir(format!("{CATALOGUE}/xml")) else {
        return map;
    };
    for f in files.flatten() {
        let path = f.path();
        let text = match path.extension().and_then(|e| e.to_str()) {
            Some("gz") => crate::sys::unzip(&path.to_string_lossy()).ok(),
            Some("xml") => fs::read_to_string(&path).ok(),
            _ => None,
        };
        if let Some(t) = text {
            for (k, v) in icons::appstream_icons(&t, &format!("{CATALOGUE}/icons")) {
                map.entry(k).or_insert(v);
            }
        }
    }
    map
}

/// Every themed application icon on disk, by name (the best file for a 64px thumbnail).
fn theme_index() -> BTreeMap<String, String> {
    let mut best: BTreeMap<String, (u32, String)> = BTreeMap::new();
    let mut todo = vec![(std::path::PathBuf::from("/usr/share/icons"), 0)];
    while let Some((dir, depth)) = todo.pop() {
        let Ok(entries) = fs::read_dir(&dir) else {
            continue;
        };
        for e in entries.flatten() {
            let path = e.path();
            if path.is_dir() {
                if depth < 6 {
                    todo.push((path, depth + 1));
                }
            } else if let Some(p) = path.to_str()
                && let Some((name, score)) = icons::icon_file(p)
                && best.get(name).is_none_or(|(s, _)| score > *s)
            {
                best.insert(name.to_string(), (score, p.to_string()));
            }
        }
    }
    let pix = fs::read_dir("/usr/share/pixmaps")
        .into_iter()
        .flatten()
        .flatten();
    for e in pix {
        let p = e.path();
        if let (Some(stem), Some("png" | "svg")) = (
            p.file_stem().and_then(|s| s.to_str()),
            p.extension().and_then(|s| s.to_str()),
        ) {
            best.entry(stem.to_string())
                .or_insert((1, p.to_string_lossy().into_owned()));
        }
    }
    best.into_iter().map(|(k, (_, v))| (k, v)).collect()
}

/// Package name -> the path of an icon file that exists. Installed packages use their desktop
/// file's icon, others the AppStream catalogue's; `names` (search results) with neither are
/// tried as icon names, so "vlc" finds the icon called vlc.
pub fn resolve(names: &[String]) -> BTreeMap<String, String> {
    let index = theme_index();
    let mut found: BTreeMap<String, String> = BTreeMap::new();
    let mut put = |pkg: &str, icon: &str| {
        let path = if icon.starts_with('/') {
            std::path::Path::new(icon)
                .is_file()
                .then(|| icon.to_string())
        } else {
            index.get(icon).cloned()
        };
        if let Some(p) = path {
            found.entry(pkg.to_string()).or_insert(p);
        }
    };
    for (pkg, icon) in desktop_icons() {
        put(&pkg, &icon);
    }
    for (pkg, icon) in catalogue_icons() {
        put(&pkg, &icon);
    }
    for n in names {
        for guess in icons::name_guesses(n) {
            put(n, guess);
        }
    }
    found
}
