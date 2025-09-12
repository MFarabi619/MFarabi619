{
  name = "🧮 Microvisor 🧮";

  infoSections = {
    name = [ "Mumtahin Farabi" ];
  };

  imports = [
    ./env
    ./tasks
    ./cachix
    ./scripts
    ./packages
    ./services
    ./processes
    ./languages
    ./git-hooks.nix
    ./containers.nix
    ./devcontainer.nix
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
