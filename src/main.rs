use std::path::{self, Path};

pub mod buildinfo;

use ::asg::lib_main;
use colored::Colorize;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() == 2 && (args[1] == "--version" || args[1] == "-v" || args[1] == "-version") {
        println!("asg - {}", "Awesome Static Generator".bold());
        println!("Available at {}", "https://github.com/vanyle/asg".green());

        #[allow(clippy::const_is_empty)]
        // TAG_NAME is generated at compile-time and can be empty or not.
        let version = if buildinfo::built_info::TAG_NAME.is_empty() {
            buildinfo::built_info::BRANCH_NAME
        } else {
            buildinfo::built_info::TAG_NAME
        };
        println!("Version: {}", version.blue());
        println!();
        println!("Build hash: {}", buildinfo::built_info::COMMIT_HASH.blue());
        println!("Built on {}", buildinfo::built_info::BUILD_TIMESTAMP.blue());
        std::process::exit(0);
    }

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
