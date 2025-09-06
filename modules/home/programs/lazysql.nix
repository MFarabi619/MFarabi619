{
  programs.lazysql = {
    enable = true;
    settings = {
      application = {
        DefaultPageSize = 300;
        DisableSidebar = false;
        SidebarOverlay = false;
      };

      database = [
        {
          Name = "💻 Development";
          URL = "postgresql://postgres:postgres@127.0.0.1:54322/postgres?sslmode=disable";
          Provider = "postgres";
          Username = "";
          Password = "";
          Hostname = "";
          Port = "";
          DBName = "postgres";
          URLParams = "";
          Commands = [ ];
        }
        {
          Name = "🚢 Production";
          URL = "postgres://postgres:password@127.0.0.1:5432/postgres?sslmode=false";
          Provider = "postgres";
          Username = "";
          Password = "";
          Hostname = "";
          Port = "";
          DBName = "postgres";
          URLParams = "";
          Commands = [ ];
        }
        {
          Name = "🐁 SQLite";
          URL = "./libs/db/sqlite.db";
          Provider = "sqlite3";
          Username = "";
          Password = "";
          Hostname = "";
          Port = "";
          DBName = "";
          URLParams = "";
          Commands = [ ];
        }
        {
          Name = "❄ devenv";
          URL = ".devenv/nix-eval-cache.db";
          Provider = "sqlite3";
          Username = "";
          Password = "";
          Hostname = "";
          Port = "";
          DBName = "";
          URLParams = "";
          Commands = [ ];
        }
      ];
    };
  };
}
