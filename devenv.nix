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

  profiles =
    { }
    // lib.optionalAttrs config.services.postgres.enable {
      user."mfarabi".module.env = {
        BASE_URL = "mfarabi.sh";
        EXERCISM_API_URL = "https://api.exercism.org/v1";
        # PGUSER = "mfarabi";
        # PGDATABASE = "postgres";
        # PGPORT = config.services.postgres.port;
        # PGHOST = config.services.postgres.listen_addresses;
      };
      # }
      # // lib.optionalAttrs config.microvisor.embassy.enable {
      #   ci.module.microvisor.embassy."probe-rs".server.address = "0.0.0.0";
      #   hostname.rpi5-16.extends = [ "ci" ];
      #   hostname.framework-desktop.extends = [ "ci" ];
    };

  env = {
    ZELLIJ_AUTO_EXIT = "true";
    ZELLIJ_AUTO_ATTACH = "true";
    # PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    # PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_22}/bin/node";
  };

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

  # nix profile install github:fuellabs/fuel.nix#fuel
  # cachix use fuellabs
  # fuel-labs:
  #   url: github:fuellabs/fuel.nix
  #   or
  #   url: github:fuellabs/fuel.nix#fuel-nightly
  # nix profile list

  enterTest = ''
    echo "Running tests"
  '';
}
