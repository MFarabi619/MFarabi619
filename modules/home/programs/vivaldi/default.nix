{ pkgs, ... }:
{
  programs.vivaldi = {
    enable = pkgs.stdenv.isLinux;
    nativeMessagingHosts = [ ];
  };

  home.packages =
    with pkgs;
    [
    ]
    ++ lib.optionals stdenv.isLinux [
      vivaldi-ffmpeg-codecs
    ];
}
