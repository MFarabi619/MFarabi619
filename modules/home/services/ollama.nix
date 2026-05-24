{
  pkgs,
  ...
}:
{
  services.ollama = {
    enable = false;
    # acceleration = "rocm";
    # acceleration = "cuda"; # nvidia
    # environmentVariables = { };
  };
}
