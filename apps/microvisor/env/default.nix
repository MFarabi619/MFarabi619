{ pkgs, ... }:
let
  #====================================================
  #                       PORTS
  #====================================================
  PORTS = {
    APP = "3000";
    API = "5150";
    DOCS = "4000";
    ARCH = "5173";
    ADMIN = "3000";
    GRAPH = "4211";
    POSTGRES = "54322";
    LOCAL_NODE = "5000";
    NODE_MODULES_INSPECTOR = "7800";
  };
  #====================================================
  #                        URLS
  #====================================================
  URLS = {
    LOCALHOST = "http://localhost:";
    BASE = "https://mfarabi.sh";
    EXERCISM = "https://api.exercism.org/v1";
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

    ZELLIJ_AUTO_ATTACH = "true";
    ZELLIJ_AUTO_EXIT = "true";

    #====================================================
    #                    DATABASE
    #====================================================
    # DATABASE_URI = "postgresql://postgres:postgres@127.0.0.1:${PORTS.POSTGRES}/postgres";
    HYDRA_DBI="dbi:Pg:dbname=postgres;host=postgresql://postgres:postgres@127.0.0.1:${PORTS.POSTGRES}/postgres;user=postgres;";
    HYDRA_DATA="/var/lib/hydra";
    PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "true";
    PLAYWRIGHT_NODEJS_PATH = "${pkgs.nodejs_22}/bin/node";

    UI_LOCAL_URL = "6006";
    API_SERVER_PORT = "5150";
    APP_DEV_SERVER_PORT = "3000";
    DOCS_DEV_SERVER_PORT = "4000";
    ADMIN_DEV_SERVER_PORT = "8000";
    GRAPH_DEV_SERVER_PORT = "4211";
    NODE_MODULES_INSPECTOR_PORT = "7000";
    ARCHITECTURE_DEV_SERVER_PORT = "5173";

    #====================================================
    #                      URLS
    #====================================================
    BASE_URL = URLS.BASE;
    SUPABASE_STUDIO_URL = "http://localhost:54323";
    APP_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.APP}";
    API_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.API}";
    DOCS_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.DOCS}";
    ADMIN_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.ADMIN}";
    GRAPH_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.GRAPH}";
    ARCHITECTURE_LOCAL_URL = "${URLS.LOCALHOST}${PORTS.ARCH}";
    LOCAL_NODE_URL = "${URLS.LOCALHOST}${PORTS.LOCAL_NODE}/v1/graphql";

    PAYLOAD_SECRET = "YOUR_SECRET_HERE";

    CORS_WHITELIST_ORIGINS = "http://localhost:4200,http://localhost:8000,https://mfarabi.sh";
    CSRF_WHITELIST_ORIGINS = "http://localhost:4200,http://localhost:8000,https://mfarabi.sh";
  };
}
