use std::{
    cmp::min,
    collections::HashMap,
    path::{Path, PathBuf},
    time::{self, SystemTime},
};

use crate::asg::lua_environment::{FileInfo, LuaEnvironment, get_asset_dir_path, get_exe_dir_path};
use chrono::DateTime;
use colored::Colorize;

use super::{git_times, handle_html::strip_html};

pub struct Tokenized<'a> {
    underlying_data: &'a str,
    position: usize,
}

pub fn tokenize(s: &str) -> Tokenized {
    Tokenized {
        underlying_data: s,
        position: 0,
    }
}

impl<'a> Iterator for Tokenized<'a> {
    type Item = &'a str;

    fn next(&mut self) -> Option<Self::Item> {
        let len = self.underlying_data.len();
        let start = self.position;

        if self.position >= len {
            return None;
        }

        let mut i = start;

        // If we start with a delimiter, we should return it
        let p = &self.underlying_data[i..min(i + 2, len)];
        if p == "{{" || p == "}}" || p == "{%" || p == "%}" {
            self.position = i + 2;
            return Some(p);
        }

        i += 1;

        while i < len {
            unsafe {
                // Does not matter if p is not a valid unicode string.
                let p = self.underlying_data.get_unchecked(i..min(i + 2, len));
                if p == "{{" || p == "}}" || p == "{%" || p == "%}" {
                    self.position = i;
                    return Some(&self.underlying_data[start..i]);
                }
            }
            i += 1;
        }
        self.position = len;
        Some(&self.underlying_data[start..len])
    }
}

// -------------------------

#[derive(Clone, Copy, Debug)]
pub enum ParseChunkType {
    RawText,
    LuaController, // {% lua %}
    LuaValue,      // {{ value }}
}

#[derive(Clone, Debug)]
pub struct ParseChunk {
    chunk: String,
    chunk_type: ParseChunkType,
}

/// Contains a partially parsed file.
/// The lua chunks needs to be executed and converted from markdown to HTML.
#[derive(Clone)]
pub struct PartialParse {
    chunks: Vec<ParseChunk>,
    timestamp: time::SystemTime,
    real_path: PathBuf,
    _partial_parse_time: time::Duration,
}

pub struct ParsingCache {
    pub cache: HashMap<PathBuf, PartialParse>,
    pub file_cache: HashMap<PathBuf, FileInfo>,
}

impl ParsingCache {
    pub fn new() -> ParsingCache {
        ParsingCache {
            cache: HashMap::new(),
            file_cache: HashMap::new(),
        }
    }
}

impl Default for ParsingCache {
    fn default() -> Self {
        Self::new()
    }
}

// For small lists, vec is faster than hashset
pub const LUA_TEMPLATE_FORMATS: &[&str] = &[".html", ".md", ".css", ".js", ".txt", ".asg"];

