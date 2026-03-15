{
  programs.mcp = {
    enable = false; # FIXME: programs in mcp server commands not found
    servers = {
      # likec4 = {
      #   command = "pnpx";
      #   args = [
      #     "-y"
      #     "@likec4/mcp"
      #   ];
      # };
      # context7 = {
      #   url = "https://mcp.context7.com/mcp";
      #   headers = {
      #     CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
      #   };
      # };

      devenv = {
        command = "devenv mcp";
      };
    };
  };
}
