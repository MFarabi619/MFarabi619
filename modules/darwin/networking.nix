{
  pkgs,
  ...
}:

let
  name = if pkgs.stdenv.isx86_64 then "macos-intel" else "macos";
in
{
  networking = {
    hostName = name;
    computerName = name;
    localHostName = name;
    wakeOnLan.enable = true;
  };
}
