{
  pkgs,
  ...
}:
{
  services.ollama = {
    enable = !pkgs.stdenv.isDarwin;
    # acceleration = "rocm";
    # acceleration = "cuda"; # nvidia
    # environmentVariables = { };
  };
}
