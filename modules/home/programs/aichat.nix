{
  programs.aichat = {
    enable = true;
    settings = {
      stream = true;
      wrap = "auto";
      theme = "dark";
      wrap_code = true;
      highlight = true;
      keybindings = "vi";
      model = "ollama:gpt-oss:20b";

      clients = [
        {
          name = "ollama";
          type = "openai-compatible";
          api_base = "http://localhost:11434/v1";
          models = [
            {
              name = "phind-codellama:34b";
              supports_vision = true;
              supports_function_calling = true;
            }
            {
              name = "gpt-oss:20b";
              supports_vision = true;
              supports_function_calling = true;
            }
            {
              name = "gpt-oss:120b";
              supports_vision = true;
              supports_function_calling = true;
            }
            {
              name = "qwen2.5-coder:32b";
              supports_vision = true;
              supports_function_calling = true;
            }
            {
              name = "llava:34b";
              supports_vision = true;
              supports_function_calling = true;
            }
            {
              name = "mistral-small3.1:latest";
              supports_vision = true;
              supports_function_calling = true;
            }
          ];
        }
      ];
    };
  };
}
