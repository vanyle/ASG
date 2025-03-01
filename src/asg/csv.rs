use std::{
    fs,
    io::{self, BufRead},
    path::Path,
};

fn read_csv_file_with_sep(file: &Path, sep: char) -> Vec<Vec<String>> {
    if !file.exists() || !file.is_file() {
        return Vec::new();
    }
    let Some(handle) = fs::File::open(file).ok() else {
        return Vec::new();
    };

    let mut result = Vec::new();
    for line in io::BufReader::new(handle).lines() {
        let Ok(l) = line else {
            continue;
        };
        let row: Vec<String> = l
            .split(sep)
            .filter(|s| !s.is_empty())
            .map(String::from)
            .collect();
        if !row.is_empty() {
            result.push(row);
        }
    }
    result
}

pub fn read_csv_file(file: &Path) -> Vec<Vec<String>> {
    read_csv_file_with_sep(file, ',')
}
