{ pkgs, ... }:
{
  terminal = {
    font = "${pkgs.terminus_font_ttf}/share/fonts/truetype/TerminusTTF.ttf";

    colors = {
      foreground = "#FFFFFF";
      background = "#0A0101";

      cursor = "#B41211";

      color0 = "#522929"; # black
      color8 = "#8F5757";
      color1 = "#FFCCCC"; # red
      color9 = "#F0ABAA";
      color2 = "#FFCCCC"; # green
      color10 = "#F0AAAA";
      color3 = "#FFCCCD"; # yellow
      color11 = "#F0AAAB";
      color4 = "#E69A9A"; # blue
      color12 = "#E69A9A";
      color5 = "#E69A9A"; # magenta
      color13 = "#E69A9A";
      color6 = "#E69A9B"; # cyan
      color14 = "#E69A9B";
      color7 = "#FFCCCC"; # white
      color15 = "#F0ABAA";
    };
  };
}
