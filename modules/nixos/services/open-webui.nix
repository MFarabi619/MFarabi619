{
  pkgs,
  ...
}:
{
  services.open-webui = {
    enable = pkgs.stdenv.isx86_64;
    port = 7777;
    host = "0.0.0.0";
    openFirewall = true;
    stateDir = "/var/lib/open-webui";
    environmentFile = "/var/lib/secrets/open-webui";
    # docs.openwebui.com/getting-started/env-configuration
    environment = {
      ENV = "dev";
      DEFAULT_LOCALE = "en";
      ENABLE_PERSISTENT_CONFIG = "False";

      WEBUI_NAME = "🤖 Beep Boop 🤖";
      WEBUI_URL = "https://ai.openws.org" ;

      WEBHOOK_URL= "https://ai.openws.org/webhook";
      ENABLE_ADMIN_EXPORT = "False";
      ENABLE_ADMIN_CHAT_ACCESS = "False";

      WEBUI_AUTH = "True";
      ENABLE_SIGNUP = "True";
      # WEBUI_SECRET_KEY = "";
      ENABLE_LOGIN_FORM = "False"; # enable OAuth before setting to "False"
      ENABLE_SIGNUP_PASSWORD_CONFIRMATION = "True";

      ENABLE_OAUTH_SIGNUP = "True";
      ENABLE_OAUTH_WITHOUT_EMAIL = "False";
      OAUTH_SCOPES = "openid email profile";
      OAUTH_UPDATE_PICTURE_ON_LOGIN = "True";
      OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "True";
      ENABLE_OAUTH_PERSISTENT_CONFIG = "false";
      OPENID_PROVIDER_URL = "https://accounts.google.com/.well-known/openid-configuration";
      OPENID_REDIRECT_URI="https://ai.openws.org/oauth/oidc/callback";

      GOOGLE_OAUTH_SCOPE = "openid email profile";
      # GOOGLE_CLIENT_ID = "";
      # GOOGLE_CLIENT_SECRET = "";
      GOOGLE_REDIRECT_URI = "https://ai.openws.org/oauth/google/callback";

      DO_NO_TRACK = "True";
      ENABLE_OTEL = "false";
      SCARF_NO_ANALYTICS = "True";
      ENABLE_OTEL_METRICS = "false";
      ANONYMIZED_TELEMETRY = "False";
      # OTEL_SERVICE_NAME = "open-webui";
      # OTEL_BASIC_AUTH_USERNAME="";
      # OTEL_BASIC_AUTH_PASSWORD="";
      # OTEL_EXPORTER_OTLP_INSECURE = "true"; # Use insecure connection for OTLP, you may want to remove this in production
      # OTEL_EXPORTER_OTLP_ENDPOINT = "http://grafana:4317";

      # OLLAMA_LOG_LEVEL="DEBUG";
      # OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";

      DEFAULT_USER_ROLE = "user"; # pending | user | admin
      DEFAULT_MODELS = "gpt-oss:20b gpt-oss:120b qwen2.5-coder:32b llama3.2:3b codellama:70b phind-codellama:34b";

      ENABLE_USER_WEBHOOKS = "True";
      ENABLE_DIRECT_CONNECTIONS = "True";
    };
  };
}
