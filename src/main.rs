use std::path::{self, Path};

use ::asg::lib_main;
use colored::Colorize;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() != 3 {
        println!("Usage: asg <input_directory> <output_directory>");
        println!("Read the README.md for more information.");
        std::process::exit(1);
    }

    let resolve_path = |arg: &str| -> path::PathBuf {
        match path::absolute(Path::new(arg)) {
            Ok(path) => path,
            Err(e) => {
                println!("{} Could not resolve path: {}", "Error:".red(), e);
                std::process::exit(1);
            }
        }
    };

    let input_directory = resolve_path(&args[1]);
    let output_directory = resolve_path(&args[2]);

    lib_main(&input_directory, &output_directory).await;
}
