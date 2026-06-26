{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  # api = config.languages.rust.import ./. { };
  pkgs-unstable = import inputs.nixpkgs-unstable { system = pkgs.stdenv.system; };
in
{
  name = "microvisor";
  packages = with pkgs-unstable; lib.optionals pkgs.stdenv.isLinux [ openssl ];

  languages = {
    nix.enable = true;
    shell.enable = true;

    c.enable = true;
    c.debugger = pkgs.gdb;
    cplusplus.enable = true;

    typescript.enable = false;
    javascript = {
      bun.enable = true;
      package = pkgs.nodejs_26;
      enable = config.languages.typescript.enable;
    };
  };

  scripts = {
    up.exec = ''devenv up "$@"'';
    clean.exec = "git clean -fdX";
    run.exec = ''devenv tasks run "$@" -m before'';
    docs.exec = "bunx likec4 start ${config.git.root}/docs";
    tio.exec = ''HOME="$DEVENV_ROOT" ${pkgs.tio}/bin/tio "$@"'';
  };

  profiles.user."mfarabi".module.env = {
    # BASE_URL = "mfarabi.sh";
    EXERCISM_API_URL = "https://api.exercism.org/v1";
    LIBRARY_PATH = lib.mkIf pkgs.stdenv.isDarwin "/opt/homebrew/lib";
  };
}
