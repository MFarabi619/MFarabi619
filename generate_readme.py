import json
from typing import Dict, List


def read_file(file_path: str) -> str:
    """Read and return the content of file"""
    try:
        with open(file_path, "r", encoding="utf-8") as file:
            return file.read()
    except FileNotFoundError:
        print(f"Warning: {file_path} not found. Will be skipped.")
        return ""


def read_json(file_path: str) -> Dict:
    """Read and return from JSON file"""
    try:
        with open(file_path, "r", encoding="utf-8") as file:
            return json.load(file)
    except FileNotFoundError:
        print(f"Error: JSON file at {file_path} not found.")
        return {}


def generate_skills_section(
    data: Dict[str, Dict[str, List[Dict]]],
) -> str:
    """Generate markdown for 'Skills' section based on provided data"""
    content = """Please note that my technical competency fluctuates based on my active projects.<br/>
            I learn (and often forget) things as I go, and regularly rotate between different problem areas.<br/><br/>
            <div class="tg-wrap" align="center">
            <table>
            <thead>
            <tr>
            """
    
    # Add table headers for each main category (Languages, Frameworks & Libraries, Tools)
    content += (
        "".join([f"<th>{category}</th>" for category in next(iter(data.values())).keys()])
        + """</tr>
          </thead>
          <tbody>
    """
    )

    # Helper function to generate table rows for each category and their respective items
    def generate_category_rows(category: str, category_data: Dict[str, List[Dict]]) -> str:
        rows = f"""<tr>
              <td colspan="3" align="center">
                <b>{category}</b>
              </td>
            </tr>
            <tr>
        """
        for subcategory, items in category_data.items():
            rows += "        <td align='center'>\n"
            for item in items:
                width = item.get("width", "40")
                height = item.get("height", "40")
                alt_text = item.get("alt", f"{item['name']} Logo")
                rows += f'          <!-- {item["name"]} -->\n'
                rows += (
                    f'          <a href="{item["url"]}" target="_blank" rel="noreferrer">\n'
                )
                rows += f'            <img src="{item["icon"]}" alt="{alt_text}" width="{width}" height="{height}"/>\n          </a>\n'
            rows += "        </td>\n"
        rows += "    </tr>\n"
        return rows

    # Generate rows for each main category: Actively Using, Previously Used, Would like to learn
    content += generate_category_rows("Actively Using", data["Actively Using"])
    content += generate_category_rows("Previously Used", data["Previously Used"])
    content += generate_category_rows("Intend to Use in Future", data["Would like to learn"])

    content += """</tbody>
    </table>
    </div>

"""
    return content


def generate_connect_section(social_links: List[Dict[str, str]]) -> str:
    """Generate markdown content for 'connect' section based on data"""
    markdown_content = "🔗 **Connect with me**:<br/><br/>"
    for link in social_links:
        markdown_content += f'<a href="{link["url"]}" target="blank"><img src="{link["icon"]}" alt="{link["alt"]}" height="{link["height"]}" width="{link["width"]}" /></a>'
    return markdown_content


def write_to_readme(content: str, mode: str = "a") -> None:
    """Write content to README.md"""
    with open("README.md", mode, encoding="utf-8") as file:
        file.write(content)


def combine_markdown_files() -> None:
    """Combine markdown sections into README.md"""
    write_to_readme("<!-- markdownlint-disable -->", "w")

    # Integrate static markdown sections
    static_sections = ["./Markdown Sections/intro.md"]
    for section in static_sections:
        content = read_file(section)
        write_to_readme(content)

    # Generate and append skills section
    skills_data = read_json("./Markdown Sections/Section Data/skills.json")
    skills_md = generate_skills_section(skills_data)
    write_to_readme(skills_md)

    # Append 'Current Setup' section
    current_setup = read_file("./Markdown Sections/current_setup.md")
    write_to_readme(current_setup)

    # Append 'About' section
    about_content = read_file("./Markdown Sections/about.md")
    write_to_readme(about_content)

    # Append 'Connect' section
    connect_md = read_file("./Markdown Sections/connect.md")

    write_to_readme(connect_md)


# Entry point
combine_markdown_files()
