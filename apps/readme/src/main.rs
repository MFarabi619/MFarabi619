use serde::Deserialize;
use std::fs::{self, File, OpenOptions};
use std::io::Write;

#[derive(Debug, Deserialize)]
struct Item {
    name: String,
    icon: String,
    url: String,
    width: Option<String>,
    height: Option<String>,
    alt: Option<String>,
}

#[derive(Debug, Deserialize)]
struct Category {
    #[serde(rename = "Languages")]
    languages: Vec<Item>,
    #[serde(rename = "Frameworks & Libraries")]
    frameworks_and_libraries: Vec<Item>,
    #[serde(rename = "Tools")]
    tools: Vec<Item>,
}

#[derive(Debug, Deserialize)]
struct SkillsData {
    #[serde(rename = "Actively Using")]
    actively_using: Category,
    #[serde(rename = "Previously Used")]
    previously_used: Category,
    #[serde(rename = "Would like to learn")]
    would_like_to_learn: Category,
}

fn read_file(file_path: &str) -> String {
    fs::read_to_string(file_path).unwrap_or_else(|_| String::new())
}

fn read_json<T: for<'de> Deserialize<'de>>(file_path: &str) -> Option<T> {
    fs::read_to_string(file_path)
        .ok()
        .and_then(|content| serde_json::from_str(&content).ok())
}

fn write_to_readme(content: &str, mode: &str) {
    let path = "../../README.md";
    let mut file = match mode {
        "w" => File::create(path).expect("Unable to create README.md"),
        "a" => OpenOptions::new()
            .append(true)
            .open(path)
            .expect("Unable to open README.md for appending"),
        _ => panic!("Invalid mode"),
    };
    file.write_all(content.as_bytes())
        .expect("Unable to write to README.md");
}

fn generate_skills_section(data: &SkillsData) -> String {
    let mut content = String::from(
        r#"Please note that my technical competency fluctuates based on my active projects. I learn (and often forget) things as I go, and regularly rotate between different problem areas.<br/><br/>
On occasions I've worked with as many as 8 different languages in a single day.<br/><br/>
<div class="tg-wrap" align="center">
<table>
<thead>
<tr>
<th>Languages</th><th>Frameworks & Libraries</th><th>Tools</th>
</tr>
</thead>
<tbody>
"#,
    );

    fn generate_category_rows(title: &str, category: &Category) -> String {
        let mut rows = format!(
            r#"<tr>
<td colspan="3" align="center"><b>{}</b></td>
</tr>
<tr>
"#,
            title
        );

        let sections = [
            &category.languages,
            &category.frameworks_and_libraries,
            &category.tools,
        ];

        for items in sections {
            rows.push_str("<td align='center'>\n");
            for item in items {
                let width = item.width.clone().unwrap_or_else(|| "40".to_string());
                let height = item.height.clone().unwrap_or_else(|| "40".to_string());
                let alt = item
                    .alt
                    .clone()
                    .unwrap_or_else(|| format!("{} Logo", item.name));
                rows.push_str(&format!(
                    r#"<!-- {} -->
<a href="{}" target="_blank" rel="noreferrer">
<img src="{}" alt="{}" width="{}" height="{}" />
</a>
"#,
                    item.name, item.url, item.icon, alt, width, height
                ));
            }
            rows.push_str("</td>\n");
        }
        rows.push_str("</tr>\n");
        rows
    }

    content.push_str(&generate_category_rows(
        "Actively Using",
        &data.actively_using,
    ));
    content.push_str(&generate_category_rows(
        "Previously Used",
        &data.previously_used,
    ));
    content.push_str(&generate_category_rows(
        "Intend to Use in Future",
        &data.would_like_to_learn,
    ));
    content.push_str("</tbody>\n</table>\n</div>\n\n");

    content
}

fn combine_markdown_files() {
    write_to_readme("<!-- markdownlint-disable -->\n", "w");

    let intro_content = read_file("content/intro.md");
    write_to_readme(&intro_content, "a");

    if let Some(skills_data) = read_json::<SkillsData>("content/skills.json") {
        let skills_md = generate_skills_section(&skills_data);
        write_to_readme(&skills_md, "a");
    }

    let current_setup = read_file("content/current_setup.md");
    write_to_readme(&current_setup, "a");

    let about_content = read_file("content/about.md");
    write_to_readme(&about_content, "a");

    let connect_content = read_file("content/connect.md");
    write_to_readme(&connect_content, "a");
}

fn main() {
    combine_markdown_files();
}
