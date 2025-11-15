{
  imports = [
    ./config.nix
    ./plugins.nix
    ./extras.nix
  ];

  programs.lazyvim = {
    enable = true;
    # pluginSource = "latest";
    # installCoreDependencies = false;
    ignoreBuildNotifications = false;
  };
}
