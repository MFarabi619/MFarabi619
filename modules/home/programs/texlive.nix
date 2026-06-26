{
  programs.texlive = {
    enable = true;
    extraPackages = tpkgs: {
      inherit (tpkgs)
        lato
        latex
        dvipng
        latexmk
        fontspec
        algorithms
        latex-fonts
        dvipsconfig
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
        collection-fontsrecommended
        ;
    };
  };
}
