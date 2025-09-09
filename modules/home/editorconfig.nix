{
  editorconfig = {
    enable = true;
    settings = {
      "*" = {
        indent_size = 2;
        charset = "utf-8";
        indent_style = "space";
        insert_final_newline = true;
        trim_trailing_whitespace = true;
      };

      "*.md" = {
        max_line_length = "off";
        trim_trailing_whitespace = false;
      };
    };
  };
}
