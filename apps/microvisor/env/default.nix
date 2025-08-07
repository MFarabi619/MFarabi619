{ pkgs, ... }:
let
  #====================================================
  #                       PORTS
  #====================================================
  PORTS = {
    DOCS = "4000";
    APP = "3000";
    API = "5150";
    ADMIN = "3000";
    LOCAL_NODE = "5000";
    ARCH = "5173";
    GRAPH = "4211";
    NODE_MODULES_INSPECTOR = "7800";
    POSTGRES = "54322";
  };
  #====================================================
  #                        URLS
  #====================================================
  URLS = {
    LOCALHOST = "http://localhost:";
    BASE = "https://mfarabi.sh";
  };
in
{
  imports = [
    ./db.nix
  ];

  env = rec {
    #====================================================
    #                  🏁 FLAGS 🏁
    #====================================================
    # SUPABASE="true"; # Requires Docker
    # SQLITE="true";
    NX_TUI = "false";
    NX_VERBOSE_LOGGING = "true";

    NEXT_PUBLIC_ENABLE_AUTOLOGIN = "true";

    ZELLIJ_AUTO_ATTACH = "true";
    ZELLIJ_AUTO_EXIT = "true";

    #====================================================
    #                    DATABASE
    #====================================================
    DATABASE_URI = "postgresql://postgres:postgres@127.0.0.1:${PORTS.POSTGRES}/postgres";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_22}/bin/node";

    #====================================================
    #                      URLS
    #====================================================
    BASE_URL = URLS.BASE;
    DOCS_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.DOCS}";
    APP_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.APP}";
    API_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.API}";
    ADMIN_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.ADMIN}";
    LOCAL_NODE_URL = "${URLS.LOCALHOST}${PORTS.LOCAL_NODE}/v1/graphql";
    ARCHITECTURE_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.ARCH}";
    GRAPH_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.GRAPH}";
    UI_LOCAL_URL = "6006";
    SUPABASE_STUDIO_URL = "http://localhost:54323";

    NODE_MODULES_INSPECTOR_PORT = "7000";

    PAYLOAD_SECRET = "YOUR_SECRET_HERE";

    CORS_WHITELIST_ORIGINS = "http://localhost:4200,http://localhost:8000,https://mfarabi.sh";
    CSRF_WHITELIST_ORIGINS = "http://localhost:4200,http://localhost:8000,https://mfarabi.sh";
  };
}
