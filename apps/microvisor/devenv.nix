{
  pkgs,
  ...
}:
{
  name = "🧮 microvisor 🧮";

  imports = [
    ./cachix
    ./env
    ./languages
    ./packages
    ./processes
    ./scripts
    ./services
    ./tasks
  ];

  packages = with pkgs; [
    eza
    bat
  ];

  # NOTE: uses native nixos test syntax | nixos.org/manual/nixos/stable/#sec-writing-nixos-tests
  enterTest = ''
    set -ex
    # process-compose down
  '';

  enterShell = ''
    devenv info
    hello
  '';

  starship = {
    enable = false;
    config = {
      enable = false;
      path = ./starship.toml;
    };
  };
}
