{
  programs.aichat = {
    enable = true;
    settings = {
      model = "ollama:mistral-small3.1:latest";
      clients = [
        {
          name = "ollama";
          type = "openai-compatible";
          api_base = "http://localhost:11434/v1";
          models = [
            {
              supports_vision = true;
              name = "mistral-small3.1:latest";
              supports_function_calling = true;
            }
          ];
        }
      ];
    };
  };
}
