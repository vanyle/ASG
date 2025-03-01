/// File process
use std::path::Path;
use std::{fs, time};

pub mod csv;
pub mod displayluaerror;
pub mod git_times;
pub mod handle_html;
pub mod lua_environment;
pub mod tokenizer;

use lua_environment::LuaEnvironment;
use notify_debouncer_full::notify;

pub fn generate_file(
    env: &mut LuaEnvironment,
    input_file: &Path,
    base_input_directory: &Path,
    output_directory: &Path,
) {
    // Let's run config.lua if it exists
    // TODO: don't run it every time!
    let config_file = base_input_directory.join("config.lua");
    if config_file.exists() {
        env.run_file_and_display_error(&config_file);
    } else {
        println!(
            "Error: Config file not at {}",
            config_file.to_str().unwrap()
        );
    }

    let is_debug_info = env.is_enabled("debugInfo");
    let is_profiling_enabled = env.is_enabled("profiler");
    let generation_instant_start = time::Instant::now();

    let mut should_be_compiled = false;
    for format in tokenizer::LUA_TEMPLATE_FORMATS {
        if input_file.to_str().unwrap().ends_with(format) {
            should_be_compiled = true;
            break;
        }
    }

    if !should_be_compiled {
        return;
    }

    let destination_url = tokenizer::get_destination_url(input_file, base_input_directory);
    let output_file = output_directory.join(&destination_url);

    if is_debug_info {
        println!(
            "Compiling {}",
            input_file.to_str().unwrap_or("<non-utf8 path>")
        );
    }

    let maybe_str =
        tokenizer::compile_file(env, input_file, Some(&output_file), base_input_directory);

    if let Some(content) = maybe_str {
        let prefix = output_file.parent().unwrap();
        let _ = fs::create_dir_all(prefix);

        if is_debug_info {
            println!(
                "Writing to {}",
                output_file.to_str().unwrap_or("<non-utf8 path>")
            );
        }
        fs::write(&output_file, content).unwrap();
        let delta = generation_instant_start.elapsed();

        if is_profiling_enabled {
            println!(
                "  - {} ms to generate {}",
                delta.as_millis(),
                &destination_url
            );
        }
    } else {
        println!("Error: Could not compile file {:?}", input_file);
    }
}

fn recursive_file_walk(
    env: &mut LuaEnvironment,
    current_dir: &Path,
    input_directory: &Path,
    output_directory: &Path,
) {
    for entry in fs::read_dir(current_dir).unwrap() {
        let entry = entry.unwrap();
        let path = entry.path();

        // Ignore data directory
        if path.is_dir() && path.ends_with("data") {
            continue;
        }

        if path.is_dir() {
            recursive_file_walk(env, &path, input_directory, output_directory);
        } else {
            generate_file(env, &path, input_directory, output_directory);
        }
    }
}

pub fn process_files(env: &mut LuaEnvironment, input_directory: &Path, output_directory: &Path) {
    // Parse posts first
    let now = time::Instant::now();

    let posts_directory = input_directory.join("posts");
    if posts_directory.exists() {
        recursive_file_walk(env, &posts_directory, input_directory, output_directory);
    }

    // Parse the rest
    recursive_file_walk(env, input_directory, input_directory, output_directory);

    let is_profiling_enabled = env.is_enabled("profiler");
    if is_profiling_enabled {
        let delta = now.elapsed();
        println!("Total time: {} ms", delta.as_millis());
    }
}

pub fn process_file(
    env: &mut LuaEnvironment,
    event_kind: notify::EventKind,
    file: &Path,
    input_directory: &Path,
    output_directory: &Path,
) {
    let is_debug_info = env.is_enabled("debugInfo");

    if is_debug_info {
        println!("OS Event received: {:?}", event_kind);
    }

    match event_kind {
        notify::EventKind::Any => {
            println!("Any event: {:?}", file);
        }
        notify::EventKind::Access(_) => {}
        notify::EventKind::Create(_) => {
            if file.exists() {
                generate_file(env, file, input_directory, output_directory);
            }
        }
        notify::EventKind::Modify(_) => {
            if file.exists() {
                generate_file(env, file, input_directory, output_directory);
            }
        }
        notify::EventKind::Remove(_) => {
            let mut output_file =
                output_directory.join(file.strip_prefix(input_directory).unwrap());
            if output_file.to_str().unwrap().ends_with(".md") {
                output_file = output_file.with_extension("html");
            }
            if output_file.exists() {
                fs::remove_file(output_file).unwrap();
            }
        }
        notify::EventKind::Other => {
            println!("Other event: {:?}", file);
        }
    }
}
