//! Scanning installed software with oysterAV (`oyst-cli scan <paths> --ndjson`): which files
//! belong to a package, and how to hand them over in batches. Pure: no process is started here.

pub const OYST_CLI: &str = "/usr/bin/oyst-cli";
/// Paths per `oyst-cli scan` call, so no call nears the argument-size limit.
pub const BATCH: usize = 400;

/// Regular files from `pacman -Ql` output (`pkg /path`), without directories (trailing `/`).
/// Only places that hold things that run or load: bins, libs, shared data would be noise.
pub fn package_files(ql: &str) -> Vec<String> {
    ql.lines()
        .filter_map(|l| l.split_once(' ').map(|(_, p)| p.trim()))
        .filter(|p| !p.ends_with('/') && p.starts_with('/'))
        .filter(|p| {
            [
                "/usr/bin/",
                "/usr/sbin/",
                "/usr/lib/",
                "/usr/lib32/",
                "/opt/",
                "/etc/",
                "/usr/share/applications/",
            ]
            .iter()
            .any(|r| p.starts_with(r))
        })
        .map(String::from)
        .collect()
}

pub fn batches(files: &[String]) -> Vec<Vec<String>> {
    files.chunks(BATCH).map(|c| c.to_vec()).collect()
}

/// Which packages to scan: the ones from outside the repositories (`-Qm`), or everything.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Scope {
    Aur,
    All,
}

pub fn should_scan(setting: &str, from_aur: bool) -> bool {
    match setting {
        "all" => true,
        "aur" => from_aur,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn keeps_runnable_files_only() {
        let ql = "htop /usr/\nhtop /usr/bin/\nhtop /usr/bin/htop\nhtop /usr/share/doc/htop/README\nhtop /usr/lib/libx.so\nhtop /etc/htoprc\n";
        assert_eq!(
            package_files(ql),
            ["/usr/bin/htop", "/usr/lib/libx.so", "/etc/htoprc"]
        );
    }
    #[test]
    fn batches_are_bounded() {
        let files: Vec<String> = (0..BATCH * 2 + 1)
            .map(|i| format!("/usr/bin/f{i}"))
            .collect();
        let b = batches(&files);
        assert_eq!(b.len(), 3);
        assert!(b.iter().all(|c| c.len() <= BATCH));
    }
    #[test]
    fn setting_decides() {
        assert!(!should_scan("off", true));
        assert!(should_scan("aur", true) && !should_scan("aur", false));
        assert!(should_scan("all", false));
    }
}
