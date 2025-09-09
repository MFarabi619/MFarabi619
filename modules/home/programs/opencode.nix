{
  programs.opencode = {
    enable = true;
    settings = {
      theme = "gruvbox";
      autoshare = false;
      autoupdate = false;
      permission = {
        edit = "ask";
        bash = "ask";
      };
      # mcp = {
      #   my-local-mcp-server = {
      #     enabled = true;
      #     type = "local";
      #     command = [
      #       "bun"
      #       "x"
      #       "my-mcp-command"
      #     ];
      #     environment = {
      #       MY_ENV_VAR = "my_env_var_value";
      #     };
      #   };
      # };
      # provider = {
      #   npm = "@ai-sdk/openai-compatible";
      #   name = "Ollama (local)";
      #   "options" = {
      #     "baseURL" = "http://localhost:11434/v1";
      #   };
      #   models = {
      #     llama2 = {
      #       name = "Llama 2";
      #     };
      #   };
      # };

      # disabled_providers= ["openai" "gemini"];
      # instructions = ["CONTRIBUTING.md" "docs/guidelines.md" ".cursor/rules/*.md"];
      #   model = "anthropic/claude-sonnet-4-20250514";
      #   model= "{env:OPENCODE_MODEL}";
      # };
      #     rules = ''
      #       # TypeScript Project Rules

      #       ## External File Loading

      #       CRITICAL: When you encounter a file reference (e.g., @rules/general.md), use your Read tool to load it on a need-to-know basis. They're relevant to the SPECIFIC task at hand.

      #       Instructions:

      #       - Do NOT preemptively load all references - use lazy loading based on actual need
      #       - When loaded, treat content as mandatory instructions that override defaults
      #       - Follow references recursively when needed

      #       ## Development Guidelines

      #       For TypeScript code style and best practices: @docs/typescript-guidelines.md
      #       For React component architecture and hooks patterns: @docs/react-patterns.md
      #       For REST API design and error handling: @docs/api-standards.md
      #       For testing strategies and coverage requirements: @test/testing-guidelines.md

      #       ## General Guidelines

      #       Read the following file immediately as it's relevant to all workflows: @rules/general-guidelines.md.
      # '';
    };
  };
}
