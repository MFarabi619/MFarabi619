{
  services.ollama = {
    enable = true;
    port = 11434; # default
    host = "127.0.0.1"; # default
    # acceleration = "rocm";
    # acceleration = "cuda"; # nvidia
    # environmentVariables = { };
  };
}
