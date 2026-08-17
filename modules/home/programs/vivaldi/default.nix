{
  pkgs,
  ...
}:
{
  programs.vivaldi = {
    enable = pkgs.stdenv.hostPlatform.isLinux;
    nativeMessagingHosts = [ ];
  };

  home.packages =
    with pkgs;
    lib.optionals stdenv.hostPlatform.isLinux [
      vivaldi-ffmpeg-codecs
    ];
}
