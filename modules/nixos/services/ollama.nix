{
  config,
  lib,
  ...
}:
{
  services.ollama = {
    enable = true;
    port = 11434;
    host = "0.0.0.0";
    openFirewall = true;
    # acceleration = "rocm"; # amd
    # acceleration = "cuda"; # nvidia
    home = "/var/lib/ollama"; # default

    loadModels = [
        "llama3.2:3b"
      ] ++ lib.optionals (
        config.networking.hostName == "framework-desktop" || config.networking.hostName == "nixos-server"
      ) [
        "mistral:7b"
        # "llava:34b"
        "gpt-oss:20b"
        # "gpt-oss:120b"
        # "deepseek-v3.1"
        # "codellama:70b"
        # "llama4:128x17b"
        "deepseek-r1:8b"
        "deepseek-r1:70b"
        "qwen2.5-coder:32b"
        "mistral-large:123b"
        # "deepseek-r1:670b"
        # "qwen3-coder:480b"
        "phind-codellama:34b"
        # "llama3.2-vision:90b"
      ];

    environmentVariables = {
      # OLLAMA_KEEP_ALIVE = "-1";
      # OLLAMA_MAX_LOADED_MODELS = "1";
    };
  };
}
