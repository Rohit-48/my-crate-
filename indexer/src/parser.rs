use serde_json::Value;

#[derive(Debug, PartialEq, Clone, Copy)] // Derive Macros
pub enum HeadingLevel{
    H1 = 1,
    H2 = 2,
    H3 = 3,
    H4 = 4,
    H5 = 5,
    H6 = 6,
}
#[derive(Debug, Clone)]
pub struct Heading{
    pub level: HeadingLevel,
    pub text: String,
    pub anchor: String,
}

#[derive(Debug, Clone)]
pub struct ParsedNote{
    pub slug: String,
    pub title:String,
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