{
  pkgs,
  config,
  ...
}:

{
  scripts = {
    hello = {
      packages = with pkgs; [chafa];
      description = "  👋 Show the Devenv logo art and a friendly greeting";
      exec = ''
        chafa --align center "${config.env.DEVENV_ROOT}/assets/devenv-symbol-dark-bg.png"
        chafa --align center "${config.env.DEVENV_ROOT}/assets/cover.png"
        echo "👋🧩"
      '';
    };
  };
}
