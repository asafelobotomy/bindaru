//! Where a package's icon comes from, with no file or process access: the caller reads the files and
//! these functions read their text. Installed packages use the icon of their `.desktop` file; others
//! use the icon AppStream cached for them, when the catalogue is installed.
use std::collections::BTreeMap;

/// The package a `/var/lib/pacman/local/<name>-<version>-<release>` directory belongs to.
pub fn local_pkg_name(dir: &str) -> Option<&str> {
    let mut it = dir.rsplitn(3, '-');
    let (_rel, _ver, name) = (it.next()?, it.next()?, it.next()?);
    (!name.is_empty()).then_some(name)
}

/// The application `.desktop` files named in a local database `files` list.
pub fn desktop_files(files: &str) -> Vec<&str> {
    files
        .lines()
        .filter(|l| l.starts_with("usr/share/applications/") && l.ends_with(".desktop"))
        .collect()
}

/// `Icon=` of an application that shows in menus; None for hidden entries and non-applications.
pub fn desktop_icon(text: &str) -> Option<String> {
    let (mut inside, mut icon, mut hidden, mut app) = (false, None, false, true);
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            inside = line == "[Desktop Entry]";
        } else if inside {
            match line.split_once('=') {
                Some(("Icon", v)) if !v.trim().is_empty() => icon = Some(v.trim().to_string()),
                Some(("NoDisplay", v)) => hidden = v.trim() == "true",
                Some(("Type", v)) => app = v.trim() == "Application",
                _ => {}
            }
        }
    }
    (app && !hidden).then_some(icon).flatten()
}

/// For a file in an icon theme (`.../apps/<name>.<ext>`): the icon's name and how good a pick it is
/// for a 64px thumbnail (a scalable one first, then the size nearest 64).
pub fn icon_file(path: &str) -> Option<(&str, u32)> {
    let (dir, file) = path.rsplit_once('/')?;
    let (name, ext) = file.rsplit_once('.')?;
    if !matches!(ext, "svg" | "png") || name.is_empty() {
        return None;
    }
    let parts: Vec<&str> = dir.split('/').collect();
    let at = parts.iter().rposition(|p| *p == "apps")?;
    if ext == "svg" || parts.contains(&"scalable") {
        return Some((name, 1000));
    }
    // hicolor: ".../48x48/apps"; breeze: ".../apps/48".
    let size = [
        parts.get(at + 1),
        at.checked_sub(1).and_then(|i| parts.get(i)),
    ]
    .into_iter()
    .flatten()
    .find_map(|p| p.split('x').next().and_then(|n| n.parse::<u32>().ok()))?;
    Some((name, 500u32.saturating_sub(size.abs_diff(64))))
}

/// What a package's name could be called as an icon: itself, then without a build suffix.
pub fn name_guesses(pkg: &str) -> Vec<&str> {
    let mut v = vec![pkg];
    for suffix in ["-bin", "-git", "-appimage", "-nightly", "-stable"] {
        if let Some(base) = pkg.strip_suffix(suffix) {
            v.push(base);
        }
    }
    v
}

fn between<'a>(s: &'a str, open: &str, close: &str) -> Option<(&'a str, &'a str)> {
    let a = s.find(open)? + open.len();
    let b = s[a..].find(close)? + a;
    Some((&s[a..b], &s[b + close.len()..]))
}

/// AppStream catalogue text -> package name to the cached icon's path under
/// `<icons>/<origin>/64x64/`. Reads the `<components origin="...">` XML by tag, which is all the
/// catalogue's generator emits for what it needs here.
pub fn appstream_icons(xml: &str, icons: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    let origin = between(xml, "origin=\"", "\"").map_or("", |(o, _)| o);
    for part in xml.split("<component").skip(1) {
        let block = part.split("</component>").next().unwrap_or(part);
        let Some((pkg, _)) = between(block, "<pkgname>", "</pkgname>") else {
            continue;
        };
        let mut rest = block;
        while let Some((_, after)) = between(rest, "<icon type=\"cached\"", ">") {
            if let Some((file, _)) = between(after, "", "</icon>")
                && !file.contains('/')
                && !file.contains("..")
                && !origin.is_empty()
            {
                out.entry(pkg.trim().to_string())
                    .or_insert_with(|| format!("{icons}/{origin}/64x64/{file}"));
                break;
            }
            rest = after;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn theme_files_rank_by_size() {
        let a = icon_file("/usr/share/icons/hicolor/48x48/apps/firefox.png").unwrap();
        let b = icon_file("/usr/share/icons/hicolor/128x128/apps/firefox.png").unwrap();
        let c = icon_file("/usr/share/icons/breeze/apps/64/firefox.svg").unwrap();
        let d = icon_file("/usr/share/icons/hicolor/scalable/apps/firefox.svg").unwrap();
        assert!(a.1 > b.1 && d.1 > a.1 && c.1 == d.1);
        assert_eq!(a.0, "firefox");
        assert!(icon_file("/usr/share/icons/hicolor/48x48/mimetypes/x.png").is_none());
        assert!(icon_file("/usr/share/icons/breeze/apps/64/x.txt").is_none());
        assert_eq!(name_guesses("paru-bin"), ["paru-bin", "paru"]);
    }

    #[test]
    fn names_from_local_dirs() {
        assert_eq!(local_pkg_name("firefox-142.0-1"), Some("firefox"));
        assert_eq!(local_pkg_name("lib32-gtk3-3.24.43-1"), Some("lib32-gtk3"));
        assert_eq!(local_pkg_name("broken"), None);
    }

    #[test]
    fn desktop_entries() {
        let d = "[Desktop Entry]\nType=Application\nName=Firefox\nIcon=firefox\n[Desktop Action x]\nIcon=nope\n";
        assert_eq!(desktop_icon(d).as_deref(), Some("firefox"));
        assert_eq!(
            desktop_icon("[Desktop Entry]\nType=Application\nNoDisplay=true\nIcon=x\n"),
            None
        );
        assert_eq!(
            desktop_files("usr/\nusr/share/applications/a.desktop\nusr/bin/a\n"),
            ["usr/share/applications/a.desktop"]
        );
    }

    #[test]
    fn appstream_cache() {
        let x = "<components origin=\"archlinux-arch-extra\" version=\"1.0\"><component type=\"desktop-application\"><id>a</id><pkgname>vlc</pkgname><icon type=\"stock\">vlc</icon><icon type=\"cached\" width=\"64\" height=\"64\">vlc_vlc.png</icon></component><component><pkgname>noicon</pkgname></component></components>";
        let m = appstream_icons(x, "/usr/share/swcatalog/icons");
        assert_eq!(
            m["vlc"],
            "/usr/share/swcatalog/icons/archlinux-arch-extra/64x64/vlc_vlc.png"
        );
        assert!(!m.contains_key("noicon"));
    }
}
