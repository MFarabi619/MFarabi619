{
  services.ollama = {
    enable = true;
    port = 11434; # default
    host = "0.0.0.0"; # default
    # acceleration = "rocm";
    # acceleration = "cuda"; # nvidia
    # environmentVariables = { };
  };
}
