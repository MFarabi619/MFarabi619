{
  description = "DoomBSD Installer Script Generator (FreeBSD-based OS)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default = let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
      import ./configuration.nix { inherit pkgs; lib = pkgs.lib; };

    meta = {
      homepage = "https://github.com/MFarabi619/MFarabi619/hosts/doombsd/README.org";
      description = "Generate a DoomBSD-themed install script for FreeBSD.";
      license = "GPL3.0";
      maintainers = [ "Mumtahin Farabi" ];
    };
  };
}
