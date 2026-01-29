{
  description = "Hello on FreeBSD";

  outputs = { self, nixpkgs }:
    let
      # nix eval --impure --expr builtins.currentSystem
      system = "x86_64-freebsd";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.${system}.default =
        pkgs.writeShellScriptBin "hello" ''
          echo "hello"
        '';
    };
}
