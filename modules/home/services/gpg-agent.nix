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
    pinentry.package =
      if pkgs.stdenv.isDarwin then pkgs.pinentry_mac else pkgs.pinentry-tty;

    maxCacheTtl = 86400; # 24 hours
    maxCacheTtlSsh = 86400; # 24 hours
    defaultCacheTtl = 86400; # 24 hours
    defaultCacheTtlSsh = 86400; # 24 hours
  };
}
