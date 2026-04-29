{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      nginxConf = pkgs.writeText "nginx.conf" ''
        pid /tmp/nginx.pid;
        daemon off;
        error_log /dev/stderr info;

        events {
          worker_connections 128;
        }

        http {
          include ${pkgs.nginx}/conf/mime.types;
          access_log /dev/stdout;

          client_body_temp_path /tmp/nginx_client_body;
          proxy_temp_path /tmp/nginx_proxy;
          fastcgi_temp_path /tmp/nginx_fastcgi;
          uwsgi_temp_path /tmp/nginx_uwsgi;
          scgi_temp_path /tmp/nginx_scgi;

          server {
            listen 3000;

            root ${pkgs.radicle-explorer};
            index index.html;

            location /api/ {
              proxy_pass http://127.0.0.1:8080;
              proxy_set_header Host $host;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            }

            location = /config.json {
              alias /tmp/radicle-config.json;
            }

            location / {
              try_files $uri $uri/ /index.html;
            }
          }
        }
      '';

      entrypoint = pkgs.writeShellScriptBin "entrypoint" ''
        set -e

        if [ ! -d "$RAD_HOME/keys" ]; then
          echo "$RAD_PASSPHRASE" | ${pkgs.radicle-node}/bin/rad auth --stdin
        fi

        cat > /tmp/radicle-config.json <<CONF
        {
          "nodes": {
            "fallbackPublicExplorer": "https://radicle.network/nodes/\$host/\$rid\$path",
            "requiredApiVersion": "~0.18.0",
            "defaultHttpdPort": 443,
            "defaultLocalHttpdPort": 8080,
            "defaultHttpdScheme": "https"
          },
          "source": {
            "commitsPerPage": 30
          },
          "preferredSeeds": [
            {
              "hostname": "''${RADICLE_DOMAIN:-localhost}",
              "port": 443,
              "scheme": "https"
            }
          ]
        }
        CONF

        ${pkgs.radicle-node}/bin/radicle-node --listen 0.0.0.0:8776 &
        ${pkgs.radicle-httpd}/bin/radicle-httpd --listen 0.0.0.0:8080 &
        exec ${pkgs.nginx}/bin/nginx -c ${nginxConf}
      '';
    in
    {
      packages.${system}.default = pkgs.dockerTools.buildLayeredImage {
        name = "microvisor-radicle";
        tag = "latest";
        maxLayers = 120;

        contents = [
          pkgs.radicle-node
          pkgs.radicle-httpd
          pkgs.radicle-explorer
          pkgs.nginx
          pkgs.fakeNss
          pkgs.coreutils
          pkgs.bash
          pkgs.curl
          pkgs.git
          entrypoint
        ];

        extraCommands = ''
          mkdir -p tmp
          mkdir -p data
        '';

        config = {
          Entrypoint = [ "${entrypoint}/bin/entrypoint" ];
          ExposedPorts = {
            "3000/tcp" = {};
            "8080/tcp" = {};
            "8776/tcp" = {};
          };
          Env = [
            "RAD_HOME=/data"
            "SSL_CERT_FILE=${pkgs.cacerts}/etc/ssl/certs/ca-bundle.crt"
          ];
          Volumes = {
            "/data" = {};
          };
        };
      };
    };
}
