use std::{
    cell::RefCell,
    collections::HashMap,
    env, fs,
    path::{Path, PathBuf},
    rc::Rc,
};

use colored::Colorize;
use mlua::{Lua, LuaSerdeExt, Value as LuaValue};
use serde::{Deserialize, Serialize};

use crate::asg::date_format::DATE_FORMAT;

use super::buildinfo;
use super::highlight_syntax;
use super::{csv, handle_html, highlight_syntax::SyntaxHighlighter, tokenizer};

// Information about a file accessible from the Lua script.
#[derive(Serialize, Deserialize)]
pub struct FileInfo {
    pub filename: String,
    pub url: String,
    pub size: i64,
    pub word_count: i64,
    pub last_modified_os: String,
    pub last_modified: String,
    pub created_at: String,
    pub title: String,
    pub description: String,
    pub tags: Vec<String>,
}

pub struct LuaEnvironment {
    pub lua: Lua,
    pub config_table: Rc<RefCell<HashMap<String, String>>>,
    pub cache: Rc<RefCell<tokenizer::ParsingCache>>,
}

pub fn get_exe_dir_path() -> PathBuf {
    let current_exe = env::current_exe().unwrap();
    current_exe.parent().unwrap().to_path_buf()
}

pub fn get_asset_dir_path() -> PathBuf {
    let current_exe_dir = get_exe_dir_path();

    current_exe_dir.join("assets")
}
impl LuaEnvironment {
    pub fn new(
        input_directory: &Path,
        _output_directory: &Path,
        asset_directory: Option<PathBuf>,
    ) -> LuaEnvironment {
        // In a testing environment, there may not be an asset folder next to the executable, so we use the asset_directory provided.
        let assets_path = Rc::new(asset_directory.unwrap_or(get_asset_dir_path()));

        let lua = Lua::new();
        let _ = lua.sandbox(false);
        lua.enable_jit(true);

        let config_table = Rc::new(RefCell::new(HashMap::new()));
        let cache = Rc::new(RefCell::new(tokenizer::ParsingCache::new()));

        let env = LuaEnvironment {
            lua,
            config_table,
            cache,
        };

        let table_ref = env.config_table.clone();

        env.lua
            .globals()
            .set(
                "setvar",
                env.lua
                    .create_function(move |_, (key, value): (String, String)| {
                        // println!("setvar: Setting {} to {}", key, value);
                        table_ref.borrow_mut().insert(key, value);
                        Ok(())
                    })
                    .unwrap(),
            )
            .unwrap();

        let assets_path_ref = assets_path.clone();
        env.lua
            .globals()
            .set(
                "include_asset",
                env.lua
                    .create_function(move |_, asset_path: String| {
                        let asset_path = assets_path_ref.join(Path::new(&asset_path));
                        if asset_path.exists() {
                            Ok(fs::read_to_string(asset_path).unwrap_or_default())
                        } else {
                            Ok(String::new())
                        }
                    })
                    .unwrap(),
            )
            .unwrap();

        env.lua
            .globals()
            .set(
                "tostring",
                env.lua
                    .create_function(|_, value: LuaValue| Ok(stringify(value)))
                    .unwrap(),
            )
            .unwrap();

        let posts_path = Rc::new(input_directory.join("posts"));
        let cache_ref = env.cache.clone();

        let posts_path_ref = posts_path.clone();
        env.lua
            .globals()
            .set(
                "posts",
                env.lua
                    .create_function(move |lua: &Lua, ()| {
                        if !posts_path_ref.exists() {
                            let iterator_nil =
                                lua.create_function(|_, ()| Ok(LuaValue::Nil)).unwrap();
                            return Ok(iterator_nil);
                        }

                        let cache_ref = cache_ref.clone();

                        let walker =
                            walkdir::WalkDir::new(posts_path_ref.as_path()).sort_by(|a, b| {
                                let t1 = a.metadata().ok().and_then(|meta| meta.modified().ok());
                                let t2 = b.metadata().ok().and_then(|meta| meta.modified().ok());
                                match (t1, t2) {
                                    (Some(t1), Some(t2)) => t1.cmp(&t2),
                                    _ => std::cmp::Ordering::Equal,
                                }
                            });
                        let iterator = Rc::new(RefCell::new(walker.into_iter()));

                        let iterator_fn = lua
                            .create_function(move |lua: &Lua, ()| {
                                loop {
                                    let Some(Ok(entry)) = iterator.borrow_mut().next() else {
                                        return Ok(LuaValue::Nil);
                                    };
                                    let cache_ref = cache_ref.clone();
                                    let cache_ref = cache_ref.borrow();
                                    let path = entry.into_path();
                                    let Some(file_info) = cache_ref.file_cache.get(&path) else {
                                        continue;
                                    };
                                    let Ok(value) = lua.to_value(&file_info) else {
                                        continue;
                                    };
                                    return Ok(value);
                                }
                            })
                            .unwrap();
                        Ok(iterator_fn)
                    })
                    .unwrap(),
            )
            .unwrap();

        let data_path = input_directory.join("data");
        env.lua
            .globals()
            .set(
                "read_data",
                env.lua
                    .create_function(move |_, filename: String| {
                        let data_path = data_path.as_path();
                        let data_file = data_path.join(filename);
                        if data_file.exists() {
                            Ok(fs::read_to_string(data_file).unwrap_or_default())
                        } else {
                            Ok(String::new())
                        }
                    })
                    .unwrap(),
            )
            .unwrap();

        let data_path = input_directory.join("data");

        env.lua
            .globals()
            .set(
                "read_csv",
                env.lua
                    .create_function(move |_, filename: String| {
                        let data_path = data_path.as_path();
                        let data_file = data_path.join(filename);
                        Ok(csv::read_csv_file(&data_file))
                    })
                    .unwrap(),
            )
            .unwrap();

        let cache_ref = env.cache.clone();
        env.lua
            .globals()
            .set(
                "get_body",
                env.lua
                    .create_function(move |_, filename: String| {
                        let cache = cache_ref.borrow();
                        for path in cache.file_cache.keys() {
                            if path.file_name().map(|f| f.to_string_lossy().to_string())
                                == Some(filename.clone())
                                && let Ok(content) = std::fs::read_to_string(path)
                            {
                                return Ok(content);
                            }
                        }

                        Ok(String::new())
                    })
                    .unwrap(),
            )
            .unwrap();

        // Add parse_html function binding
        env.lua
            .globals()
            .set(
                "parse_html",
                env.lua
                    .create_function(move |lua, html: String| {
                        let headings = handle_html::parse_html(&html);
                        let result_table = lua.create_table()?;

                        for (i, heading) in headings.iter().enumerate() {
                            let heading_table = lua.create_table()?;
                            heading_table.set("rank", heading.rank)?;
                            heading_table.set("title", heading.text.clone())?;
                            result_table.set(i + 1, heading_table)?;
                        }

                        Ok(result_table)
                    })
                    .unwrap(),
            )
            .unwrap();

        // Add highlight_syntax function binding
        env.lua
            .globals()
            .set(
                "highlight_syntax",
                env.lua
                    .create_function(move |_, (code, lang): (String, String)| {
                        let sh = SyntaxHighlighter::new();
                        let html = highlight_syntax::highlight_syntax(&sh, &code, &lang);
                        Ok(html)
                    })
                    .unwrap(),
            )
            .unwrap();

        env.lua
            .globals()
            .set(
                "to_rfc2822_date",
                env.lua
                    .create_function(move |_, time: (String,)| {
                        let parsed_time =
                            chrono::NaiveDateTime::parse_from_str(&time.0, DATE_FORMAT);
                        println!(
                            "Parsed time: {:?} - {} ; {}",
                            parsed_time, &time.0, DATE_FORMAT
                        );
                        let Ok(dt) = parsed_time else {
                            return Ok(time.0);
                        };
                        Ok(dt.and_utc().to_rfc2822())
                    })
                    .unwrap(),
            )
            .unwrap();

        env.lua
            .globals()
            .set(
                "asg_commit_hash",
                env.lua
                    .create_string(buildinfo::built_info::COMMIT_HASH)
                    .unwrap(),
            )
            .unwrap();

        env.lua
            .globals()
            .set(
                "asg_version",
                env.lua.create_string(buildinfo::get_asg_version()).unwrap(),
            )
            .unwrap();

        // Let's run std.lua if it exists
        let std_file = assets_path.join("std.lua");
        if std_file.exists() {
            env.run_file_and_display_error(&std_file);
        } else {
            println!(
                "{}: std.lua not found in assets directory. Check your installation.",
                "Error".red()
            );
            println!(
                "{}: Looking for std.lua at {}",
                "Info".yellow(),
                std_file.to_str().unwrap()
            );
            std::process::exit(1);
        }

        env
    }

