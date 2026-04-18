{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.radicle-web;

  lighttpdConfig = pkgs.writeText "radicle-explorer-lighttpd.conf" ''
    server.document-root = "${pkgs.radicle-explorer}"
    server.port = ${toString cfg.explorer.port}
    server.bind = "127.0.0.1"
    server.error-handler-404 = "/index.html"
    mimetype.assign = (
      ".html" => "text/html",
      ".css" => "text/css",
      ".js" => "application/javascript",
      ".json" => "application/json",
      ".svg" => "image/svg+xml",
      ".png" => "image/png",
      ".woff2" => "font/woff2",
      ".wasm" => "application/wasm",
      ".webmanifest" => "application/manifest+json"
    )
  '';
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
        ${pkgs.lighttpd}/bin/lighttpd -D -f ${lighttpdConfig}
      '')
    ];
  };
}
