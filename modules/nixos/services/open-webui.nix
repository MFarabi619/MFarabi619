{
  services.open-webui = {
   enable = false;
    port = 8080;
    host = "127.0.0.1";
    stateDir = "/var/lib/open-webui";
    environment = {
      # WEBUI_AUTH = "True";
      DO_NO_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      ANONYMIZED_TELEMETRY = "False";
      # OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
    };
  };
}