    pub fn is_enabled(&self, feature_name: &str) -> bool {
        let config = self.config_table.borrow();
        config.contains_key(feature_name) && config.get(feature_name).unwrap() == "true"
    }

    pub fn get_config(&self, key: &str) -> Option<String> {
        let config = self.config_table.borrow();
        config.get(key).cloned()
    }

    /// Assumes that the path provided is a valid file.
    pub fn run_file_and_display_error(&self, file_path: &Path) {
        let lua_chunk = self.lua.load(fs::read(file_path).unwrap());
        let result = lua_chunk
            .set_name("@".to_owned() + file_path.to_str().unwrap())
            .exec();
        if result.is_err() {
            let error = result.err().unwrap();
            let error_msg = error.to_string();
            self.display_error(&error_msg, file_path.to_str().unwrap(), None);
        }
    }
}

fn stringify(value: LuaValue) -> String {
    match value {
        LuaValue::Nil => "nil".to_string(),
        LuaValue::Boolean(b) => b.to_string(),
        LuaValue::LightUserData(light_user_data) => {
            format!("LightUserData({})", light_user_data.0.addr())
        }
        LuaValue::Integer(i) => format!("{i}"),
        LuaValue::Number(i) => format!("{i}"),
        LuaValue::Vector(v) => format!("Vector({},{},{})", v.x(), v.y(), v.z()),
        LuaValue::String(s) => s.to_string_lossy(),
        LuaValue::Table(table) => {
            let mut result = "{".to_string();
            for pair in table.pairs::<String, LuaValue>() {
                match pair {
                    Ok((key, value)) => {
                        result.push_str(format!("{}={},", key, stringify(value)).as_str());
                    }
                    Err(_) => continue,
                }
            }
            result.push('}');
            result
        }
        LuaValue::Function(function) => {
            let info = function.info();
            format!(
                "Function({}, {})",
                info.name.unwrap_or("unnamed".to_string()),
                info.line_defined.unwrap_or(usize::MAX)
            )
        }
        LuaValue::Thread(thread) => format!("Thread({})", thread.to_pointer().addr()),
        LuaValue::UserData(any_user_data) => {
            format!("UserData({})", any_user_data.to_pointer().addr())
        }
        LuaValue::Buffer(buffer) => format!("Buffer(len={})", buffer.len()),
        LuaValue::Error(error) => format!("Error({error})"),
        LuaValue::Other(_) => "Other(???)".to_string(),
    }
}
