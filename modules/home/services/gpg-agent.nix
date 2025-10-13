{
  pkgs,
  ...
}:
{
  services.gpg-agent = {
    enable = true;
    verbose = true;
    enableScDaemon = true;
    enableSshSupport = true;
    enableExtraSocket = true;
    grabKeyboardAndMouse = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    pinentry = {
      program = "pinentry-tty";
      package = pkgs.pinentry-tty;
    };
    # extraConfig = ''
    # '';
  };
}
