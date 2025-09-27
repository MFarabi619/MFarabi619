{
  programs.aichat = {
    enable = true;
    settings ={
      stream = true;
      wrap = "auto";
      theme = "dark";
      wrap_code = true;
      highlight = true;
      keybindings = "vi";
      model = "ollama:mistral-small3.1:latest"; # ollama pull mistral-small3.1:latest
      clients = [
        {
          name = "ollama";
          type = "openai-compatible";
          api_base = "http://localhost:11434/v1";
          models = [
            {
              name = "mistral-small3.1:latest";
              supports_vision = true;
              supports_function_calling = true;
            }
            {
              name = "phind-codellama:latest";
              supports_vision = true;
              supports_function_calling = true;
            }
            {
              name = "phi:latest";
              supports_vision = true;
              supports_function_calling = true;
            }
          ];
        }
      ];
    };
  };
}
