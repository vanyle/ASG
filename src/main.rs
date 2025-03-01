use std::path::{self, Path};

use ::asg::lib_main;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = std::env::args().collect();

    if args.len() != 3 {
        println!("Usage: asg <input_directory> <output_directory>");
        println!("Read the README.md for more information.");
        std::process::exit(1);
    }
    let input_directory = path::absolute(Path::new(&args[1])).unwrap();
    let output_directory = path::absolute(Path::new(&args[2])).unwrap();

    lib_main(&input_directory, &output_directory).await;
}
