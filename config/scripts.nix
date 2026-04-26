{
  pkgs,
  config,
  ...
}:
{
  scripts = {
    docs = {
      description = " 📚 RTFM";
      exec = "bunx likec4 start ${config.git.root}/docs";
    };

    run = {
      exec = ''devenv tasks run "$@" -m before'';
    };

    up = {
      description = " 🎉 Fire up the Microvisor Kernel";
      exec = ''devenv up "$@"'';
    };

    console = {
      packages = with pkgs; [
        ttyd
      ];
      description = "🕹  Fire up the Microvisor Console";
      exec = ''
        ttyd --writable --browser --url-arg --once process-compose
      '';
    };

    clean = {
      description = "   🚨 Remove all files matched by .gitignore, including .env*";
      exec = "git clean -fdX";
    };
  };
}
