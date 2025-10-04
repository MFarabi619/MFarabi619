{
  services.ollama = {
    enable = true;
    port = 11434; # default
    openFirewall = false;
    home = "/var/lib/ollama"; # default
    loadModels = [
      "mistral"
    ];
    # environmentVariables = {
    #
    # };
  };
}
