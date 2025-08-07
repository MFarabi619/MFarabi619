{ pkgs, ... }:
{
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-u16n.psf.gz";

    # Make colored console output more readable
    # for example, `ip addr`s (blues are too dark by default)
    # Tango theme: https://yayachiken.net/en/posts/tango-colors-in-terminal/
    colors = [
      "000000"
      "CC0000"
      "4E9A06"
      "C4A000"
      "3465A4"
      "75507B"
      "06989A"
      "D3D7CF"
      "555753"
      "EF2929"
      "8AE234"
      "FCE94F"
      "739FCF"
      "AD7FA8"
      "34E2E2"
      "EEEEEC"
    ];
  };
}
