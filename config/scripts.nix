{
  pkgs,
  config,
  ...
}:
{
  scripts = {
    hello = {
      packages = with pkgs; [
        chafa
      ];
      description = "  👋 Show the Devenv logo art and a friendly greeting";
      exec = ''
        # chafa --align center "${config.git.root}/assets/devenv-symbol-dark-bg.png"
        # chafa --align center "${config.git.root}/assets/cover.png"
        echo "👋🧩"
      '';
    };

    doctor = {
      packages = with pkgs; [
        figlet
        shellspec
      ];

      description = " 💊 Run Microdoctor health-check suite with docs output";
      exec = ''
        figlet -cf slant "💊 Microdoctor";
        shellspec -c "${config.git.root}/tests" --quiet "$@";
      '';
    };

    ai = {
      description = "     🤖 Use the GPT LLM of your choice";
      exec = ''
        open-webui serve --port 1212
      '';
    };

    kernel = {
      description = " 🎉 Fire up the Microvisor Kernel";
      exec = ''
        process-compose
      '';
    };

    docs = {
      description = " 📚 RTFM";
      exec = "pnpx likec4 start ${config.git.root}/docs";
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

    di = {
      description = "      ⌨ Reload devenv";
      exec = ''
        set -ex
        direnv reload
      '';
    };

    dn = {
      description = "     💥 Nuke & reload devenv";
      exec = ''
        set -ex
        git clean -fdX -e '!.env*'
      '';
    };

    clean = {
      description = "  🧽 Remove all files matched by .gitignore (except any .env*)";
      exec = ''
        set -ex;
        git clean -fdX -e '!.env*' -e '!.devenv*' -e '!.direnv*'
      '';
    };

    nuke = {
      description = "   🚨 Remove all files matched by .gitignore, including .env*";
      exec = ''
        sudo git clean -fdX
      '';
    };
  };
}
