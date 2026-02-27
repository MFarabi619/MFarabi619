{
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      hyperlinks = true;
      # line-numbers = true;
      # side-by-side = true;
      keep-plus-minus-markers = false;
      # whitespace-error-style = "22 reverse";
      hyperlinks-file-link-format = "lazygit-edit://{path}:{line}";
    };
  };
}
