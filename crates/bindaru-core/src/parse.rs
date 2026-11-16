//! Parsers for pacman's text output (`pacman -Si`, `-Qi`, `-Ss`). Run pacman with `LC_ALL=C`.
use crate::pkg::Package;

fn list(v: &str) -> Vec<String> {
    if v.trim() == "None" {
        return vec![];
    }
    v.split_whitespace().map(String::from).collect()
}

/// Parse blocks of `Key : value` lines separated by blank lines (`pacman -Si`/`-Qi`).
pub fn parse_info(text: &str, installed: bool) -> Vec<Package> {
    let mut out = Vec::new();
    for block in text.split("\n\n") {
        let (mut name, mut version, mut repo) = (None, None, String::from("local"));
        let mut p_desc = String::new();
        let (mut url, mut lic, mut dep, mut dl, mut sz) = (None, vec![], vec![], None, None);
        let mut last_key = String::new();
        for line in block.lines() {
            if let Some((k, v)) = line.split_once(" : ") {
                let (k, v) = (k.trim(), v.trim());
                last_key = k.to_string();
                match k {
                    "Repository" => repo = v.to_string(),
                    "Name" => name = Some(v.to_string()),
                    "Version" => version = Some(v.to_string()),
                    "Description" => p_desc = v.to_string(),
                    "URL" => url = (v != "None").then(|| v.to_string()),
                    "Licenses" => lic = list(v),
                    "Depends On" => dep = list(v),
                    "Download Size" => dl = Some(v.to_string()),
                    "Installed Size" => sz = Some(v.to_string()),
                    _ => {}
                }
            } else if line.starts_with(' ') && !line.trim().is_empty() {
                // Wrapped continuation of a list field.
                match last_key.as_str() {
                    "Depends On" => dep.extend(list(line)),
                    "Licenses" => lic.extend(list(line)),
                    _ => {}
                }
            }
        }
        if let (Some(n), Some(v)) = (name, version) {
            let mut p = Package::new(&n, &v, &repo);
            p.description = p_desc;
            p.installed = installed;
            p.url = url;
            p.licenses = lic;
            p.depends = dep;
            p.download_size = dl;
            p.installed_size = sz;
            out.push(p);
        }
    }
    out
}

/// Parse `pacman -Ss` output: `repo/name version [installed]` then an indented description.
pub fn parse_search(text: &str) -> Vec<Package> {
    let mut out: Vec<Package> = Vec::new();
    for line in text.lines() {
        if line.starts_with(' ') {
            if let Some(p) = out.last_mut() {
                p.description = line.trim().to_string();
            }
            continue;
        }
        let mut it = line.split_whitespace();
        let (Some(head), Some(ver)) = (it.next(), it.next()) else {
            continue;
        };
        let Some((repo, name)) = head.split_once('/') else {
            continue;
        };
        let mut p = Package::new(name, ver, repo);
        p.installed = line.contains("[installed");
        out.push(p);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    const SI: &str = "Repository      : extra\nName            : htop\nVersion         : 3.4.1-1\nDescription     : Interactive process viewer\nURL             : https://htop.dev\nLicenses        : GPL-2.0-or-later\nDepends On      : glibc  ncurses  libnl\n                  hwloc\nDownload Size   : 180.00 KiB\nInstalled Size  : 470.00 KiB\n\nRepository      : extra\nName            : btop\nVersion         : 1.4.0-1\nDescription     : A monitor\nDepends On      : None\n";
    #[test]
    fn info_blocks() {
        let v = parse_info(SI, false);
        assert_eq!(v.len(), 2);
        assert_eq!(v[0].name, "htop");
        assert_eq!(v[0].repo, "extra");
        assert_eq!(v[0].depends, ["glibc", "ncurses", "libnl", "hwloc"]);
        assert_eq!(v[0].download_size.as_deref(), Some("180.00 KiB"));
        assert!(v[1].depends.is_empty());
    }
    #[test]
    fn search_lines() {
        let t = "extra/htop 3.4.1-1 (1.0 MiB) [installed]\n    Interactive process viewer\ncore/zlib 1:1.3-1\n    Compression\n";
        let v = parse_search(t);
        assert_eq!(v.len(), 2);
        assert!(v[0].installed && !v[1].installed);
        assert_eq!(v[1].version, "1:1.3-1");
        assert_eq!(v[1].description, "Compression");
    }
}
