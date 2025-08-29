use std::{env, fs, io::Write, path::Path};

fn get_commit_hash(cargo_manifest_dir: &Path) -> String {
    let output = std::process::Command::new("git")
        .args(["rev-parse", "HEAD"])
        .current_dir(cargo_manifest_dir)
        .output()
        .expect("Failed to get current commit hash");
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn get_git_branch(cargo_manifest_dir: &Path) -> String {
    let output = std::process::Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .current_dir(cargo_manifest_dir)
        .output()
        .expect("Failed to get current branch");
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn get_git_tag(cargo_manifest_dir: &Path) -> String {
    let output = std::process::Command::new("git")
        .args(["tag", "--points-at", "HEAD"])
        .current_dir(cargo_manifest_dir)
        .output()
        .expect("Failed to get current tag");
    String::from_utf8_lossy(&output.stdout).trim().to_string()
}

fn main() {
    let dst = Path::new(&env::var("OUT_DIR").expect("OUT_DIR not set")).join("buildinfo.rs");

    let binding = env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR");
    let cargo_manifest_dir = Path::new(&binding);

    let mut built_file = fs::File::create(dst).unwrap();

    let current_commit_hash = get_commit_hash(cargo_manifest_dir);
    let current_branch = get_git_branch(cargo_manifest_dir);
    let current_tag = get_git_tag(cargo_manifest_dir);

    let build_timestamp = chrono::Utc::now().to_rfc2822();

    // We are generating a file that will be imported by run main program.
    let _ = built_file.write_all(
        r#"//
// EVERYTHING BELOW THIS POINT WAS AUTO-GENERATED DURING COMPILATION. DO NOT MODIFY.
//

"#
        .as_ref(),
    );
    let _ = built_file
        .write_all(format!("pub const COMMIT_HASH: &str = \"{current_commit_hash}\";").as_ref());
    let _ = built_file
        .write_all(format!("pub const BRANCH_NAME: &str = \"{current_branch}\";").as_ref());
    let _ = built_file.write_all(format!("pub const TAG_NAME: &str = \"{current_tag}\";").as_ref());

    let _ = built_file
        .write_all(format!("pub const BUILD_TIMESTAMP: &str = \"{build_timestamp}\";").as_ref());
}
