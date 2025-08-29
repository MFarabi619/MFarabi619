{
  # config,
  ...
}:
{
  services.cachix-agent = {
    enable = false;
    verbose = true;
    name = "archlinux";
    # host = null;
    # credentialsFile = "${config.xdg.configHome}/cachix-agent.token"; # default
  };
}
