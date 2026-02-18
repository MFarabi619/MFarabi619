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

  enterShell =''
        echo "👋🧩"
    ''
    + lib.optionalString (pkgs.stdenv.isLinux && config.services.caddy.enable) ''
      # sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0
    '';

  enterTest = ''
    echo "Running tests"
  '';
}
