{
  imports = [
    ./doctor.nix
    ./hello.nix
  ];

  scripts = {

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

    console = {
      description = "🕹  Fire up the Microvisor Console";
      exec = ''
        ttyd --writable --browser --url-arg --once process-compose
      '';
    };

    di = {
      description = "      ⌨ Reload devenv";
      exec = "set -ex; direnv reload";
    };

    dn = {
      description = "     💥 Nuke & reload devenv";
      exec = "set -ex; git clean -fdX -e '!.env*'";
    };

    clean = {
      description = "  🧽 Remove all files matched by .gitignore (except any .env*)";
      exec = "set -ex; git clean -fdX -e '!.env*' -e '!.devenv*' -e '!.direnv*'";
    };

    nuke = {
      description = "   🚨 Remove all files matched by .gitignore, including .env*";
      exec = ''
        sudo git clean -fdX
      '';
    };
  };
}
