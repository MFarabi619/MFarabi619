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
    pinentry.program = "pinentry-tty";
    pinentry.package = pkgs.pinentry-tty;

    maxCacheTtl = 86400; # 24 hours
    maxCacheTtlSsh = 86400; # 24 hours
    defaultCacheTtl = 86400; # 24 hours
    defaultCacheTtlSsh = 86400; # 24 hours
  };
}
