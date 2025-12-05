{
  pkgs,
  ...
}:

{
  languages.javascript = {
    enable = true;
    bun.enable = true;
    package = pkgs.nodejs_24;
    # FIXME: find out why this crashes for intel macbooks
    # pnpm.enable = !(pkgs.stdenv.isDarwin && pkgs.stdenv.isx86_64);
  };
}
