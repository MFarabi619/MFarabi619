{ pkgs, lib, ... }:

{
  imports = [
    ./db.nix
    ./git.nix
    ./shell.nix
    # ./ai.nix
  ];

  packages =
    with pkgs;
    [
      trunk # rust web app server
      nix-tree

      pulumi
      pulumi-esc
      pulumiPackages.pulumi-nodejs
      pulumiPackages.pulumi-command
    ]
    ++ lib.optionals (stdenv.isLinux) [
      vips
      # netscanner
    ]
    ++ lib.optionals (stdenv.isDarwin && stdenv.isAarch64) [
      cowsay
    ];
}
