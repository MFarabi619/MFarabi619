{
  programs.texlive = {
    enable = true;
    extraPackages = tpkgs: {
      inherit (tpkgs) collection-fontsrecommended algorithms;
    };
  };
}
