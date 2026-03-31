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

  name = "🧮 Microvisor 🧮";

  infoSections = {
    name = [ "Mumtahin Farabi" ];
  };

  imports = map (path: ./config + path) [
    "/files"
    "/env.nix"
    "/services"
    "/languages"
    "/microvisor"
    "/tasks.nix"
    "/cachix.nix"
    "/embassy.nix"
    "/scripts.nix"
    "/packages.nix"
    "/processes.nix"
    "/containers.nix"
    "/platformio.nix"
    "/devcontainer.nix"
  ];

  enterShell = ''
    echo "👋🧩"
  ''
  + lib.optionalString (pkgs.stdenv.isLinux && config.services.caddy.enable) ''
    # sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
  '';

  enterTest = ''
    echo "Running tests"
  '';
}
