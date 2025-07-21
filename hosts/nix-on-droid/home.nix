{
  config,
  lib,
  pkgs,
  ...
}:

{
  home = {
    stateVersion = "24.05";
    packages = with pkgs; [
    ];

  };
  # insert home-manager config
}
