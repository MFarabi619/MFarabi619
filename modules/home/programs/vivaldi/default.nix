{ pkgs, ... }:
{
  programs.vivaldi = {
    enable = pkgs.stdenv.isLinux;
    nativeMessagingHosts = [];
  };
  home.packages = with pkgs; [
   vivaldi-ffmpeg-codecs
  ];
}
