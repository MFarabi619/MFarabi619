{ pkgs, ... }:

{
  languages.javascript = {
    enable = true;
    pnpm.enable = true;
    # bun.enable = true;
    package = pkgs.nodejs_24;
  };
}
