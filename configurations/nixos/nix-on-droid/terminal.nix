{ pkgs, ... }:
{
  terminal = {
    colors = {
    };

    font = "${pkgs.terminus_font_ttf}/share/fonts/truetype/TerminusTTF.ttf";
  };
}
