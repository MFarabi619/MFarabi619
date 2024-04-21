import json
from typing import Dict, List


def read_file(file_path: str) -> str:
    """Reads and returns the content of a file as a string."""
    try:
        with open(file_path, "r", encoding="utf-8") as file:
            return file.read()
    except FileNotFoundError:
        print(f"Warning: {file_path} not found. Will be skipped.")
        return ""


def read_json(file_path: str) -> Dict:
    """Reads and returns JSON data from a file."""
    try:
        with open(file_path, "r", encoding="utf-8") as file:
            return json.load(file)
    except FileNotFoundError:
        print(f"Error: JSON file at {file_path} not found.")
        return {}


def generate_skills_section(data: Dict[str, List[Dict]], category: str) -> str:
    """Generates markdown for the skills section based on the provided data."""
    content = (
        '<div class="tg-wrap" align="center">\n  <table>\n    <thead>\n      <tr>\n'
    )
    content += (
        "".join([f"<th>{key}</th>" for key in data.keys()])
        + "\n      </tr>\n    </thead>\n    <tbody>\n      <tr>\n"
    )

    for key, items in data.items():
        content += "        <td>\n"
        for item in items:
            width = item.get("width", "40")
            height = item.get("height", "40")
            alt_text = item.get("alt", f"{item['name']} Logo")
            content += f'          <!-- {item["name"]} -->\n'
            content += (
                f'          <a href="{item["url"]}" target="_blank" rel="noreferrer">\n'
            )
            content += f'            <img src="{item["icon"]}" alt="{alt_text}" width="{width}" height="{height}"/>\n          </a>\n'
        content += "        </td>\n"

    content += "      </tr>\n    </tbody>\n  </table>\n</div>\n<br/>\n"
    return content


def generate_connect_section(social_links: List[Dict[str, str]]) -> str:
    """Generates markdown content for the 'connect' section based on JSON data."""
    markdown_content = "🔗 **Connect with me**:<br/><br/>\n"
    for link in social_links:
        markdown_content += f'<a href="{link["url"]}" target="blank"><img src="{link["icon"]}" alt="{link["alt"]}" height="{link["height"]}" width="{link["width"]}" /></a>\n'
    return markdown_content


def write_to_readme(content: str, mode: str = "a") -> None:
    """Writes content to README.md."""
    with open("README.md", mode, encoding="utf-8") as file:
        file.write(content + "\n\n")


def combine_markdown_files() -> None:
    """Combines all markdown sections into README.md."""
    write_to_readme("<!-- markdownlint-disable -->", "w")

    # Integrate static markdown sections
    static_sections = ["./Markdown Sections/intro.md"]
    for section in static_sections:
        content = read_file(section)
        write_to_readme(content)

    # Generate and append skills section
    skills_data = read_json("./Markdown Sections/Section Data/skills.json")
    skills_md = generate_skills_section(skills_data, "Skills")
    write_to_readme(skills_md)

    # Generate and append connect section
    connect_data = read_json("./Markdown Sections/Section Data/connect.json")[
        "socialLinks"
    ]
    connect_md = generate_connect_section(connect_data)
    write_to_readme(connect_md)

    # Append 'about' section
    about_content = read_file("./Markdown Sections/about.md")
    write_to_readme(about_content)


combine_markdown_files()
