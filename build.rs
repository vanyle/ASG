use std::{env, fs, io::Write, path::Path};

fn main() {
    let dst = Path::new(&env::var("OUT_DIR").expect("OUT_DIR not set")).join("built.rs");
    //let cargo_manifest_dir: &Path = env::var("CARGO_MANIFEST_DIR")
    //    .expect("CARGO_MANIFEST_DIR")
    //    .as_ref();
    let mut built_file = fs::File::create(dst).unwrap();
    // We are generating a file that will be imported by run main program.
    let _ = built_file.write_all(
        r#"//
// EVERYTHING BELOW THIS POINT WAS AUTO-GENERATED DURING COMPILATION. DO NOT MODIFY.
//
pub const MAGIC_BUILT_VALUE: &str = "Hello, world!";
"#
        .as_ref(),
    );
}
