{
  pkgs,
  ...
}:
{
    languages.c = {
      enable = true;
      debugger = pkgs.gdb;
    };
}
