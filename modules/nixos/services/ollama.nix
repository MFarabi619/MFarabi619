{
  services.ollama = {
    enable = true;
    port = 11434; # default
    openFirewall = true;
    host = "0.0.0.0";
    # acceleration = "rocm"; # amd
    # acceleration = "cuda"; # nvidia
    home = "/var/lib/ollama"; # default
    loadModels = [
      "mistral"
      "llama3.2"
      # "gpt-oss:120b"
      "codellama:70b"
      # "mistral-large"
      # "deepseek-v3.1"
      # "llama4:128x17b"
      "phind-codellama"
      # "deepseek-r1:70b"
      # "deepseek-r1:670b"
      # "qwen3-coder:480b"
      # "llama3.2-vision:90b"
    ];
    # environmentVariables = { };
  };
}