/// Pure function (but reads IO).
/// Takes the content of a file and outputs a partially parsed version.
/// Does not execute lua, nor markdown and is memoized.
pub fn tokenize_file(
    cache: &mut ParsingCache,
    relative_path: &Path,
    input_dir: &Path,
) -> Option<PartialParse> {
    if cache.cache.contains_key(relative_path) {
        let last_parse = &cache.cache[relative_path];
        let last_modified_time = last_parse.real_path.metadata().unwrap().modified().unwrap();
        if last_modified_time < last_parse.timestamp {
            return Some(last_parse.clone());
        }
    }

    let start_of_parse = time::Instant::now();
    // To resolve the relative path, we try in order:
    // - relative to cwd.
    // - relative to the executable
    // - relative to executable/assets

    let mut input_path = relative_path.to_path_buf();
    if !input_path.exists() || !input_path.is_file() {
        input_path = input_dir.join(relative_path);
    }
    if !input_path.exists() || !input_path.is_file() {
        input_path = get_exe_dir_path().join(relative_path);
    }
    if !input_path.exists() || !input_path.is_file() {
        input_path = get_asset_dir_path().join(relative_path);
    }

    if !input_path.exists() || !input_path.is_file() {
        return None;
    }

    let Ok(file_content) = std::fs::read_to_string(&input_path) else {
        return None;
    };

    let mut templating = false;

    for format in LUA_TEMPLATE_FORMATS {
        if input_path.to_str().unwrap().ends_with(format) {
            templating = true;
            break;
        }
    }

    let is_pure_lua = input_path.to_str().unwrap().ends_with(".lua");
    if !templating || is_pure_lua {
        let chunk_type = if is_pure_lua {
            ParseChunkType::LuaController
        } else {
            ParseChunkType::RawText
        };
        let chunks: Vec<ParseChunk> = vec![ParseChunk {
            chunk: file_content,
            chunk_type,
        }];
        return Some(PartialParse {
            chunks,
            timestamp: time::SystemTime::now(),
            real_path: relative_path.to_path_buf(),
            _partial_parse_time: start_of_parse.elapsed(),
        });
    }

    let mut chunks: Vec<ParseChunk> = Vec::new();
    let mut is_in_lua = false;
    let mut is_in_lua_controller = false;
    let mut is_in_loop = false;
    let mut is_end_of_loop = false;
    let mut lua_code_buffer = String::new();

    for t in tokenize(&file_content) {
        if t == "{{" {
            is_in_lua = true;
        } else if t == "}}" {
            is_in_lua = false;
        } else if t == "{%" {
            is_in_lua_controller = true;
        } else if t == "%}" {
            is_in_lua_controller = false;
            if is_in_loop {
                if is_end_of_loop {
                    is_in_loop = false;
                    is_end_of_loop = false;
                    lua_code_buffer.push_str("return table.concat(result)");

                    chunks.push(ParseChunk {
                        chunk: lua_code_buffer,
                        chunk_type: ParseChunkType::LuaValue,
                    });
                    lua_code_buffer = String::new();
                } else {
                    is_end_of_loop = true;
                }
            }
        } else if is_in_loop {
            if is_in_lua {
                lua_code_buffer.push_str(&format!("table.insert(result,({}))\n", t));
            } else if is_in_lua_controller {
                lua_code_buffer.push_str(&format!("{}\n", t.trim()));
            } else {
                lua_code_buffer.push_str(&format!("table.insert(result,[=====[{}]=====])\n", t));
            }
        } else if is_in_lua {
            chunks.push(ParseChunk {
                chunk: format!("return {}", t),
                chunk_type: ParseChunkType::LuaValue,
            });
        } else if is_in_lua_controller {
            let stripped = t.trim();
            if stripped.starts_with("for ")
                || stripped.starts_with("if ")
                || stripped.starts_with("while ")
            {
                is_in_loop = true;
                is_end_of_loop = false;
                lua_code_buffer = format!("result = {{}}\n{}\n", stripped).to_string();
            } else {
                chunks.push(ParseChunk {
                    chunk: t.to_string(),
                    chunk_type: ParseChunkType::LuaController,
                });
            }
        } else {
            chunks.push(ParseChunk {
                chunk: t.to_string(),
                chunk_type: ParseChunkType::RawText,
            });
        }
    }

    let result = Some(PartialParse {
        chunks,
        timestamp: time::SystemTime::now(),
        real_path: input_path.to_path_buf(),
        _partial_parse_time: start_of_parse.elapsed(),
    });
    // Don't fill the cache with large files (>10Mo)
    if file_content.len() < 10 * 1024 * 1024 * 8 {
        cache
            .cache
            .insert(input_path.to_path_buf(), result.clone().unwrap());
    }
    result
}

/// Read the file located at `in_path` and turn it into the
/// file inside `out_path`.
/// If `out_path` is not provided, no output is generated.
/// This function is not pure and can modify the lua state machine.
pub fn compile_file(
    env: &mut LuaEnvironment,
    in_path: &Path,
    out_path: Option<&Path>,
    base_input_dir: &Path,
) -> Option<String> {
    let mut v = vec![];
    compile_file_recursive(env, in_path, out_path, base_input_dir, &mut v)
}

