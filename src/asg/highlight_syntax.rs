use syntect::highlighting::ThemeSet;
use syntect::html::highlighted_html_for_string;
use syntect::parsing::SyntaxSet;

pub struct SyntaxHighlighter {
    ps: SyntaxSet,
    ts: ThemeSet,
}

impl SyntaxHighlighter {
    pub fn new() -> Self {
        let ps = SyntaxSet::load_defaults_newlines();
        let ts = ThemeSet::load_defaults();
        Self { ps, ts }
    }
}

impl Default for SyntaxHighlighter {
    fn default() -> Self {
        Self::new()
    }
}

// Takes some code and a language name and return html code
// with the syntax highlighted. If the language is not found, return the string as is.
pub fn highlight_syntax(sh: &SyntaxHighlighter, code: &str, lang: &str) -> String {
    let syntax = sh.ps.find_syntax_by_extension(lang);
    let Some(syntax) = syntax else {
        return code.to_string();
    };

    let result =
        highlighted_html_for_string(code, &sh.ps, syntax, &sh.ts.themes["base16-ocean.dark"]);

    let Ok(html) = result else {
        return code.to_string();
    };

    html
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_highlight_syntax() {
        let sh = SyntaxHighlighter::new();
        let code = "print(\"Hello, world!\")";
        let lang = "rs";
        let html = highlight_syntax(&sh, code, lang);
        assert!(html.starts_with("<pre style="));
    }
}
