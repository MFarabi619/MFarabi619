{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      forSystems = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ];
    in
    {
      packages = forSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          explorer = pkgs.radicle-explorer.withConfig {
            preferredSeeds = [{
              hostname = "git.apidae.systems";
              port = 443;
              scheme = "https";
            }];
          };

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
                root ${explorer};
                index index.html;
                location /api/ {
                  proxy_pass http://127.0.0.1:8080;
                  proxy_set_header Host $host;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                }
                location / {
                  try_files $uri $uri/ /index.html;
                }
              }
            }
          '';

          s6Services = pkgs.runCommand "s6-services" { } ''
            mkdir -p $out/etc/s6/radicle-node $out/etc/s6/radicle-httpd $out/etc/s6/nginx

            cat > $out/etc/s6/radicle-node/run <<'SCRIPT'
            #!/bin/sh
            exec ${pkgs.radicle-node}/bin/radicle-node --listen 0.0.0.0:8776
            SCRIPT
            chmod +x $out/etc/s6/radicle-node/run

            cat > $out/etc/s6/radicle-httpd/run <<'SCRIPT'
            #!/bin/sh
            exec ${pkgs.radicle-httpd}/bin/radicle-httpd --listen 0.0.0.0:8080
            SCRIPT
            chmod +x $out/etc/s6/radicle-httpd/run

            cat > $out/etc/s6/nginx/run <<'SCRIPT'
            #!/bin/sh
            exec ${pkgs.nginx}/bin/nginx -c ${nginxConf}
            SCRIPT
            chmod +x $out/etc/s6/nginx/run
          '';

          entrypoint = pkgs.writeTextFile {
            name = "entrypoint";
            executable = true;
            destination = "/bin/entrypoint";
            text = ''
              #!/bin/sh
              set -e
              if [ ! -d "$RAD_HOME/keys" ]; then
                echo "$RAD_PASSPHRASE" | ${pkgs.radicle-node}/bin/rad auth --stdin
              fi
              if [ ! -f "$RAD_HOME/config.json" ]; then
                ${pkgs.radicle-node}/bin/rad config init --alias apidae
              fi
              exec ${pkgs.s6}/bin/s6-svscan /etc/s6
            '';
          };
        in
        {
          default = pkgs.dockerTools.buildLayeredImage {
            name = "microvisor-radicle";
            tag = "latest";
            maxLayers = 120;

            contents = [
              pkgs.radicle-node
              pkgs.radicle-httpd
              explorer
              pkgs.nginx
              pkgs.s6
              pkgs.fakeNss
              pkgs.bashInteractive
              pkgs.wget
              s6Services
              entrypoint
            ];

            extraCommands = ''
              mkdir -p tmp data
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
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ];
              Volumes = {
                "/data" = {};
              };
            };
          };
        }
      );
    };
}
