use colored::Colorize;

use crate::asg::LuaEnvironment;

impl LuaEnvironment {
    #[allow(clippy::print_stdout)]
    pub fn display_error(&self, error_msg: &str, error_file: &str, m_error_code: Option<&str>) {
        let config = self.config_table.borrow();
        // color is enabled by default.
        let is_color = !config.contains_key("coloredErrors") || config["coloredErrors"] == "true";

        let m_red = |s: &str| {
            if is_color { s.red() } else { s.clear() }
        };

        println!("{}", m_red("Compilation Error:"));
        println!("  Concerning {error_file}");
        println!("  {error_msg}");

        if let Some(error_code) = m_error_code {
            println!("  {}", m_red("Code responsible:"));

            if error_code.len() > 400 {
                let error_code = error_code.split_at(400).0;
                println!("{error_code}... (omited)");
            } else {
                println!("{error_code}");
            }

            println!("{}", m_red("-----"));
        }
    }
}
