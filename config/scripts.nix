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

    clean = {
      description = "   🚨 Remove all files matched by .gitignore, including .env*";
      exec = "git clean -fdX";
    };
  };
}
