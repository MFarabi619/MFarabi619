{
  pkgs,
  ...
}:
{
  services.open-webui = {
    enable = pkgs.stdenv.isx86_64;
    port = 7777;
    host = "127.0.0.1";
    openFirewall = true;
    stateDir = "/var/lib/open-webui";
    environmentFile = "/var/lib/secrets/open-webui";
    environment = {
      # docs.openwebui.com/getting-started/env-configuration

      # ============================================== #
      # =============== 👋 GENERAL 👋 ================ #
      # ============================================== #

      WEBUI_URL = "https://ai.openws.org";
      ENABLE_SIGNUP = "True";
      ENABLE_SIGNUP_PASSWORD_CONFIRMATION = "True";
      ENABLE_LOGIN_FORM = "False"; # enable OAuth before setting to "False"
      DEFAULT_LOCALE = "en";
      DEFAULT_MODELS = "llama3.2:3b";
      DEFAULT_USER_ROLE = "user"; # pending | user | admin
      ENABLE_CHANNELS = "False";
      WEBHOOK_URL = "https://ai.openws.org/webhook";
      ENABLE_ADMIN_EXPORT = "False";
      ENABLE_ADMIN_CHAT_ACCESS = "False";
      BYPASS_ADMIN_ACCESS_CONTROL = "True";
      ENABLE_USER_WEBHOOKS = "True";
      THREAD_POOL_SIZE = "80";
      MODELS_CACHE_TTL = "300";
      ENV = "dev";
      ENABLE_PERSISTENT_CONFIG = "False";
      WEBUI_NAME = "🤖 Beep Boop 🤖";
      ENABLE_REALTIME_CHAT_SAVE = "False";

      # ============================================== #
      # ============= 📁 DIRECTORIES 📁 ============== #
      # ============================================== #

      # DATA_DIR = "./data";

      # ============================================== #
      # =============== 🦙 OLLAMA 🦙 ================= #
      # ============================================== #

      ENABLE_OLLAMA_API = "True";
      ENABLE_OLLAMA_DOCKER = "False";
      K8S_FLAG = "False";

      # ============================================== #
      # =============== 🤖 OPENAI 🤖 ================= #
      # ============================================== #

      ENABLE_OPENAI_API = "True";
      OPENAI_API_BASE_URL = "https://api.openai.com/v1";
      # OLLAMA_LOG_LEVEL="DEBUG";

      # ============================================== #
      # =============== 📋 TASKS 📋 ================== #
      # ============================================== #

      TASK_MODEL = "llama3.2:3b";
      TASK_MODEL_EXTERNAL = "gpt-oss:20b";
      ENABLE_FOLLOW_UP_GENERATION = "True";

      # ============================================== #
      # ========== 👩‍💻 CODE EXECUTION 👩‍💻 ============== #
      # ============================================== #

      ENABLE_CODE_EXECUTION = "True";
      CODE_EXECUTION_ENGINE = "pyodide";

      # ============================================== #
      # ========= 📋 CODE INTERPRETER 📋 ============= #
      # ============================================== #

      ENABLE_CODE_INTERPRETER = "False";
      CODE_INTERPRETER_ENGINE = "pyodide";

      # ============================================== #
      # ======== 🚨 SECURITY VARIABLES 🚨 ============ #
      # ============================================== #

      ENABLE_FORWARD_USER_INFO_HEADERS = "False";
      WEBUI_AUTH = "True";
      # WEBUI_SECRET_KEY = "";
      ENABLE_VERSION_UPDATE_CHECK = "True";
      SAFE_MODE = "False";

      # ============================================== #
      # ========== ↱ VECTOR DATABASE ↱ ============= #
      # ============================================== #

      VECTOR_DB = "chroma";

      # ============================================== #
      # ================ 🔒 OAUTH 🔒 =================== #
      # ============================================== #

      ENABLE_OAUTH_SIGNUP = "True";
      ENABLE_OAUTH_PERSISTENT_CONFIG = "True";
      OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "True"; # never enable for providers that don't verify email addresses, will lead to account takeover
      ENABLE_OAUTH_WITHOUT_EMAIL = "False";
      OAUTH_UPDATE_PICTURE_ON_LOGIN = "True";
      OAUTH_SCOPES = "openid email profile";
      OPENID_PROVIDER_URL = "https://accounts.google.com/.well-known/openid-configuration";
      OPENID_REDIRECT_URI = "https://ai.openws.org/oauth/oidc/callback";

      # GOOGLE_CLIENT_ID = "";
      # GOOGLE_CLIENT_SECRET = "";
      GOOGLE_OAUTH_SCOPE = "openid email profile";
      GOOGLE_REDIRECT_URI = "https://ai.openws.org/oauth/google/callback";

      DO_NO_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      ANONYMIZED_TELEMETRY = "False";

      ENABLE_DIRECT_CONNECTIONS = "True";

      # ============================================== #
      # =========== 🤸‍♀️ USER PERMISSIONS 🤸‍♀️ =========== #
      # ============================================== #

      USER_PERMISSIONS_CHAT_CONTROLS = "True";
      USER_PERMISSIONS_CHAT_VALVES = "True";
      USER_PERMISSIONS_CHAT_SYSTEM_PROMPT = "True";
      USER_PERMISSIONS_CHAT_PARAMS = "True";
      USER_PERMISSIONS_CHAT_FILE_UPLOAD = "True";
      USER_PERMISSIONS_CHAT_DELETE = "True";
      USER_PERMISSIONS_CHAT_EDIT = "True";
      USER_PERMISSIONS_CHAT_DELETE_MESSAGE = "True";
      USER_PERMISSIONS_CHAT_CONTINUE_RESPONSE = "True";
      USER_PERMISSIONS_CHAT_REGENERATE_RESPONSE = "True";
      USER_PERMISSIONS_CHAT_RATE_RESPONSE = "True";
      USER_PERMISSIONS_CHAT_STT = "True";
      USER_PERMISSIONS_CHAT_TTS = "True";
      USER_PERMISSIONS_CHAT_CALL = "True";
      USER_PERMISSIONS_CHAT_MULTIPLE_MODELS = "True";
      USER_PERMISSIONS_CHAT_TEMPORARY = "True";
      USER_PERMISSIONS_CHAT_TEMPORARY_ENFORCED = "True";

      # ============================================== #
      # ========= ✨ FEATURE PERMISSIONS ✨ ========== #
      # ============================================== #

      USER_PERMISSIONS_FEATURES_DIRECT_TOOL_SERVERS = "True";
      USER_PERMISSIONS_FEATURES_WEB_SEARCH = "True";
      USER_PERMISSIONS_FEATURES_IMAGE_GENERATION = "True";
      USER_PERMISSIONS_FEATURES_CODE_INTERPRETER = "True";

      # ============================================== #
      # ======== 🎡 WORKSPACE PERMISSIONS 🎡 ========= #
      # ============================================== #

      USER_PERMISSIONS_WORKSPACE_NOTES_ALLOW_PUBLIC_SHARING = "True";

      # ============================================== #
      # ====== 🔭 OPENTELEMETRY CONFIGURATION 🔭 ===== #
      # ============================================== #

      # ENABLE_OTEL = "False";
      # ENABLE_OTEL_TRACES = "False";
      # ENABLE_OTEL_METRICS = "False";
      # ENABLE_OTEL_LOGS = "False";
      # OTEL_EXPORTER_OTLP_ENDPOINT = "http://grafana:4317";
      # OTEL_SERVICE_NAME = "open-webui";
      # OTEL_BASIC_AUTH_USERNAME="";
      # OTEL_BASIC_AUTH_PASSWORD="";
      # OTEL_EXPORTER_OTLP_INSECURE = "true"; # Use insecure connection for OTLP, you may want to remove this in production

      # ============================================== #
      # ============= 📀 DATABASE POOL 📀 ============ #
      # ============================================== #

      # DATABASE_URL = "sqlite:///${DATA_DIR}/webui.db";
      # DATABASE_TYPE = "sqlite"; # sqlite | postgersql | sqlite+sqlcipher
      # DATABASE_USER = "";
      # DATABASE_PASSWORD = "";
      # DATABASE_HOST = "";
      # DATABASE_PORT = "";
      # DATABASE_NAME = "";
      # DATABASE_SCHEMA = "";
      # DATABASE_POOL_SIZE = "";
      # DATABASE_POOL_MAX_OVERFLOW = "";
      # DATABASE_POOL_TIMEOUT = "";
      # DATABASE_POOL_RECYCLE = "";
      DATABASE_ENABLE_SQLITE_WAL = "True";
      # REDIS = "rediss://:password@localhost:6379/0";
      # REDIS_SENTINEL_HOSTS = "";
      # REDIS_SENTINEL_PORT = 26379;
      # REDIS_CLUSTER = "False";
      # REDIS_KEY_PREFIX = "open-webui";
      ENABLE_WEBSOCKET_SUPPORT = "True";
    };
  };
}
