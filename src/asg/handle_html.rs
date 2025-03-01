use scraper::{Html, Selector};

#[derive(Debug, Clone)]
pub struct HtmlHeading {
    pub rank: u8,
    pub text: String,
}

pub fn parse_html(html: &str) -> Vec<HtmlHeading> {
    let fragment = Html::parse_fragment(html);
    let mut result = Vec::new();

    if let Ok(selector) = Selector::parse("h1, h2, h3, h4, h5, h6") {
        for element in fragment.select(&selector) {
            let tag_name = element.value().name();
            let rank = tag_name
                .chars()
                .nth(1)
                .unwrap_or('0')
                .to_digit(10)
                .unwrap_or(0) as u8;

            let text = element.text().collect::<String>().trim().to_string();

            result.push(HtmlHeading { rank, text });
        }
    }

    result
}

pub fn strip_html(s: &str) -> String {
    let fragment = Html::parse_fragment(s);

    fragment
        .root_element()
        .text()
        .collect::<String>()
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

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

    #[test]
    fn test_parse_html_headings() {
        let html = r#"
            <html>
                <head><title>Test Page</title></head>
                <body>
                    <h1>Main Title</h1>
                    <p>Some content</p>
                    <h2>Subtitle 1</h2>
                    <p>More content</p>
                    <h3>Section 1.1</h3>
                    <p>Even more content</p>
                    <h2>Subtitle 2</h2>
                    <h3>Section 2.1</h3>
                </body>
            </html>
        "#;

        let headings = parse_html(html);

        assert_eq!(headings.len(), 5);
        assert_eq!(headings[0].rank, 1);
        assert_eq!(headings[0].text, "Main Title");
        assert_eq!(headings[1].rank, 2);
        assert_eq!(headings[1].text, "Subtitle 1");
        assert_eq!(headings[2].rank, 3);
        assert_eq!(headings[2].text, "Section 1.1");
        assert_eq!(headings[3].rank, 2);
        assert_eq!(headings[3].text, "Subtitle 2");
        assert_eq!(headings[4].rank, 3);
        assert_eq!(headings[4].text, "Section 2.1");
    }

    #[test]
    fn test_parse_html_with_attributes() {
        let html = r#"
            <h1 class="title" id="main-title">Title with Attributes</h1>
            <h2 style="color: blue;">Blue Subtitle</h2>
        "#;

        let headings = parse_html(html);

        assert_eq!(headings.len(), 2);
        assert_eq!(headings[0].rank, 1);
        assert_eq!(headings[0].text, "Title with Attributes");
        assert_eq!(headings[1].rank, 2);
        assert_eq!(headings[1].text, "Blue Subtitle");
    }

    #[test]
    fn test_parse_html_with_nested_elements() {
        let html = "<h1>Title with <em>emphasis</em> and <strong>strong</strong> text</h1><h2>Subtitle with <a href=\"#\">link</a></h2>";

        let headings = parse_html(html);

        assert_eq!(headings.len(), 2);
        assert_eq!(headings[0].rank, 1);
        assert_eq!(headings[0].text, "Title with emphasis and strong text");
        assert_eq!(headings[1].rank, 2);
        assert_eq!(headings[1].text, "Subtitle with link");
    }
}
