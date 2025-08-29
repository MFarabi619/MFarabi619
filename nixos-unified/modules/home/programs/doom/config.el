;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; karthinks.com/software/emacs-window-management-almanac/
;; notes.justin.vc/config

;; Reconfigure packages with `after!' block wrap, otherwise Doom's defaults may override your settings. E.g.
;;   (after! PACKAGE
;;     (setq x y))
;;
;; Exceptions to this:
;;   - Setting file/directory variables (like `org-directory')
;;   - Setting variables which explicitly tell you to set them before their
;;     package is loaded (see 'C-h v VARIABLE' to look up their documentation).
;;   - Setting doom variables (which start with 'doom-' or '+').
;;
;; Additional Doom configuration functions/macros:
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!rectories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; See documentation about these functions/macros, by pressing
;; 'K' over the highlighted symbol ('C-c c k' for non-evil users).
;; open documentation for it, including demos of how they are used.
;; Alternatively, use `C-h o' to look up symbols (functions, variables, faces,
;; etc).
;;
;; See implementations with 'gd' over symbol (or 'C-c c d').

;; https://tecosaur.github.io/emacs-config

;; https://git.sr.ht/~morgansmith/sway-ts-mode
;; ;; (load! "./extra/sway-ts-mode")
;; (add-load-path "./extra")
;; (setq treesit-extra-load-path "./extra")

(display-time-mode 1)
(global-undo-tree-mode 1)
;; (keycast-tab-line-mode)
;; (+global-word-wrap-mode +1)
(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8)
(menu-bar--display-line-numbers-mode-relative)

(setq user-full-name "Mumtahin Farabi"
      user-mail-address "mfarabi619@gmail.com"
      plstore-cache-passphrase-for-symmetric-encryption t
      treemacs-git-mode 'extended
      which-key-idle-delay 0.25 ;; Make popup faster
      which-key-allow-multiple-replacements t ;; Remove 'evil-' in too many popups
      doom-modeline-hud t
      doom-modeline-time-icon t
      display-time-day-and-date t
      doom-modeline-persp-name t
      doom-modeline-major-mode-icon t
      display-line-numbers-type 'relative
      browse-url-browser-function 'browse-url-default-browser
      projectile-project-search-path '("~/workspace/" "~/Documents/")
      evil-split-window-below t
      evil-vsplit-window-right t
      ;; If you use `org' and don't want your org files in the default location below,
      ;; change `org-directory'. It must be set before org loads!
      org-directory "~/Documents/org/")

(after! treemacs
  treemacs-git-commit-diff-mode t
  treemacs-indent-guide-mode t
  treemacs-position 'left
  ;; treemacs-load-theme "doom-colors")
  ;; lsp-treemacs-theme "Eclipse"
  ;; lsp-treemacs-theme "NetBeans"
  ;; lsp-treemacs-theme "Idea"
  lsp-treemacs-symbols-position-params '((side . left) (slot . 1) (window-width . 35)))

(after! dired
  (setq dirvish-side-display-alist '((side . right) (slot . -1))
        dirvish-peek-mode t
        dirvish-side-auto-close t
        dirvish-side-follow-mode t))

(after! dirvish
  (setq!
   dirvish-default-layout '(1 0.11 0.70)
   dirvish-quick-access-entries
   `(("h" "~/"                          "Home")
     ("e" ,user-emacs-directory         "Emacs user directory")
     ("w" "~/workspace/"                "Workspace")
     ("d" "~/Downloads/"                "Downloads")
     ("p" "~/Pictures/"                 "Pictures")
     ("m" "/mnt/"                       "Mounted drives")
     ("t" "~/.local/share/Trash/files/" "Trash"))))

(use-package! gptel
  :config
  (setq gptel-default-mode #'org-mode
        gptel-model 'gpt-4o
        ;; gptel-api-key "your key"
        gptel-backend (gptel-make-gh-copilot "Copilot")
        gptel-directives '((default     . "You are a large language model living in Doom Emacs and a helpful assistant. Respond concisely. I'm using Doom Emacs with Evil Mode inside Arch Linux with Hyprland. I browse the web with Vivaldi. I also use Nix for configuration management, and write code in Rust.")
                           (programming . "You are a large language model and a careful programmer. Provide code and only code as output without any additional text, prompt or note.")
                           (writing     . "You are a large language model and a writing assistant. Respond concisely.")
                           (chat        . "You are a large language model and a conversation partner. Respond concisely.")))
  (add-hook 'gptel-post-stream-hook 'gptel-auto-scroll
            'gptel-post-response-functions 'gptel-end-of-response))

