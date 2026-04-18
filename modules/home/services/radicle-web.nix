{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.radicle-web;
in
{
  options.services.radicle-web = {
    enable = lib.mkEnableOption "Radicle web UI (httpd + explorer)";

    httpd.port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port for radicle-httpd API server.";
    };

    explorer.port = lib.mkOption {
      type = lib.types.port;
      default = 3000;
      description = "Port for radicle-explorer web frontend.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellScriptBin "rad-web" ''
        ${pkgs.radicle-httpd}/bin/radicle-httpd --listen 127.0.0.1:${toString cfg.httpd.port} &
        HTTPD_PID=$!
        trap "kill $HTTPD_PID 2>/dev/null" EXIT
        echo "radicle-httpd started on :${toString cfg.httpd.port} (PID $HTTPD_PID)"
        echo "Serving explorer on :${toString cfg.explorer.port}..."
        echo "Open http://localhost:${toString cfg.explorer.port}/nodes/127.0.0.1:${toString cfg.httpd.port}"
        cd ${pkgs.radicle-explorer}
        ${pkgs.python3}/bin/python3 -m http.server ${toString cfg.explorer.port}
      '')
    ];
  };
}
