{
  pkgs,
  flake,
  config,
  ...
}:
{
  imports = [
    flake.inputs.lazyvim.homeManagerModules.default

    ./config.nix
    ./extras.nix
    ./plugins.nix
  ];

  programs = {
    neovim.defaultEditor = !config.services.emacs.defaultEditor;

    lazyvim = {
      enable = true;
      # pluginSource = "latest";
      # installCoreDependencies = false;
      ignoreBuildNotifications = false;
    };
  };
}
