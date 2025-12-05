{
  programs.texlive = {
    enable = true;
    extraPackages = tpkgs: {
      inherit (tpkgs)
        latex
        fontspec
        algorithms
        latex-fonts
        fontawesome6
        collection-basic
        collection-latex
        collection-xetex
        jetbrainsmono-otf
        collection-luatex
        collection-binextra
        collection-latexextra
        collection-fontsextra
        collection-formatsextra
        collection-fontsrecommended;
    };
  };
}
