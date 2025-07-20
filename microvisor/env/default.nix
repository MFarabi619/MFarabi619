{
  imports = [
    ./db.nix
  ];

  # NOTE: existing env vars in devenv.nix will have priority
  dotenv = {
    enable = true;
    filename = [
      ".env"
    ];
  };

  env = {
    #====================================================
    #                  🏁 FLAGS 🏁
    #====================================================
    # SUPABASE="true"; # Requires Docker
    # SQLITE="true";
    NX_TUI = "false";
    NX_VERBOSE_LOGGING = "true";
    NEXT_PUBLIC_ENABLE_AUTOLOGIN = "true";
    # TERM = "xterm-256color";
    ZELLIJ_AUTO_ATTACH = "true";
    ZELLIJ_AUTO_EXIT = "true";

    #====================================================
    #                      PORTS
    #====================================================
    APP_DEV_SERVER_PORT = "3000";
    ADMIN_DEV_SERVER_PORT = "8000";
    API_SERVER_PORT = "5150";
    UI_SERVER_PORT = "6006";
    DOCS_DEV_SERVER_PORT = "4000";
    ARCHITECTURE_DEV_SERVER_PORT = "5173";
    GRAPH_DEV_SERVER_PORT = "4211";
    NODE_MODULES_INSPECTOR_PORT = "7000";

    #====================================================
    #                      URLS
    #====================================================
    BASE_URL = "https://mira.ly";
    LOCALHOST_STRING = "http://localhost";

    APP_LOCAL_URL = "http://localhost:3000";
    ADMIN_LOCAL_URL = "http://localhost:8000";
    API_SERVER_LOCAL_URL = "http://localhost:8080";
    DOCS_LOCAL_URL = "http://localhost:4000";
    ARCHITECTURE_LOCAL_URL = "http://localhost:5173";
    GRAPH_LOCAL_URL = "http://localhost:4211";
    SUPABASE_STUDIO_URL = "http://localhost:54323";

    PAYLOAD_SECRET = "YOUR_SECRET_HERE";

    CORS_WHITELIST_ORIGINS = "http://localhost:4200,http://localhost:8000,https://mfarabi.sh";
    CSRF_WHITELIST_ORIGINS = "http://localhost:4200,http://localhost:8000,https://mfarabi.sh";
  };
}
