{
  config,
  pkgs,
  ...
}: let
  UID_GID = "${toString config.users.users.actual-budget.uid}:${toString config.users.groups.actual-budget.gid}";
  actual-version = "25.10.0";
in {
  users.users.actual-budget = {
    isSystemUser = true;
    uid = 800;
    group = "actual-budget";
  };
  users.groups.actual-budget.gid = config.users.users.actual-budget.uid;

  dockerCompose.actual-budget.composeFile = pkgs.writeText "docker-compose.yml" ''
    # Actual Budget - Docker Compose
    # Expects an environment variable UID_GID (format: "<uid>:<gid>") to run the container as a specific user.
    # Example: export UID_GID="800:800"

    name: actual-budget
    services:
      actual-budget:
        container_name: actual-budget
        image: "ghcr.io/actualbudget/actual:${actual-version}-alpine"
        user: "${UID_GID}"
        expose:
          - "5006"
        networks:
          reverse_proxy:
        volumes:
          - /srv/actual-budget:/data:rw
        healthcheck:
          test: ["CMD", "node", "src/scripts/health-check.js"]
          interval: 1m0s
          timeout: 10s
          retries: 3
          start_period: 20s
        restart: unless-stopped

    networks:
      reverse_proxy:
        external: true
  '';

  systemd.tmpfiles.rules = [
    "d /srv/actual-budget 0750 actual-budget actual-budget -"
  ];
}
