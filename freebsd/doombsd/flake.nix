{
  description = "DoomBSD Installer Script Generator (FreeBSD-based OS)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default = let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
      import ./configuration.nix {
        inherit pkgs;
        lib = pkgs.lib;
      };

    meta = {
      license = "GPL3.0";
      maintainers = [ "Mumtahin Farabi" ];
      description = "Generate a DoomBSD-themed install script for FreeBSD.";
      homepage = "https://github.com/MFarabi619/MFarabi619/freebsd/doombsd/README.org";
    };
  };
}