fn compile_file_recursive(
    env: &mut LuaEnvironment,
    in_path: &Path,
    _out_path: Option<&Path>,
    base_input_dir: &Path,
    recursion_path: &mut Vec<PathBuf>,
) -> Option<String> {
    let partial_parse = tokenize_file(&mut env.cache.borrow_mut(), in_path, base_input_dir);
    partial_parse.as_ref()?; // if none, return
    let partial_parse = partial_parse.unwrap();
    recursion_path.push(partial_parse.real_path.as_path().to_owned());

    let mut raw_data = String::new();

    let file_path = partial_parse.real_path.as_path();
    let file_metadata = file_path.metadata().unwrap();
    let file_info_table = env.lua.create_table().unwrap();
    let _ = file_info_table.set("name", file_path.to_string_lossy().to_string());
    let _ = file_info_table.set("size", file_metadata.len());

    let datetime: DateTime<chrono::Local> =
        file_metadata.modified().unwrap_or(SystemTime::now()).into();
    let blame = git_times::git_blame(file_path);

    file_info_table
        .set(
            "last_modified_os",
            datetime.format("%d/%m/%Y %T").to_string(),
        )
        .unwrap();

    file_info_table
        .set(
            "last_modified",
            git_times::get_git_modification_time(&blame)
                .format("%d/%m/%Y %T")
                .to_string(),
        )
        .unwrap();

    file_info_table
        .set(
            "created_at",
            git_times::get_git_creation_time(&blame)
                .format("%d/%m/%Y %T")
                .to_string(),
        )
        .unwrap();

    env.lua.globals().set("file", file_info_table).unwrap();

    for chunk in &partial_parse.chunks {
        match chunk.chunk_type {
            ParseChunkType::RawText => {
                raw_data.push_str(&chunk.chunk);
            }
            ParseChunkType::LuaController => {
                let lua_chunk = env.lua.load(&chunk.chunk);
                let result = lua_chunk
                    .set_name("@".to_owned() + &file_path.to_string_lossy())
                    .exec();
                match result {
                    Ok(_) => {}
                    Err(e) => {
                        let error_msg = e.to_string();
                        let error_file = file_path.to_string_lossy();
                        env.display_error(&error_msg, &error_file, Some(&chunk.chunk));
                    }
                }
            }
            ParseChunkType::LuaValue => {
                let lua_chunk = env.lua.load(&chunk.chunk);
                let result: Result<mlua::Value, mlua::Error> = lua_chunk
                    .set_name("@".to_owned() + file_path.to_str().unwrap())
                    .call(());
                match result {
                    Ok(r) => {
                        if let Ok(d) = r.to_string() {
                            raw_data.push_str(&d);
                        } else if r.is_null() {
                            raw_data.push_str("nil");
                        } else {
                            raw_data.push_str("<LUA VALUE>");
                        }
                    }
                    Err(e) => {
                        let error_msg = e.to_string();
                        let error_file = file_path.to_string_lossy();
                        env.display_error(&error_msg, &error_file, Some(&chunk.chunk));
                    }
                }
            }
        }
    }

    if file_path.to_str().unwrap().ends_with(".md") {
        let mut options = markdown::Options::gfm();
        options.compile.allow_dangerous_html = true;
        options.compile.allow_dangerous_protocol = true;
        options.compile.gfm_tagfilter = false;
        let result = markdown::to_html_with_options(&raw_data, &options);
        if result.is_ok() {
            raw_data = result.unwrap();
        } else {
            let error_msg = result.err().unwrap().to_string();
            let error_file = file_path.to_string_lossy();
            env.display_error(&error_msg, &error_file, None);
        }
    }

    let tags: Vec<String>;
    let title;
    let description;

    // Strip script and style

    let without_html = strip_html(&raw_data);
    let maybe_layout_file;
    let word_count;
    let are_errors_colored;

    {
        let config = env.config_table.borrow();
        let maybe_tags = config
            .get("tags")
            .map(|s| s.to_string())
            .unwrap_or(String::from(""));

        tags = maybe_tags
            .split(",")
            .map(|s| s.to_string())
            .collect::<Vec<String>>();

        let mut lines = without_html.lines().filter(|l| !l.trim().is_empty());
        word_count = without_html.split_whitespace().count();
        title = config
            .get("title")
            .map(|s| s.to_string())
            .or(lines.next().map(|s| s.to_string()));

        description = config
            .get("description")
            .map(|s| s.to_string())
            .or(lines.next().map(|s| s.to_string()));

        maybe_layout_file = config.get("layout").map(|s| s.to_string());
        are_errors_colored = config.get("coloredErrors").unwrap_or(&"".to_string()) == "true";
    }

    if let Some(layout_file) = maybe_layout_file {
        if !layout_file.is_empty() {
            let layout_file = Path::new(&layout_file).to_path_buf();
            if recursion_path.contains(&layout_file) {
                let m_yellow = |s: &str| {
                    if are_errors_colored {
                        s.yellow()
                    } else {
                        s.clear()
                    }
                };

                println!(
                    "{}",
                    m_yellow("Warning: Infinite inclusion loop in layouts")
                );
                println!("  The recursion stack is:");
                println!(
                    "  {}",
                    recursion_path
                        .iter_mut()
                        .map(|p| p.to_string_lossy().to_string())
                        .collect::<Vec<String>>()
                        .join(",")
                );
                println!("The last file is repeated, this is a loop.");
            } else {
                env.lua.globals().set("body", raw_data).unwrap();
                let result = compile_file_recursive(
                    env,
                    &layout_file,
                    _out_path,
                    base_input_dir,
                    recursion_path,
                );
                if result.is_some() {
                    raw_data = result.unwrap();
                } else {
                    return None;
                }
            }
        }
    }

    let datetime: DateTime<chrono::Utc> =
        file_metadata.modified().unwrap_or(SystemTime::now()).into();
    let blame = git_times::git_blame(file_path);

    let fpi = FileInfo {
        filename: file_path.to_str().unwrap().to_string(),
        url: get_destination_url(file_path, base_input_dir),
        size: 0_i64,
        word_count: word_count as i64,
        last_modified_os: datetime.format("%d/%m/%Y %T").to_string(),
        last_modified: git_times::get_git_modification_time(&blame)
            .format("%d/%m/%Y %T")
            .to_string(),
        created_at: git_times::get_git_creation_time(&blame)
            .format("%d/%m/%Y %T")
            .to_string(),
        title: title.unwrap_or("".to_string()),
        description: description.unwrap_or("".to_string()),
        tags: tags.iter().map(|s| s.to_string()).collect(),
    };
    env.cache
        .borrow_mut()
        .file_cache
        .insert(in_path.to_path_buf(), fpi);
    Some(raw_data)
}

pub fn get_destination_url(file_path: &Path, base_input_dir: &Path) -> String {
    let relative_path = file_path
        .strip_prefix(base_input_dir)
        .unwrap_or(base_input_dir);
    let mut output_file = Path::new(".").join(relative_path);
    if output_file.to_string_lossy().ends_with(".md") {
        output_file = output_file.with_extension("html");
    }
    output_file.to_string_lossy().into_owned()
}
