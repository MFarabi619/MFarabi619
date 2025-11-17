{
  services.nginx = {
    enable = false;
    statusPage = true; # enable http://127.0.0.1:80/nginx_status
    virtualHosts = {
      "_" = {
        default = true;
        root = "/var/www/html";
        locations = {
          "/" = {
            index = "index.html";
          };
        };

        listen = [
          {
            addr = "0.0.0.0";
            port = 90;
          }
        ];
      };
    };
  };
}
