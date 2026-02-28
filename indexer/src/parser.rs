use lazy_static::lazy_static;
use regex::Regex;
use serde_json::Value;
use std::error::Error;
use std::path::Path;
use std::sync::LazyLock;

#[derive(Debug, PartialEq, Clone, Copy)] // Derive Macros
pub enum HeadingLevel {
    H1 = 1,
    H2 = 2,
    H3 = 3,
    H4 = 4,
    H5 = 5,
    H6 = 6,
}
#[derive(Debug, Clone)]
pub struct Heading {
    pub level: HeadingLevel,
    pub text: String,
    pub anchor: String,
}

#[derive(Debug, Clone)]
pub struct ParsedNote {
    pub slug: String,
    pub title: String,
    pub description: Option<String>,
    pub raw_md: String,
    pub html: String,
    pub links: Vec<String>,
    pub embeds: Vec<String>,
    pub tags: Vec<String>,
    pub toc: Vec<Heading>,
    pub has_latex: bool,
    pub frontmatter: Value,
}

pub fn parse_note(path: &Path) -> Result<ParsedNote, Box<dyn Error>> {
    let raw = std::fs::read_to_string(path)?;
    let (formatter_str, markdown) = split_formatter(&raw);

    println!("formatter: {:?}", formatter_str);
    println!("markdown: {:?}", markdown);

    todo!()
}

// spilt-formatter to split md file attributes
fn split_formatter(raw: &str) -> (&str, &str) {
    if raw.starts_with("---") {
        let after_first = &raw[3..];
        if let Some(end) = after_first.find("---") {
            let formatter = &after_first[..end];
            let content = &after_first[end + 3..];
            return (formatter.trim(), content.trim());
        }
    }
    ("", raw.trim())
}

// embeds and wikilinks
static LINK_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(!)?\[\[([^\]|]+)(?:\|[^\]]+)?\]\]").unwrap());
fn extract_links(markdown: &str) -> (Vec<String>, Vec<String>) {
    let mut wikilinks = Vec::new();
    let mut embeds = Vec::new();

    let re = Regex::new(r"(!)?\[\[([^\]|]+)(?:\|[^\]]+)?\]\]").unwrap(); // read regex to understand that god lang
    for cap in re.captures_iter(markdown) {
        let is_embed = cap.get(1).is_some();
        let target = cap.get(2).map(|m| m.as_str().trim().to_string()).unwrap();

        if is_embed {
            embeds.push(target);
        } else {
            wikilinks.push(target);
        }
    }
    (wikilinks, embeds)
}

// title and tags
fn parse_formatter(yaml_str: &str) -> (Option<String>, Vec<String>, Value) {
    let yaml: Value =
        serde_yaml::from_str(yaml_str).unwrap_or(Value::Object(serde_json::Map::new()));

    // grabing the title
    let title = yaml
        .get("title")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string());

    let mut tags = Vec::new();
    if let Some(tags_val) = yaml.get("tags") {
        if let Some(tag_list) = tags_val.as_array() {
            for t in tag_list {
                if let Some(tag_str) = t.as_str() {
                    tags.push(tag_str.to_string());
                }
            }
        } else if let Some(single_tag) = tags_val.as_str() {
            tags.push(single_tag.to_string());
        }
    }
    (title, tags, yaml) // (Option<String>, Vec<String>, Value)
}

// parsig body(content)

