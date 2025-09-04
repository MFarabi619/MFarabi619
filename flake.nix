{
  description = "Kubernetes + Argo CD";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nixidy = {
      url = "github:arnarg/nixidy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nixidy,
    }:
    (flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
      in
      {
        # This declares the available nixidy envs.
        nixidyEnvs = nixidy.lib.mkEnvs {
          inherit pkgs;

          envs = {
            # Currently we only have the one dev env.
            dev.modules = [ ./env/dev.nix ];
          };
        };

        # Handy to have nixidy cli available in the local
        # flake too.
        packages.nixidy = nixidy.packages.${system}.default;

        # Useful development shell with nixidy in path.
        # Run `nix develop` to enter.
        devShells.default = pkgs.mkShell {
          buildInputs = [ nixidy.packages.${system}.default ];
        };
      }
    ));
}
