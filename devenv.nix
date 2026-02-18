{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
{
  name = "🧮 Microvisor 🧮";

  infoSections = {
    name = [ "Mumtahin Farabi" ];
  };

  imports = map (path: ./config + path) [
    "/files"
    "/env.nix"
    "/services"
    "/languages"
    "/tasks.nix"
    "/frameworks"
    "/cachix.nix"
    "/scripts.nix"
    "/packages.nix"
    "/processes.nix"
    "/git-hooks.nix"
    "/containers.nix"
    "/devcontainer.nix"
  ];

  # NOTE: uses native nixos test syntax | nixos.org/manual/nixos/stable/#sec-writing-nixos-tests
  enterTest = ''
    set -ex
    # process-compose down
  '';

  enterShell =
    ""
    + lib.optionalString (pkgs.stdenv.isLinux && config.services.caddy.enable) ''
      # sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
    '';
}
