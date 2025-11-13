{
  pkgs,
  ...
}:

{
  languages.javascript = {
    enable = true;
    # FIXME: find out why this crashes for intel macbooks
    # bun.enable = true;
    package = pkgs.nodejs_24;
    pnpm.enable = !(pkgs.stdenv.isDarwin && pkgs.stdenv.isx86_64);
  };
}
