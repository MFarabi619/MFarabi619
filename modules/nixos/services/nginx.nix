{
  config,
  flake,
  ...
}:
let
  cgit = config.services.cgit."cgit";
in
{
  services.nginx = {
    inherit (cgit) enable;
    defaultHTTPListenPort = 82;
    defaultSSLListenPort = 445;

    virtualHosts."${cgit.nginx.virtualHost}".locations = {
      "= /gruvbox.cgit.css".alias = "${flake.self}/assets/gruvbox.cgit.css";
      "= ${cgit.settings.favicon}".alias = "${flake.self}/assets/static/public/favicon.svg";
    };

    # statusPage = true; # enable http://127.0.0.1:80/nginx_status
    # virtualHosts = {
    #   "_" = {
    #     default = true;
    #     root = "/var/www/html";
    #     locations = {
    #       "/" = {
    #         index = "index.html";
    #       };
    #     };

    #     listen = [
    #       {
    #         addr = "0.0.0.0";
    #         port = 90;
    #       }
    #     ];
    #   };
    # };
  };
}
