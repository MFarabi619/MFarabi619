{
  config,
  ...
}:
{
  programs.opencode = {
    enable = true;
    web.enable = true;
    tui.theme = "gruvbox";
    web.extraArgs = [ "--mdns" ];
    enableMcpIntegration = true;

    settings = {
      autoshare = false;
      autoupdate = false;
      server.mdns = true;
      model = "ollama/qwen3.5:35b-a3b-coding-nvfp4";
      disabled_providers = [
        "gemini"
        "openai"
      ];

      provider.ollama = {
        name = "Ollama (local)";
        npm = "@ai-sdk/openai-compatible";
        models."qwen3.5:35b-a3b-coding-nvfp4".name = "qwen3.5:35b-a3b-coding-nvfp4";
        "options"."baseURL" =
          "http://${config.services.ollama.host}:${builtins.toString config.services.ollama.port}/v1";
      };

      permission = {
        read = "allow";
        bash = "allow";
        edit = "allow";
        grep = "allow";
        glob = "allow";
        list = "allow";
        write = "allow";
        skill = "allow";
        webfetch = "allow";
        question = "allow";
        todowrite = "allow";
      };
    };

    rules = ''
      General Project Rules
      ## External File Loading

      CRITICAL: When you encounter a file reference (e.g., @rules/general.md), use your Read tool to load it on a need-to-know basis. They're relevant to the SPECIFIC task at hand.

      # Taste

      - I have a strong preference for modular, re-usable code.
      - I'm a strong advocate for test-driven development, and prefer to develop against a test suite.
      - When doing feature development, move slow, and correct. Do not rush. Start with small parts and get them working.

      ## Instructions

      ### General

      - Do NOT preemptively load all references - use lazy loading based on actual need.
      - When loaded, treat content as mandatory instructions that override defaults.
      - Follow references recursively when needed.

      ### Tooling

      - If @devenv.nix along with an @.envrc exists at the repository root, that means I'm using Devenv - https://devenv.sh, and direnv.
        - Always do `direnv allow` before running commands as you may have been launched from outside the directory and may not have access.
          to the environment variables, scripts, tasks, and processes in your shell context until that.
        - If you suspect that a command for an app failure may be related to devenv shell not instantiating or direnv hooks not loading properly,
          stop immediately and ask me for help.

      ### Taste

      - Languages: Look to always use existing features and standard libraries of the programming language to its full potential instead of making custom data structures and functions.
      - Variables: NEVER use single letter or short names. `temperature_celcius` is preferred as opposed `temp`. Avoid repeating variable names again and again. Prefer to factor into structs, functions, and directories. Duplicated and repetitive naming causes extreme grep pollution.
      - Functions: look to keep functions monadic, which means only take a single argument. If a diadic function (two arguments) significantly simplifies things, then prefer that. Always avoid going any higher than diadic (triadic, quadratic, etc.).
      - Libraries: When encountering existing libraries, ALWAYS look to use existing abstractions from the library to keep the volume of our own code low.
        - If you're not familiar with the library APIs let me know and I'll checkout the source of the library to my git root for you to scan and delete it after.

      ### Philosophy

      - Keep things simple. Your greatest priority is to remove code, not create more of it.
      - Think outside the box to see if there's a no-code solution to the user experience problem at hand. Authoring software is our last resort, not primary. Always avoid throwing more code at the problem.
      - Dig deep beneath the problem to eliminate it or sidestep it altogether rather than applying a solution. We have a limited amount of time and bandwidth, and need to pick our battles carefully.
      - Always avoid writing custom code and shop around for existing standard, libraries, features, approaches etc. The more code we write the more code we have to maintain.
      - Refactor early and refactor often. If you come across an area that could be improved, don't ignore it. Just patch it up as you pass by. Always leave code better than you found it. Ideally less lines and more readable for humans.
    '';
  };
}
