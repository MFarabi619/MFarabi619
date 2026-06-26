{ inputs, ... }:
{
  flake.nixOnDroidConfigurations.default = inputs.nix-on-droid.lib.nixOnDroidConfiguration {
    home-manager-path = inputs.home-manager.outPath;

    extraSpecialArgs = {
      inherit inputs;
      flake = {
        inherit inputs;
        inherit (inputs) self;
      };
    };

    pkgs = import inputs.nixpkgs {
      system = "aarch64-linux";
      overlays = [ inputs.nix-on-droid.overlays.default ];
    };

    modules = [
      (
        {
          lib,
          pkgs,
          flake,
          config,
          ...
        }:
        let
          inherit (flake) inputs;
          inherit (inputs) self;
        in
        {
          imports = [
            self.nixosModules.time
            ./terminal.nix
            ./android-integration.nix
            # ./ssh.nix
          ];

          system.stateVersion = "24.05";
          # stylix = {
          #   enable = true;
          # };

          user.shell = "${pkgs.zsh}/bin/zsh";

          nix = {
            extraOptions = ''
              trusted-users = root mfarabi
              experimental-features = nix-command flakes
            '';

            substituters = [
              "https://nix-darwin.cachix.org"
              "https://emacsng.cachix.org"
              "https://nix-on-droid.cachix.org"
            ];

            trustedPublicKeys = [
              "nix-darwin.cachix.org-1:LxMyKzQk7Uqkc1Pfq5uhm9GSn07xkERpy+7cpwc006A="
              "emacsng.cachix.org-1:i7wOr4YpdRpWWtShI8bT6V7lOTnPeI7Ho6HaZegFWMI="
              "nix-on-droid.cachix.org-1:56snoMJTXmDRC1Ei24CmKoUqvHJ9XCp+nidK7qkMQrU="
            ];
          };

          environment = {
            # Backup etc files instead of failing to activate generation if a file already exists in /etc
            etcBackupExtension = ".bak";

            packages = with pkgs; [
              man
              xz
              zip
              sudo
              gzip
              unzip
              gnupg
              bzip2
              gnused
              gnutar
              tzdata
              procps
              killall
              openssh
              gnugrep
              hostname
              diffutils
              findutils
              utillinux

              devenv
            ];
          };

          home-manager = {
            useGlobalPkgs = true;
            backupFileExtension = "hm-bak";

            extraSpecialArgs = {
              inherit inputs flake;
            };

            config = {
              stylix.overlays.enable = false;

              home = {
                username = lib.mkForce config.user.userName;
                stateVersion = "24.05";
                shell = {
                  enableShellIntegration = true;
                  enableBashIntegration = true;
                  enableZshIntegration = true;
                };

                packages = with pkgs; [
                  noto-fonts

                  tree
                  gnutls # for TLS connectivity
                  sqlite # :tools lookup & :lang org +roam

                  nil
                  cachix
                  nix-info
                  nix-inspect

                  tgpt
                  cointop # crypto price feed
                  nix-health # health check
                  cmake # vterm compilation and more
                  gnumake
                  coreutils

                  # ============== 🤪 =================
                  cowsay
                  lolcat # rainbow text output
                  figlet # fancy ascii text output
                  cmatrix
                  nyancat # rainbow flying cat
                  asciiquarium # ascii aquarium
                  hollywood

                  # termscp
                ];
              };

              imports =
                with self.homeModules;
                [
                  me
                  # home
                  fonts
                  stylix
                  manual
                  services
                  editorconfig
                ]
                ++ map (p: programs + "/${p}") [
                  "fastfetch"
                  "neovim"
                  "zsh"
                  # "emacs"

                  "bash.nix"
                  "bat.nix"
                  "btop.nix"
                  "direnv.nix"
                  "eza.nix"
                  "fd.nix"
                  "fzf.nix"
                  "gcc.nix"
                  "gh.nix"
                  "git.nix"
                  "go.nix"
                  "gpg.nix"
                  "grep.nix"
                  "home-manager.nix"
                  "jq.nix"
                  "jqp.nix"
                  "lazygit.nix"
                  "lazysql.nix"
                  "less.nix"
                  "mu.nix"
                  "nh.nix"
                  "nix-index.nix"
                  "nix-search-tv.nix"
                  "pandoc.nix"
                  "ripgrep.nix"
                  "television.nix"
                  "tex-fmt.nix"
                  "texlive.nix"
                  "tmux.nix"
                  "uv.nix"
                  "yazi.nix"
                  "zellij.nix"
                  "zoxide.nix"
                ];
            };
          };
        }
      )
    ];
  };
}
