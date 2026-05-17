{
  pkgs,
  flake,
  ...
}:
{
  services.cgit."cgit" = {
    enable = true;
    scanPath = "/srv/git";
    gitHttpBackend.enable = true;
    gitHttpBackend.checkExportOkFiles = false;
    nginx.virtualHost = "cgit.mfarabi.sh";

    settings = {
      root-title = "Mumtahin Farabi";
      root-desc = "A society grows great when the old plant trees in whose shade they know they shall never sit. 🌴";
      root-readme = builtins.toFile "cgit-root-readme.txt" ''
        Public Git mirror for Mumtahin Farabi's monorepo.

        Clone:    git clone https://cgit.mfarabi.sh/MFarabi619
        Browse:   click a repository name above.

        Theme:    gruvbox-cgit by imn1
                  https://gitlab.com/imn1/gruvbox-cgit
      '';

      remove-suffix = "1";
      section-from-path = "1";

      enable-git-config = "1";
      enable-http-clone = "1";
      enable-html-serving = "1";
      enable-index-links = "1";
      enable-index-owner = "0";

      enable-log-filecount = "1";
      enable-log-linecount = "1";
      enable-remote-branches = "1";
      enable-subject-links = "1";
      enable-tree-linenumbers = "1";

      enable-blame = "1";
      enable-commit-graph = "1";
      enable-filter-overrides = "1";

      branch-sort = "age";

      favicon = "/favicon.svg";
      logo = "/favicon.svg";
      logo-link = "https://mfarabi.sh";

      section-sort = "0";

      snapshots = "tar.gz";

      readme = [
        ":readme.md"
        ":readme"
        ":README.md"
        ":README"
      ];

      cache-size = "1000";
      cache-root = "/var/cache/cgit";
      cache-root-ttl = "60";
      cache-repo-ttl = "15";

      about-filter = "${pkgs.cgit}/lib/cgit/filters/about-formatting.sh";

      css = [
        "/cgit.css"
        "/gruvbox.cgit.css"
      ];
    };
  };
}
