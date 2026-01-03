{
  pkgs,
  flake,
  ...
}:
{
  imports = [
    flake.inputs.lazyvim.homeManagerModules.default

    ./config.nix
    ./extras.nix
    ./plugins.nix
  ];

  programs.lazyvim = {
    enable = true;
    # pluginSource = "latest";
    # installCoreDependencies = false;
    ignoreBuildNotifications = false;
  };
}
