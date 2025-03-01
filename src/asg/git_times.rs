use std::path::Path;

use chrono::{DateTime, Local, TimeZone};

#[derive(Default)]
pub struct Commit {
    pub hash: String,
    pub message: String,
    pub author: String,
    pub date: String,
}

pub type BlameInfo = Vec<Commit>;

fn rest_after_space(s: &str) -> String {
    match s.find(' ') {
        Some(pos) => s[pos + 1..].trim().to_string(),
        None => String::new(),
    }
}

fn parse_commits(output: &str) -> BlameInfo {
    let mut lines = output.lines();
    let mut blame_info = vec![];
    let mut current_commit = Commit::default();
    loop {
        let Some(l) = lines.next() else {
            break;
        };

        if l.starts_with("commit") {
            let hash = rest_after_space(l);
            current_commit.hash = hash;
        } else if l.starts_with("Author: ") {
            let author = rest_after_space(l);
            current_commit.author = author;
        } else if l.starts_with("Date: ") {
            let date = rest_after_space(l);
            current_commit.date = date;
        } else if l.is_empty() {
            let mut m = String::new();
            loop {
                let Some(next_line) = lines.next() else {
                    break;
                };
                if next_line.is_empty() {
                    break;
                }
                m.push_str(next_line.trim());
            }
            current_commit.message = m;
            blame_info.push(current_commit);
            current_commit = Commit::default();
        }
    }
    blame_info
}

pub fn git_blame(path: &Path) -> BlameInfo {
    if !path.exists() {
        return vec![];
    }
    let Some(parent_folder) = path.parent() else {
        return vec![];
    };
    let Some(filename) = path.file_name() else {
        return vec![];
    };
    let output = std::process::Command::new("git")
        .arg("log")
        .arg("--follow")
        .arg(filename)
        .current_dir(parent_folder)
        .output()
        .expect("Failed to execute git log --follow");
    let output = String::from_utf8_lossy(&output.stdout).to_string();
    parse_commits(&output)
}

fn parse_date(s: &str) -> DateTime<Local> {
    let format = "%a %b %e %H:%M:%S %Y %z";
    let date = chrono::NaiveDateTime::parse_from_str(s, format).unwrap_or_default();
    Local
        .from_local_datetime(&date)
        .earliest()
        .unwrap_or_default()
}

pub fn get_git_modification_time(bi: &BlameInfo) -> DateTime<Local> {
    if bi.is_empty() {
        // If the file is not in Git, it is new.
        return std::time::SystemTime::now().into();
    }
    let date_string = &bi[0].date;
    parse_date(date_string)
}

pub fn get_git_creation_time(bi: &BlameInfo) -> DateTime<Local> {
    if bi.is_empty() {
        // If the file is not in Git, it is new.
        return std::time::SystemTime::now().into();
    }
    let date_string = &bi[bi.len() - 1].date;
    parse_date(date_string)
}

#[cfg(test)]
mod tests {
    use chrono::{Datelike, Timelike};

    use super::*;

    #[test]
    fn test_parse_date() {
        let date = parse_date("Fri Nov 1 14:07:05 2024 +0100");
        assert_eq!(date.year(), 2024);
        assert_eq!(date.month(), 11);
        assert_eq!(date.day(), 1);
        assert_eq!(date.hour(), 14);
        assert_eq!(date.minute(), 7);
        assert_eq!(date.second(), 5);
    }

    #[test]
    fn test_parse_commit() {
        let commit_test = "commit c06dc8bcc5bb323a062265860cd861f7fcb95381
Author: Mr. A
Date:   Sat Feb 22 13:44:40 2025 +0100

    :bug: fix bug

commit b8ddad3380286ab14590f0c9443d6abb52969766
Author: Mr. A
Date:   Sun Feb 9 15:08:19 2025 +0100

    :bug: todo

commit 338e1177c3e4be94756d7be8b75e64ece72d6837
Author: Mr. B
Date:   Wed Nov 13 17:59:13 2024 +0100

    :memo: docs

commit 670d2faeca08c98d1768cca2c75425f3ee4ae6b8
Author: Mr. A
Date:   Fri Nov 1 22:58:48 2024 +0100

    :tada: implement feature
";
        let commits = parse_commits(commit_test);
        assert_eq!(commits.len(), 4);
        assert_eq!(commits[0].hash, "c06dc8bcc5bb323a062265860cd861f7fcb95381");
        assert_eq!(commits[0].author, "Mr. A");
        assert_eq!(commits[0].date, "Sat Feb 22 13:44:40 2025 +0100");
        assert_eq!(commits[0].message, ":bug: fix bug");
    }
}
