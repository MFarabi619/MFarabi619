use std::fs::{self, File, OpenOptions};
use std::io::Write;

fn read_file(file_path: &str) -> String {
    fs::read_to_string(file_path).unwrap_or_else(|_| String::new())
}
fn write_to_readme(content: &str, mode: &str) {
    let path = "README.md";
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
fn combine_markdown_files() {
    write_to_readme("<!-- markdownlint-disable -->\n", "w");

    let intro_content = read_file("./Markdown Sections/intro.md");
    write_to_readme(&intro_content, "a");


    let current_setup = read_file("./Markdown Sections/current_setup.md");
    write_to_readme(&current_setup, "a");

    let about_content = read_file("./Markdown Sections/about.md");
    write_to_readme(&about_content, "a");

    let connect_content = read_file("./Markdown Sections/connect.md");
    write_to_readme(&connect_content, "a");
}

fn main() {
    combine_markdown_files();
}
