use regex::Regex;

/// Strips HTML tags from a string using a regex.
/// Might not work for all cases but fast.
pub fn strip_html(s: &str) -> String {
    let re = Regex::new(r"<[^>]*>").unwrap();
    re.replace_all(s, "").to_string()
}

#[cfg(test)]
mod tests {
    use crate::asg::strip_html::strip_html;

    #[test]
    fn test_strip_html() {
        let input = "<p>hello</p>";
        let result = strip_html(input);
        assert_eq!(result, "hello");
    }

    #[test]
    fn test_strip_scripts() {
        let input = "<script defer src=\"https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.5.1/languages/dockerfile.min.js\"></script>";
        let result = strip_html(input);
        assert_eq!(result, "");
    }
}
