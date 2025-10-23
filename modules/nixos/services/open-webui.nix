{
pkgs,
...
}:
{
  services.open-webui = {
    port = 7777;
    enable = pkgs.stdenv.isx86_64;
    # openFirewall = false; # default
    # host = "127.0.0.1"; # default
    stateDir = "/var/lib/open-webui"; # default
    # environmentFile = "/var/lib/secrets/openWebuiSecrets";
    environment = {
      # WEBUI_AUTH = "True";
      DO_NO_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      ANONYMIZED_TELEMETRY = "False";
      # OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
    };
  };
}
