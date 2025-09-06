{
  programs.aichat = {
    enable = true;
    settings ={
      model = "ollama:mistral-small3.1:latest";
      clients = [
        {
          type = "openai-compatible";
          name = "ollama";
          api_base = "http://localhost:11434/v1";
          models = [
            {
              name = "mistral-small3.1:latest";
              supports_function_calling = true;
              supports_vision = true;
            }
          ];
        }
      ];
    };
  };
}