(use-package! jira
  :config
  (setq jira-base-url "https://charthouse.atlassian.net"
        jira-username "mfarabi619@gmail.com"
        ;; https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/
        jira-token ""
        jira-token-is-personal-access-token nil
        jira-api-version 3 ;; Version 2 is also allowed
        ;; https://apidocs.tempo.io/
        ;; jira-tempo-token "foobar123123")
        ))

;; (minimap-mode)

;; (add-hook 'vterm-mode-hook #'evil-normal-state)
;; (setq vterm-environment '("TERM=xterm-kitty")
;; (vterm-term-environment-variable "xterm-kitty")

(map! :n "C-l" nil :n "C-l" #'+lazygit/toggle
      :n "C-;" nil :n "C-;" #'+vterm/toggle
      :n "C-/" nil :n "C-/" #'dirvish
      :n "C-t" nil :n "C-t" (lambda () (interactive) (execute-kbd-macro (kbd "SPC o p")))
      :leader :desc "Open AI Chat buffer" "d" #'gptel)

(set-popup-rule! "*doom:vterm-popup:*"
  :height 0.5
  :width 0.5
  :slot 0
  :vslot 0
  :select t
  :quit t
  :ttl nil
  :modeline t
  :side 'right)

(set-popup-rule! "*doom:vterm-popup:lazygit*"
  :height 0.5
  :width 0.5
  :slot 0
  :vslot 0
  :select t
  :quit t
  :ttl nil
  :modeline t
  :side 'right)

(defun +lazygit/toggle ()
  "Bring up or reuse a vterm popup running lazygit."
  (interactive)
  (+vterm--configure-project-root-and-display
   nil
   (lambda ()
     (let* ((buffer-name
             (format "*doom:vterm-popup:lazygit-%s*"
                     (if (bound-and-true-p persp-mode)
                         (safe-persp-name (get-current-persp))
                       "main")))
            (buffer (or (cl-loop for buf in (doom-buffers-in-mode 'vterm-mode)
                                 if (equal (buffer-local-value '+vterm--id buf)
                                           buffer-name)
                                 return buf)
                        (get-buffer-create buffer-name)))
            (proc   (get-buffer-process buffer))
            (need-launch (not (and proc (process-live-p proc)))))
       (if-let ((win (get-buffer-window buffer-name)))
           (delete-window win)
         (with-current-buffer buffer
           (unless (eq major-mode 'vterm-mode)
             (vterm-mode))
           (setq-local +vterm--id buffer-name))
         (pop-to-buffer buffer)
         (when need-launch
           (vterm-send-string "lazygit status -sm normal; exit")
           (vterm-send-return)))
       buffer))))

(map! :leader ;; Remap switching to last buffer from 'SPC+`' to 'SPC+e'
      :desc "Switch to last buffer"
      "e" #'evil-switch-to-windows-last-buffer)
;; "e" #'my/switch-to-last-buffer-in-split)
;;
(map! :leader
      :desc "Open Dirvish Side"
      "[" #'dirvish-side)

(map! :map evil-window-map
      "SPC" #'rotate-layout
      ;; Navigation
      "<left>"     #'evil-window-left
      "<down>"     #'evil-window-down
      "<up>"       #'evil-window-up
      "<right>"    #'evil-window-right
      ;; Swapping windows
      "C-<left>"       #'+evil/window-move-left
      "C-<down>"       #'+evil/window-move-down
      "C-<up>"         #'+evil/window-move-up
      "C-<right>"      #'+evil/window-move-right)

(defun my/switch-to-last-buffer-in-split ()
  "Show last buffer on split screen."
  (interactive)
  (let ((current-buffer (current-buffer)))
    (if (one-window-p)
        (progn
          (split-window-right)
          (evil-switch-to-windows-last-buffer)
          (switch-to-buffer current-buffer)))))


(defadvice! prompt-for-buffer (&rest _)
  :after '(evil-window-split evil-window-vsplit)
  (consult-buffer))

(set-popup-rule! "*Copilot*" :size 0.5 :vslot -4 :select t :quit nil :ttl 0 :side 'left)
(set-popup-rule! "^\\*Flycheck errors\\*$" :side 'bottom :size 0.4 :select t) ;; move flycheck errors to bottom

(add-hook
 'pdf-view-mode-hook
 'pdf-view-midnight-minor-mode
 'doom-modeline-mode-hook #'nyan-mode)

(after! evil
  (setq evil-ex-substitute-global t ;; implicit /g flag on evil ex substitution
        evil-escape-key-sequence "jk")
  (add-hook 'evil-local-mode-hook 'turn-on-undo-tree-mode)
  ;; Move by visual lines instead of physical lines
  (define-key evil-normal-state-map (kbd "j") 'evil-next-visual-line)
  (define-key evil-normal-state-map (kbd "k") 'evil-previous-visual-line))

(after! org
  ;; Allow linking to non-headlines
  (setq org-link-search-must-match-exact-headline nil)
  org-todo-keywords '((sequence "TODO(t)" "INPROGRESS(i)" "BLOCKED(b)" "|" "DONE(d)" "CANCELLED(c)"))
  org-todo-keyword-faces '(("TODO" :foreground "#7c7c75" :weight normal :underline t)
                           ("INPROGRESS" :foreground "#0098dd" :weight normal :underline t)
                           ("DONE" :foreground "#50a14f" :weight normal :underline t)
                           ("CANCELLED" :foreground "#ff6480" :weight normal :underline t)
                           ("BLOCKED" :foreground "#ff9800" :weight normal :underline t))
  org-priority-faces
  '((?A :foreground "#e45649")
    (?B :foreground "#da8548")
    (?C :foreground "#0098dd"))

  (define-key org-mode-map (kbd "C-c C-r") verb-command-map)

  (setq org-modern-star ["◉" "○" "✸" "✿" "✤" "✜" "◆" "▶"]
        org-modern-table-vertical 1
        org-modern-table-horizontal 0.2
        org-modern-list '((43 . "➤")
                          (45 . "–")
                          (42 . "•"))
        ;; org-modern-todo '((sequence "TODO(t)" "INPROGRESS(i)" "BLOCKED(b)" "|" "DONE(d)" "CANCELLED(c)"))
        ;; org-modern-todo-faces '(("TODO" :foreground "#7c7c75" :weight normal :underline t)
        ;;                         ("INPROGRESS" :foreground "#0098dd" :weight normal :underline t)
        ;;                         ("DONE" :foreground "#50a14f" :weight normal :underline t)
        ;;                         ("CANCELLED" :foreground "#ff6480" :weight normal :underline t)
        ;;                         ("BLOCKED" :foreground "#ff9800" :weight normal :underline t))
        ;; org-modern-priority-faces '((?A :foreground "#e45649")
        ;;                             (?B :foreground "#da8548")
        ;;                             (?C :foreground "#0098dd"))
        ;; org-modern-priority nil
        ;; org-modern-todo nil
        ;; org-modern-footnote (cons nil (cadr org-script-display))
        ;; (custom-set-faces! '(org-modern-statistics :inherit org-checkbox-statistics-todo))

        ;; (after! spell-fu
        ;;   (cl-pushnew 'org-modern-tag (alist-get 'org-mode +spell-excluded-faces-alist)))
        ))

;; (after! magit
;;   (use-package! magit-todos
;;     :config (magit-todos-mode 1))
;;   (setq magit-diff-refine-hunk 'all
;;         magit-log-margin-show-committer-date t
;;         magit-log-arguments '("--graph" "--decorate" "--color" "--abbrev-commit" "-n256") ;; Enable commit graphs
;;         magit-status-margin '(t age magit-log-margin-width t 22)
;;         magit-log-margin-show-author t
;;         magit-section-visibility-indicator '(" " . " ")
;;         magit-format-file-function #'magit-format-file-nerd-icons
;;         magit-revision-insert-related-refs t)
;;   (add-hook 'magit-mode-hook 'hl-line-mode
;;             'magit-mode-hook 'display-line-numbers-mode)
;;   (custom-set-faces
;;    '(magit-diff-added ((t (:foreground "#00ff00" :background "#002200"))))
;;    '(magit-diff-removed ((t (:foreground "#ff0000" :background "#220000"))))
;;    '(magit-section-heading ((t (:foreground "#ffff00" :weight bold))))
;;    '(magit-diff-context ((t (:foreground "#b0b0b0"))))
;;    '(magit-diff-hunk-heading ((t (:background "#3a3f5a"))))
;;    '(magit-diff-hunk-heading-highlight ((t (:background "#51576d" :foreground "#ffffff"))))))

(after! pdf-tools
  (setq pdf-view-continuous t))

(use-package! nov-xwidget
  :demand t
  :after nov
  :config
  (define-key nov-mode-map (kbd "o") 'nov-xwidget-view)
  (add-hook 'nov-mode-hook 'nov-xwidget-inject-all-files))

(after! centaur-tabs-mode
  (setq centaur-tabs-gray-out-icons t
        centaur-tabs-show-count t
        centaur-tabs-enable-key-bindings t
        centaur-tabs-show-navigation-buttons t))

;; (after! js-mode
;;   (setq +javascript-npm-mode-hook
;;         '(doom--enable-+web-phaser-mode-in-+javascript-npm-mode-h
;;           doom--enable-+web-react-mode-in-+javascript-npm-mode-h
;;           doom--enable-+web-angularjs-mode-in-+javascript-npm-mode-h
;;           pnpm-mode
;;           +javascript-add-npm-path-h)))

(after! nyan-mode
  (setq nyan-animate-nyancat t
        nyan-wavy-trail t))

(use-package! fretboard :defer nil)
(after! fretboard
  (setq fretboard-fret-count 15)
  (add-hook 'fretboard-mode-hook #'evil-emacs-state))

(after! nerd-icons
  (setq nerd-icons-completion-mode t))

;; Add LikeC4 to LSP language configuration
(after! lsp-mode
  (setq lsp-eslint-package-manager "pnpm"
        lsp-eslint-run "onSave"
        lsp-typescript-format-enable t
        lsp-typescript-references-code-lens-enabled t
        lsp-typescript-suggest-complete-function-calls t)

  (add-to-list 'lsp-language-id-configuration '(".*\\.c4" . "likec4"))

  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection '("likec4-language-server" "--stdio"))
    :activation-fn (lsp-activate-on "likec4")
    :server-id 'likec4-ls)))

  ;; (gfm-mode-hook 'gfm-view-mode)

;; (define-derived-mode sway-mode rust-ts-mode "sway")
;; (add-to-list 'auto-mode-alist '("\\.sw\\'" . sway-mode))
;; (add-to-list
;;  'eglot-server-programs
;;  '((sway-mode) .
;;    ("nix" "shell" "github:fuellabs/fuel.nix#fuel" "--command" "forc-lsp")))

(after! which-key
  (pushnew!
   which-key-replacement-alist
   '(("" . "\\`+?evil[-:]?\\(?:a-\\)?\\(.*\\)") . (nil . "◂\\1"))
   '(("\\`g s" . "\\`evilem--?motion-\\(.*\\)") . (nil . "◃\\1"))))

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!

(defun my-custom-dashboard-text ()
  "Insert custom text into the Doom dashboard."
  (insert "\"Do not proceed with a mess; messes just grow with time.\" ― Bjarne Stroustrup\n\n"))

;; (setq fancy-splash-image "~/dotfiles/.config/doom/doom-emacs-color2.svg")
(setq fancy-splash-image "~/MFarabi619/nixos-unified/modules/home/programs/doom/apollyon-emacs.png")

;; Find `doom-dashboard-widget-banner` in the list and insert after it
(let ((pos (cl-position #'doom-dashboard-widget-banner +doom-dashboard-functions)))
  (when pos
    (setq +doom-dashboard-functions
          (append (cl-subseq +doom-dashboard-functions 0 (1+ pos))
                  (list #'my-custom-dashboard-text)
                  (cl-subseq +doom-dashboard-functions (1+ pos))))))

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;;
;; - `doom-font' -- the primary font to use
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
;; - `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;; - `doom-symbol-font' -- for symbols
;; - `doom-serif-font' -- for the `fixed-pitch-serif' face
;;
;; See 'C-h v doom-font' for documentation and more examples of what they
;; accept. For example:
;;
;; (setq doom-font (font-spec :family "Fira Code" :size 12 :weight 'semi-light))
;; doom-variable-pitch-font (font-spec :family "Fira Sans" :size 13))
;;
;; If you or Emacs can't find your font, use 'M-x describe-font' to look them
;; up, `M-x eval-region' to execute elisp code, and 'M-x doom/reload-font' to
;; refresh your font settings. If Emacs still can't find your font, it likely
;; wasn't installed correctly. Font issues are rarely Doom issues!

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
;; (setq doom-theme 'doom-gruvbox)

(setq doom-theme
      ;; 'doom-lantern
      'doom-gruvbox
      ;; 'doom-gruvbox-light
      ;; 'doom-solarized-light
      ;; doom-lantern-brighter-modeline t
      ;; doom-lantern-brighter-comments t
      doom-lantern-padded-modeline t
      doom-font (font-spec :family "JetBrainsMono Nerd Font" :size 20)
      doom-variable-pitch-font (font-spec :family "JetBrainsMono Nerd Font" :size 20)
      doom-big-font (font-spec :family "JetBrainsMono Nerd Font" :size 40))

;; https://www.ovistoica.com/blog/2024-7-05-modern-emacs-typescript-web-tsx-config
