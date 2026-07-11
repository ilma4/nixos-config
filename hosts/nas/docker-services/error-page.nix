{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkIf mkMerge;

  cfg = config.traefikReverseProxy or {};

  errorPageConf = pkgs.writeText "error-page.conf" ''
    server {
        listen 80 default_server;
        error_page 404 /404.html;
        location / {
            return 404;
        }
        location = /404.html {
            root /usr/share/nginx/html;
            internal;
        }
    }
  '';

  errorPageHtml = pkgs.writeText "404.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <title>404 Not Found</title>
        <style>
            body { font-family: sans-serif; text-align: center; padding-top: 50px; }
            h1 { font-size: 50px; }
        </style>
    </head>
    <body>
        <h1>404</h1>
        <p>Not Found</p>
    </body>
    </html>
  '';

  composeYaml = ''
    services:
      error-page:
        image: docker.io/library/nginx:alpine
        container_name: traefik-error-page
        restart: always
        volumes:
          - ${errorPageConf}:/etc/nginx/conf.d/default.conf:ro
          - ${errorPageHtml}:/usr/share/nginx/html/404.html:ro
        networks:
          - reverse_proxy
        labels:
          - "traefik.enable=true"
          - "traefik.http.routers.catchall.rule=HostRegexp(`^.+\\.home\\.arpa$`) || Host(`home.arpa`)"
          - "traefik.http.routers.catchall.priority=1"
          - "traefik.http.routers.catchall.entrypoints=websecure"
          - "traefik.http.routers.catchall.tls=true"
          - "traefik.http.services.catchall.loadbalancer.server.port=80"

    networks:
      reverse_proxy:
        external: true
  '';
in {
  config = mkIf cfg.enable (mkMerge [
    {
      dockerCompose."error-page" = {
        composeText = composeYaml;
      };
    }
  ]);
}
