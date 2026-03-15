{
  config,
  ...
}:
{
  # env.OPENCODE_CONFIG = "${config.git.root}/.devenv/state/opencode/opencode.json";

  files."${config.git.root}/opencode.json".json = {
    "$schema" = "https://opencode.ai/config.json";

    tools = {
      bash = true;
      # edit = "ask";
      write = true;
      read = true;
      grep = true;
      list = true;
      glob = true;
      skill = true;
      webfetch = true;
      question = true;
      todowrite = true;
    };

    mcp = {
      devenv = {
        enabled = true;
        type = "local";
        command = [
          "devenv"
          "mcp"
        ];
      };

      likec4 = {
        enabled = true;
        type = "local";
        command = [
          "likec4"
          "mcp"
          "${config.git.root}/docs"
        ];
      };

      supabase = {
        enabled = true;
        type = "remote";
        url = "http://localhost:54321/mcp?features=docs%2Cdatabase%2Cdebugging%2Cdevelopment";
      };

      pulumi = {
        enabled = true;
        type = "remote";
        url = "https://mcp.ai.pulumi.com/mcp";
      };

      nx = {
        enabled = true;
        type = "local";
        command = [
          "nx"
          "mcp"
        ];
      };
    };
  };
}
