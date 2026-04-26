{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
# let
#   api = config.languages.rust.import ./. { };
# in
{
  # packages = [
  #   api
  # ];

  name = "microvisor";

  infoSections = {
    name = [ "Mumtahin Farabi" ];
  };

  imports = map (path: ./config + path) [
    "/env.nix"
    "/services"
    "/languages"
    "/tasks.nix"
    "/microvisor"
    "/embassy.nix"
    "/scripts.nix"
    "/packages.nix"
    "/processes.nix"
    "/containers.nix"
    "/devcontainer.nix"
  ];

  enterShell = ''
    echo "👋🧩"
  ''
  + lib.optionalString (pkgs.stdenv.isLinux && config.services.caddy.enable) ''
    # sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
  '';



  cachix = {
    enable = true;
    push = "mfarabi";
    pull = [
      "cachix"
      "oxalica"
      "devenv"
      "nixpkgs"
      "mfarabi"
      "emacs-ci"
      "nix-darwin"
      "nix-community"
      "pre-commit-hooks"
    ];
  };


  enterTest = ''
    echo "Running tests"
  '';
}
