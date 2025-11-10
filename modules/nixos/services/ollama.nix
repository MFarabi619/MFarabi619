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
      # "mistral"
      # "mistral-large"
      "llama3.2:3b"
      # "llama4:128x17b"
      # "llama3.2-vision:90b"
      "gpt-oss:20b"
      # "gpt-oss:120b"
      # "codellama:70b"
      # "deepseek-r1:8b"
      # "deepseek-v3.1"
      # "phind-codellama:34b"
      # "deepseek-r1:70b"
      # "deepseek-r1:670b"
      "qwen2.5-coder:32b"
      # "qwen3-coder:480b"
      # "llava:34b"
    ];
    # environmentVariables = { };
  };
}
