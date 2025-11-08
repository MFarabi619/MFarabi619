{
  programs.texlive = {
    enable = true;
    extraPackages = tpkgs: {
      inherit (tpkgs)
        latex
        collection-basic
        collection-binextra
        collection-latexextra
        collection-formatsextra
        collection-fontsrecommended
        algorithms;
    };
  };
}
