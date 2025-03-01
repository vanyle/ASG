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
    io::BufReader::new(handle)
        .lines()
        .map(|line| line.unwrap().split(sep).map(|s| s.to_string()).collect())
        .collect()
}

pub fn read_csv_file(file: &Path) -> Vec<Vec<String>> {
    read_csv_file_with_sep(file, ',')
}
