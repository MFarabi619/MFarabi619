;; This "home-environment" file can be passed to 'guix home reconfigure'
;; to reproduce the content of your profile.  This is "symbolic": it only
;; specifies package names.  To reproduce the exact same profile, you also
;; need to capture the channels being used, as returned by "guix describe".
;; See the "Replicating Guix" section in the manual.

(use-modules (gnu home)
             (gnu packages)
             (gnu services)
             (gnu packages fonts)
             (guix gexp)
             (gnu packages shells)
             (gnu home services)
             (gnu home services shells))

(home-environment
  ;; Packages show up in Home profile, under ~/.guix-home/profile.
  (packages
   (specifications->packages
    (list
     "neovim"
     "git"
     "btop"
     "fd"
     "fzf"
     "ripgrep"
     "direnv"
     "tree-sitter"
     "eza"
     "bat"
     "fastfetch"
     "tree"
     "cmatrix"
     "figlet"
     "cowsay"
     "lolcat"
     "nyancat"

     "emacs-nyan-mode"
     "emacs-evil"
     "emacs-evil-collection"
     "emacs-evil-smartparens"
     "emacs-evil-multiedit"
     "emacs-evil-surround"
     "emacs-evil-quickscope"
     "emacs-evil-traces"
     "emacs-evil-org"
     "emacs-evil-markdown"
     "emacs-evil-goggles"
     "emacs-evil-leader"
     "emacs-evil-args"
     "emacs-evil-commentary"
     "emacs-evil-lion"
     "emacs-fd"
     "emacs-ripgrep"
     "emacs-xterm-color"
     "emacs-centaur-tabs"
     "emacs-doom-themes"
     "emacs-doom-modeline"
     "emacs-dirvish"
     "emacs-pdf-tools"
     "emacs-nerd-icons"
     "emacs-all-the-icons"
     "emacs-all-the-icons-dired"
     "emacs-which-key"
     "emacs-which-key-posframe"
     "emacs-scad-mode"
     "emacs-eshell-syntax-highlighting"
     "emacs-eshell-git-prompt"
     "poppler"
     "ffmpegthumbnailer"
     "mediainfo"
     "imagemagick"

     "emacs-fd"
     "emacs-ripgrep"
     "emacs-xterm-color"
     "emacs-centaur-tabs"
     "emacs-doom-themes"
     "emacs-doom-modeline"
     "emacs-dirvish"
     "emacs-pdf-tools"
     "emacs-nerd-icons"
     "emacs-all-the-icons"
     "emacs-all-the-icons-dired"
     "emacs-which-key"
     "emacs-which-key-posframe"
     "emacs-scad-mode"
     "emacs-eshell-syntax-highlighting"
     "emacs-eshell-git-prompt"
     "poppler"
     "ffmpegthumbnailer"
     "mediainfo"
     "imagemagick"

     "glibc-locales"
     "zsh"
     "network-manager"
     "vips"
     )))

  ;; Home services
  ;; Search services with 'guix home search KEYWORD'
  (services
   (append (list (service home-bash-service-type
                          (home-bash-configuration
                           (aliases '(("grep" . "grep --color=auto")
                                      ("ll" . "ls -l")
                                      ("ls" . "ls -p --color=auto")))
                           (bashrc (list (local-file
                                          "/home/mfarabi/MFarabi619/hosts/guix/.bashrc"
                                          "bashrc")))
                           (bash-profile (list (local-file
                                                "/home/mfarabi/MFarabi619/hosts/guix/.bash_profile"
                                                "bash_profile"))))))
           %base-home-services)))
