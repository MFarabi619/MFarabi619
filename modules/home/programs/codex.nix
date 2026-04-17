{
  config,
  ...
}:
{
  programs.codex = {
    enable = false;
    enableMcpIntegration = config.programs.mcp.enable;

    # context = ''
    #   - Always respond with emojis
    # '';

    # rules = {
    #   default = "prefix_rule(pattern = [\"nix\", \"build\"], decision = \"allow\")\n";
    #   github = ./codex/github.rules;
    # };
  };
}
