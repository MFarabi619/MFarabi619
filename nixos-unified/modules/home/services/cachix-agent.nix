{
  # config,
  ...
}:
{
  services.cachix-agent = {
    enable = false;
    verbose = true;
    name = "";
    host = "";
    # credentialsFile = "${config.xdg.configHome}/cachix-agent.token";
  };
}
