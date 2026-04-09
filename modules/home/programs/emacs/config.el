;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

(nyan-mode 1)
(parrot-mode -1)
(display-time-mode 1)
(line-number-mode -1)
(kitty-graphics-mode 1)
(window-divider-mode -1)
(global-undo-tree-mode 1)
;; (keycast-tab-line-mode)
(dape-breakpoint-global-mode 1)
(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8)
(set-frame-parameter nil 'undecorated t)
(add-to-list 'default-frame-alist '(undecorated . t))

(setopt doom-theme 'doom-gruvbox
        ;; doom-theme 'catppuccin
        fancy-splash-image "~/MFarabi619/assets/apollyon-emacs.png"

        column-number-mode nil
        size-indication-mode nil
        doom-modeline-percent-position nil

        doom-modeline-hud t
        doom-modeline-time-icon t
        doom-modeline-battery nil
        doom-modeline-persp-name t
        doom-modeline-major-mode-icon t
        ;; doom-lantern-padded-modeline t

        display-time-day-and-date t
        display-line-numbers-type 'relative

        doom-font                (font-spec :family "JetBrainsMono Nerd Font" :size 14)
        doom-big-font            (font-spec :family "JetBrainsMono Nerd Font" :size 32)
        doom-variable-pitch-font (font-spec :family "JetBrainsMono Nerd Font" :size 14)
        doom-symbol-font doom-font

        evil-escape-key-sequence "jk"
        which-key-allow-multiple-replacements t ;; Remove 'evil-' in too many popups

        which-key-idle-delay 0.25

        org-latex-compiler "lualatex"
        plantuml-default-exec-mode "executable"

        org-directory "~/Documents/org/"
        user-full-name "Mumtahin Farabi"
        user-mail-address "mfarabi619@gmail.com"
        ;; plstore-cache-passphrase-for-symmetric-encryption t

        compilation-scroll-output t
        find-file-visit-truename nil
        browse-url-browser-function 'browse-url-default-browser
        projectile-project-search-path '("~/workspace/" "~/Documents/")

        lsp-postgres-server-path "postgrestools"

        gdb-debuginfod-enable-setting t
        gud-gdb-command-name "arm-none-eabi-gdb -i=mi")

(load!        "./dashboard.el")
;; (add-load-path! "pio-mode")
;; (use-package! pio-mode)
(use-package! org-anki)
(use-package! kbd-mode)
;; (use-package! gptel-integrations)
(use-package! exercism              :if (not (eq system-type 'berkeley-unix))) ;; FIXME: fails on FreeBSD
(use-package! magit-todos           :after magit         :config (magit-todos-mode 1))
(use-package! consult-compile-multi :after compile-multi :config (consult-compile-multi-mode 1))
(use-package! fretboard                                  :config (setopt fretboard-fret-count 15) (add-hook 'fretboard-mode-hook #'evil-emacs-state))
(use-package! nov-xwidget           :after nov           :config (add-hook! 'nov-mode-hook #'nov-xwidget-inject-all-files) (define-key nov-mode-map (kbd "o") #'nov-xwidget-view))
(use-package! fancy-compilation     :after compile       :config (setopt fancy-compilation-term "xterm-256color" fancy-compilation-quiet-prelude t fancy-compilation-quiet-prolog t fancy-compilation-override-colors nil) (fancy-compilation-mode 1))
(use-package! ob-duckdb             :after org           :config (setopt org-babel-duckdb-max-rows 200 org-babel-duckdb-show-progress t org-babel-duckdb-queue-display 'auto org-babel-duckdb-queue-position 'side org-babel-duckdb-progress-display 'popup org-babel-duckdb-output-buffer "*DuckDB Results*"))

(after!       direnv        (direnv-mode -1))
(after!       nerd-icons    (nerd-icons-completion-mode 1))
(after!       pdf-tools     (setopt pdf-view-continuous t))
(after!       evil          (setopt evil-ex-substitute-global t))
(after!       magit-delta   (setopt magit-delta-hide-plus-minus-markers t))
(after!       nyan-mode     (setopt nyan-animate-nyancat t nyan-wavy-trail t))
(after!       files         (add-to-list 'safe-local-variable-directories "~/MFarabi619/"))
(after!       dap-gdb       (setopt dap-gdb-debug-program '("arm-none-eabi-gdb" "-i" "dap")))
(after!       treesit       (setopt treesit-font-lock-level 4 treesit-auto-install-grammar 'always))
(after!       projectile    (add-hook! 'projectile-after-switch-project-hook #'my/warm-project-vterm))
(after!       tramp         (setopt tramp-verbose 1           tramp-default-method "sshx" tramp-connection-timeout 10))
(after!       osm           (setopt osm-copyright t           osm-home (list 45.38730243858645 -75.69539479599302 15)))
(after!       sql           (setopt sql-database "microvisor" sql-server "127.0.0.1" sql-port 5432 sql-user "mfarabi" sql-password ""))
(after!       verb-mode     (setopt verb-auto-show-headers-buffer t verb-auto-kill-response-buffers t verb-json-use-mode #'json-ts-mode))
(after!       which-key     (pushnew! which-key-replacement-alist '(("" . "\\`+?evil[-:]?\\(?:a-\\)?\\(.*\\)") . (nil . "◂\\1")) '(("\\`g s" . "\\`evilem--?motion-\\(.*\\)") . (nil . "◃\\1"))))
(after!       parrot-mode   (setopt parrot-animate-parrot t parrot-num-rotations 1000 parrot-animation-frame-interval 0.045 parrot-spaces-before 1 parrot-spaces-after 1) (parrot-type "confused"))
(after!       dirvish       (setopt dirvish-peek-mode t dirvish-side-auto-close t dirvish-side-follow-mode t dired-listing-switches "-alhX" dirvish-side-display-alist '((side . right) (slot . -1))))
(after!       lsp           (setopt lsp-enable-folding t lsp-eldoc-render-all t lsp-before-save-edits t lsp-inlay-hint-enable t lsp-completion-enable t lsp-auto-execute-action t lsp-describe-thing-at-point t))
(after!       lsp-clangd    (setopt lsp-clients-clangd-args '("-j=3" "--clang-tidy" "--background-index" "--header-insertion=never" "--completion-style=detailed" "--header-insertion-decorators=0")) (set-lsp-priority! 'clangd 2) )
(after!       vertico       (vertico-multiform-mode 1) (add-to-list 'vertico-multiform-commands '(compile-multi buffer (vertico-buffer-display-action . ((display-buffer-reuse-window display-buffer-in-side-window) (side . right) (window-width . 0.20) (window-parameters . ((no-delete-other-windows . t) (mode-line-format . none))))))))
(after!       treemacs      (setopt treemacs-width 40 treemacs-peek-mode t treemacs-follow-mode t treemacs-git-mode 'extended treemacs-position 'right lsp-treemacs-theme "Default" treemacs-git-commit-diff-mode t treemacs-nerd-icons-icon-size 2.0 treemacs-display-in-side-window t lsp-treemacs-symbols-position-params '((side . right) (slot . 2) (window-width . 100))))
(after!       compile-multi (setopt compile-multi-default-directory (lambda () (ignore-errors (projectile-project-root)))) (advice-add 'compile-multi :around (lambda (fn &rest args) (if (bound-and-true-p vertico-posframe-mode) (unwind-protect (progn (vertico-posframe-mode -1) (apply fn args)) (vertico-posframe-mode 1)) (apply fn args)))))
(after!       gnus          (setopt sendmail-program "msmtp" message-sendmail-f-is-evil t gnus-secondary-select-methods nil mm-text-html-renderer 'shr mm-inline-large-images t mm-discouraged-alternatives '("text/plain" "text/richtext") shr-use-colors nil shr-max-width 100 shr-max-image-proportion 0.6 shr-use-fonts nil message-sendmail-envelope-from 'header message-send-mail-function 'message-send-mail-with-sendmail message-sendmail-extra-arguments '("--read-envelope-from") gnus-select-method '(nnmaildir "local" (directory "~/Maildir/Gmail"))))
(after!       rustic-mode   (setopt lsp-rust-features "all" lsp-rust-unstable-features t lsp-rust-analyzer-implicit-drops t lsp-rust-analyzer-lens-references-adt-enable t lsp-rust-analyzer-lens-references-trait-enable t lsp-rust-analyzer-lens-references-method-enable t lsp-rust-analyzer-lens-references-enum-variant-enable t lsp-rust-analyzer-display-lifetime-elision-hints-enable t lsp-rust-analyzer-display-lifetime-elision-hints-use-parameter-names t))
(after!       proced        (setopt proced-auto-update-interval 1 proced-goal-attribute nil proced-enable-color-flag t proced-format 'medium) (setq-default proced-auto-update-flag t)

  (add-hook! 'proced-mode-hook
    (lambda () (setq-local      mode-line-format nil line-spacing 0.10)
      (face-remap-add-relative 'font-lock-keyword-face                     :foreground "#fb4934")
      (face-remap-add-relative 'font-lock-function-name-face               :foreground "#b8bb26")
      (face-remap-add-relative 'font-lock-variable-name-face               :foreground "#83a598")
      (face-remap-add-relative 'font-lock-type-face                        :foreground "#d3869b")
      (face-remap-add-relative 'default                                    :foreground "#ebdbb2" :background "#1d2021")
      (face-remap-add-relative 'error                        :weight 'bold :foreground "#fb4934"                      )
      (face-remap-add-relative 'success                      :weight 'bold :foreground "#b8bb26"                      )
      (face-remap-add-relative 'warning                      :weight 'bold :foreground "#fabd2f"                      ))))

(after! prodigy
  (require 'seq)

  (setopt prodigy-kill-process-buffer-on-stop t)

  (custom-set-faces! '(prodigy-red-face    :foreground "#fb4934" :weight bold) '(prodigy-green-face  :foreground "#b8bb26" :weight bold) '(prodigy-yellow-face :foreground "#fabd2f" :weight bold))

  (defun my/prodigy-group-row-p (&optional pos) (let ((id (tabulated-list-get-id pos))) (and (consp id) (eq (car id) :group))))
  (defun my/prodigy-next-service (&optional n) (interactive "p") (let ((n (or n 1))) (dotimes (_ n) (forward-line 1) (while (and (not (eobp)) (or (my/prodigy-group-row-p) (null (tabulated-list-get-id)))) (forward-line 1)))
                                                                      (when (eobp) (forward-line -1) (while (and (not (bobp)) (or (my/prodigy-group-row-p) (null (tabulated-list-get-id)))) (forward-line -1)))))
  (defun my/prodigy-previous-service (&optional n) (interactive "p") (let ((n (or n 1))) (dotimes (_ n) (forward-line -1) (while (and (not (bobp)) (or (my/prodigy-group-row-p) (null (tabulated-list-get-id)))) (forward-line -1)))
                                                                          (when (my/prodigy-group-row-p) (forward-line 1) (while (and (not (eobp)) (or (my/prodigy-group-row-p) (null (tabulated-list-get-id)))) (forward-line 1)))))
  (defun my/prodigy-display-name (service) (or (plist-get service :display-name) (plist-get service :name) ""))
  (defun my/prodigy-group-label (service) (or (plist-get service :group-label) "other"))

  (defun my/prodigy-service-entry (service) (list (prodigy-service-id service) (vector (prodigy-marked-col service) (propertize (my/prodigy-display-name service) 'face (or (prodigy-status-face service) 'default)) (if-let ((port (plist-get service :port))) (number-to-string port) ""))))

  (defun my/prodigy-group-entry (label) (let* ((width 35)
                                               (text  (format "  %s  " label))
                                               (text-width (string-width text))
                                               (left-width  (max 0 (/ (- width text-width) 2)))
                                               (right-width (max 0 (- width text-width left-width)))
                                               (left  (propertize (make-string left-width ?─) 'face 'shadow))
                                               (right (propertize (make-string right-width ?─) 'face 'shadow))
                                               (mid   (propertize text 'face 'shadow)))
                                          (list `(:group ,label) (vector "" (concat left mid right) ""))))

  (defun my/prodigy-list-entries () (apply #'append (mapcar (lambda (group) (let ((label (car group)) (services (sort (copy-sequence (cdr group)) (lambda (a b) (string-lessp (my/prodigy-display-name a) (my/prodigy-display-name b))))))
                                                                              (cons (my/prodigy-group-entry label) (mapcar #'my/prodigy-service-entry services))))
                                                            (seq-group-by #'my/prodigy-group-label (prodigy-services)))))

  (add-hook! 'prodigy-mode-hook (setq-local mode-line-format nil
                                            header-line-format nil
                                            tabulated-list-padding 0
                                            tabulated-list-groups nil
                                            tabulated-list-sort-key nil
                                            tabulated-list-entries #'my/prodigy-list-entries
                                            tabulated-list-format [(" " 1 nil) ("Service" 35 t) ("Port" 1 t)])
    (tabulated-list-print t))) ;; end prodigy

(with-eval-after-load 'mu4e
  (setopt
   mu4e-index-cleanup nil
   mu4e-index-lazy-check t
   message-sendmail-f-is-evil t
   mu4e-context-policy 'ask-if-none
   send-mail-function #'smtpmail-send-it
   mu4e-compose-context-policy 'always-ask
   sendmail-program (executable-find "msmtp")
   message-sendmail-extra-arguments '("--read-envelope-from")
   message-send-mail-function #'message-send-mail-with-sendmail)
  (use-package! mu4e-column-faces :config (mu4e-column-faces-mode 1))
  (use-package! mu4e-marker-icons :config (mu4e-marker-icons-mode 1))
  ;; (use-package! mu4e-views        :config (setopt mu4e-views-completion-method 'default mu4e-views-default-view-method "html" mu4e-views-auto-view-selected-message t mu4e-views-next-previous-message-behaviour 'stick-to-current-window) (mu4e-views-mu4e-use-view-msg-method "html"))
  )

(add-hook! 'sql-mode-hook #'lsp!)
(add-hook! 'conf-toml-mode-hook #'lsp!)
(add-hook! 'gfm-mode-hook #'markdown-view-mode)
;; (add-hook! 'sql-mode-hook #'sqlup-mode!)
;; (add-hook! 'lsp-mode-hook #'lsp-inlay-hints-mode)
(add-hook! 'prodigy-view-mode-hook (text-scale-set -2))
;; (add-hook! 'sql-interactive-mode-hook #'sqlup-mode!)
(add-hook! 'doom-first-buffer-hook #'my/warm-project-vterm)
(add-hook! 'pdf-view-mode-hook 'pdf-view-midnight-minor-mode 'doom-modeline-mode-hook #'nyan-mode)
(add-hook! '(sql-mode-hook sql-interactive-mode-hook) (setq-local sql-default-directory (projectile-project-root)) (sql-highlight-postgres-keywords))

(set-popup-rule! "^\\*Flycheck errors\\*$" :side 'bottom                                    :height 0.40 :width 0.40 :select t   :modeline nil)
(set-popup-rule! "*doom:vterm-popup:*"     :side 'right  :quit t :slot  0 :ttl nil :vslot 0 :height 0.50 :width 0.50 :select t   :modeline nil)
(set-popup-rule! "*prodigy*"               :side 'right  :quit t :slot  1 :ttl nil :vslot 0 :height 0.50 :width 0.20 :select t   :modeline nil)
(set-popup-rule! "^*prodigy-.*$"           :side 'right  :quit t :slot  2 :ttl nil :vslot 0 :height 0.45 :width 0.40 :select nil :modeline nil)
(set-popup-rule! "^\\*compilation\\*.*$"   :side 'right  :quit t :slot  1 :ttl nil :vslot 0 :height 0.30 :width 0.50 :select nil :modeline nil)

(defadvice!   prompt-for-buffer (&rest _)  :after '(evil-window-split evil-window-vsplit) (consult-buffer))

(defun my/compile-multi-read-task () (let ((this-command 'compile-multi) (real-this-command 'compile-multi))
                                       (if (bound-and-true-p vertico-posframe-mode) (unwind-protect (progn (vertico-posframe-mode -1) (compile-multi--get-task)) (vertico-posframe-mode 1))
                                         (compile-multi--get-task))))

(defun my/compile-multi-prodigy ()
  (interactive)
  (let* ((task        (my/compile-multi-read-task))
         (title       (car task))
         (plain-title (substring-no-properties title))
         (plist       (cdr task)))
    (if (plist-get plist :prodigy)
        (if-let ((service (prodigy-find-service plain-title)))
            (progn (save-selected-window (prodigy))
                   (if (prodigy-service-started-p service)
                       (prodigy-restart-service service
                         (lambda () (save-selected-window (prodigy) (when-let ((buffer (get-buffer (prodigy-buffer-name service)))) (with-current-buffer buffer (unless (eq major-mode 'prodigy-view-mode) (prodigy-view-mode))) (display-buffer buffer)))))

                     (prodigy-start-service service
                       (lambda ()
                         (save-selected-window (prodigy) (when-let ((buffer (get-buffer (prodigy-buffer-name service)))) (with-current-buffer buffer (unless (eq major-mode 'prodigy-view-mode) (prodigy-view-mode))) (display-buffer buffer)))))))

          (message "No Prodigy service found for %s" plain-title))
      (compile-multi nil (plist-get plist :command)))))

(map! :n                                      "j" #'evil-next-visual-line
      :n                                      "k" #'evil-previous-visual-line
      :leader             :desc "Dirvish"     "k" #'dirvish
      :leader             :desc "vterm"       "j" #'+vterm/toggle
      :leader             :desc "Lazygit"     "l" #'+lazygit/toggle
      :leader             :desc "Treemacs"    "[" #'+treemacs/toggle
      :leader             :desc "Last buffer" "e" #'evil-switch-to-windows-last-buffer
      :leader :prefix "o" :desc "Prodigy"     "p" #'prodigy
      :leader :prefix "c" :desc "Compile"     "c" #'my/compile-multi-prodigy
      :leader :prefix "c" :desc "In-Progress" "p" #'compilation-goto-in-progress-buffer

      :map prodigy-mode-map :n "j" #'my/prodigy-next-service :n "k" #'my/prodigy-previous-service
      :map mu4e-headers-mode-map
      "M-p" #'mu4e-views-cursor-msg-view-window-up
      "M-n" #'mu4e-views-cursor-msg-view-window-down
      "i"   #'mu4e-views-mu4e-view-as-nonblocked-html
      "v"   #'mu4e-views-mu4e-select-view-msg-method
      "f"   #'mu4e-views-toggle-auto-view-selected-message)

(after! dape
  (defvar my/dape-use-custom-layout nil)

  ;; Forward RTT output into the DAPE REPL.
  (cl-defmethod dape-handle-event (conn (_event (eql probe-rs-rtt-data)) body) (when-let ((data (plist-get body :data))) (dape--repl-insert (concat data "\n"))))
  ;; Tell probe-rs that the RTT terminal window is open.
  (cl-defmethod dape-handle-event (conn (_event (eql probe-rs-rtt-channel-config)) _body) (dape-request conn "rttWindowOpened" '((channelNumber . 0) (windowIsOpen . t))))

  (setopt
   dape-request-timeout 60
   dape-repl-echo-shell-output t
   dape-info-variable-table-aligned t
   dape-buffer-window-arrangement 'gud
   dape-adapter-dir "~/.local/share/nix-doom/debug-adapters/"
   dape-display-source-buffer-action '((display-buffer-reuse-window display-buffer-same-window)) ;; Keep source in the selected main window.
   dape-info-buffer-window-groups    '(((dape-info-scope-mode 3) dape-info-breakpoints-mode dape-info-threads-mode)
                                       ((dape-info-scope-mode 0) dape-info-watch-mode) ((dape-info-scope-mode 2))
                                       (dape-info-stack-mode (dape-info-scope-mode 1) dape-info-modules-mode dape-info-sources-mode))
   display-buffer-alist      (append '(((lambda (_buffer alist) (and (eq dape-buffer-window-arrangement 'gud) (eq (alist-get 'category alist) 'dape-info-1)))
                                        (display-buffer-reuse-window display-buffer-in-side-window) (side . bottom) (slot . -1) (window-width . 0.70))
                                       ((lambda (_buffer alist) (and (eq dape-buffer-window-arrangement 'gud) (eq (alist-get 'category alist) 'dape-info-2)))
                                        (display-buffer-reuse-window display-buffer-in-side-window) (side . bottom) (slot . 0) (window-width . 0.15))
                                       ((lambda (_buffer alist) (and (eq dape-buffer-window-arrangement 'gud) (eq (alist-get 'category alist) 'dape-info-4)))
                                        (display-buffer-reuse-window display-buffer-in-side-window) (side . bottom) (slot . 1) (window-width . 0.15)))
                                     display-buffer-alist))

  (when my/dape-use-custom-layout
    (setopt
     dape-buffer-window-arrangement nil
     dape-info-buffer-window-groups '(((dape-info-scope-mode 3)) ((dape-info-scope-mode 1)) (dape-info-watch-mode)
                                      ((dape-info-scope-mode 0)) ((dape-info-scope-mode 2)) (dape-info-breakpoints-mode)
                                      (dape-info-threads-mode) (dape-info-stack-mode dape-info-modules-mode dape-info-sources-mode))
     display-buffer-alist
     (append
      '(
        ;; LEFT TOP: Variables
        ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-0))
         (display-buffer-reuse-window display-buffer-in-side-window)
         (side . left) (slot . 0) (window-width . 0.25))

        ;; RIGHT MID: Static
        ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-1))
         (display-buffer-reuse-window display-buffer-in-side-window)
         (side . right) (slot . 1) (window-width . 0.45) (window-height . 0.38))

        ;; LEFT: Stack / Modules / Sources
        ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-3))
         (display-buffer-reuse-window display-buffer-in-side-window)
         (side . left) (slot . 2) (window-width . 0.25) (window-height . 0.18))

        ;; LEFT LOWER: Watch
        ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-2))
         (display-buffer-reuse-window display-buffer-in-side-window)
         (side . left) (slot . 3) (window-width . 0.25) (window-height . 0.05))

        ;; LEFT BOTTOM: Breakpoints
        ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-5))
         (display-buffer-reuse-window
          (lambda (buffer alist)
            (let ((window (display-buffer-in-side-window buffer alist)))
              (with-current-buffer buffer (setq-local truncate-lines nil word-wrap t) (visual-line-mode 1)) window)))
         (side . left) (slot . 4) (window-width . 0.25) (window-height . 0.03))

        ;; LEFT BOTTOM: Threads
        ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-6))
         (display-buffer-reuse-window
          (lambda (buffer alist)
            (let ((window (display-buffer-in-side-window buffer alist)))
              (with-current-buffer buffer (setq-local truncate-lines nil word-wrap t) (visual-line-mode 1)) window)))
         (side . left) (slot . 5) (window-width . 0.25) (window-height . 0.03))

        ;; LEFT MID: Registers
        ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-4))
         (display-buffer-reuse-window
          (lambda (buffer alist)
            (let ((window (display-buffer-in-side-window buffer alist)))
              (with-current-buffer buffer (setq-local dape-info-variable-table-aligned t)) window)))
         (side . left) (slot . 1) (window-width . 0.25) (window-height . 0.24))

        ;; RIGHT TOP: Peripherals
        ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-7))
         (display-buffer-reuse-window
          (lambda (buffer alist)
            (let ((window (display-buffer-in-side-window buffer alist)))
              (with-current-buffer buffer (setq-local dape-info-variable-table-aligned t dape-info-variable-table-row-config '((name . 0) (value . 0) (type . 0)) face-remapping-alist '((default (:height 0.84)) (header-line (:height 0.84))))) window)))
         (side . right) (slot . 0) (window-width . 0.45) (window-height . 0.62))

        ;; REPL: top half of the center area only
        ("^\\*dape-repl\\*$" (display-buffer-reuse-window display-buffer-in-direction) (direction . above) (window-height . 0.3))
        ("^\\*Welcome to the Dape REPL\\*$" (display-buffer-reuse-window display-buffer-in-direction) (direction . above) (window-height . 0.3)))
      display-buffer-alist)))

  (add-to-list
   'dape-configs
   '(probe-rs-esp32s3
     :chip "esp32s3" :request "launch" :type "probe-rs-debug" :consoleLogLevel "Console" :flashingConfig (:flashingEnabled t)

     port :autoport host "localhost" command "probe-rs"
     modes (rust-mode rustic-mode)
     compile "cargo +esp probe-rs-debug-esp32s3"
     command-args ("dap-server" "--port" ":autoport")
     command-cwd (lambda () (project-root (project-current)))
     fn (lambda (config) (if (derived-mode-p 'dape-repl-mode) config (plist-put config 'compile nil)))
     :coreConfigs [(
                    :coreIndex 0 :rttEnabled t :rttChannelFormats [(:channelNumber 0 :showTimestamps t :dataFormat "String")]
                    :svdFile (lambda () (expand-file-name "boards/esp32s3.svd" (project-root (project-current))))
                    :programBinary (lambda () (expand-file-name "target/xtensa-esp32s3-none-elf/debug/esp32s3" (project-root (project-current)))))]))

  (add-hook!
   'dape-display-source-hook #'pulse-momentary-highlight-one-line
   'dape-repl-mode-hook (defun dape--repl-wrap () (setq-local truncate-lines nil word-wrap t) (visual-line-mode 1))
   'dape-info-parent-mode-hook
   (defun dape--info-compact ()
     (when (string-prefix-p "Registers" (format-mode-line header-line-format))
       (setq-local
        dape-info-variable-table-aligned t
        dape-info-variable-table-row-config '((name . 8) (value . 10) (type . 14))))
     (face-remap-add-relative 'header-line :height 0.9) (face-remap-add-relative 'default :height 0.9))))

(after! dap-mode
  (dap-register-debug-template
   "Embedded::OpenOCD"
   (list :autorun t
         :target ":3333"
         :request "attach"
         :type "gdbserver"
         :printCalls :json-false
         :name "Embedded::OpenOCD"
         :gdbpath "arm-none-eabi-gdb"
         :showDevDebugOutput :json-false
         :executable "target/thumbv7em-none-eabihf/debug/led-roulette"
         :debugger_args ["-q" "-ix" "extended-remote" "-x" "learning/rust/openocd.gdb"])))

(after! dirvish
  (setopt dirvish-default-layout '(1 0.11 0.70)
          dirvish-quick-access-entries
          `(("h" "~/"                          "Home")
            ("t" "~/.local/share/Trash/files/" "Trash")
            ("p" "~/Pictures/"                 "Pictures")
            ("w" "~/workspace/"                "Workspace")
            ("d" "~/Downloads/"                "Downloads")
            ("a" "~/Documents/"                "Documents")
            ("m" "/mnt/"                       "Mounted drives")
            ("e" ,user-emacs-directory         "Emacs user directory"))))

(defconst my/lazygit-command " lazygit status -sm normal")
(defvar my/vterm-warmed-projects (make-hash-table :test #'equal))

(defun my/project-root () (let ((root (or (doom-project-root default-directory) (and (fboundp 'projectile-project-root) (ignore-errors (projectile-project-root))) default-directory))) (file-name-as-directory (expand-file-name root))))

(defun my/vterm-buffer-name () (format "*doom:vterm-popup:project-%s*" (if (bound-and-true-p persp-mode) (safe-persp-name (get-current-persp)) "main")))

(defun my/vterm-project-buffer () (let* ((buffer-name (my/vterm-buffer-name)) (buffer (get-buffer-create buffer-name)) (root (my/project-root)))
                                    (with-current-buffer buffer (let ((default-directory root)) (unless (derived-mode-p 'vterm-mode) (vterm-mode)) (setq-local +vterm--id buffer-name))) buffer))

(defun my/warm-project-vterm ()
  "Pre-create vterm per project so first use is instant."
  (let ((root (my/project-root)))
    (unless (gethash root my/vterm-warmed-projects)
      (puthash root t my/vterm-warmed-projects)
      (run-with-idle-timer
       0.2 nil
       (lambda (dir)
         (when (file-directory-p dir)
           (let ((default-directory dir))
             (save-window-excursion
               (my/vterm-project-buffer)))))
       root))))

(defun +vterm/toggle ()
  "Toggle the project vterm buffer.
If lazygit is active there, quit it and leave the shell running."
  (interactive)
  (let ((buffer (my/vterm-project-buffer)))
    (if-let ((win (get-buffer-window buffer t)))
        (if (one-window-p) (bury-buffer buffer) (delete-window win))
      (unless (get-buffer-window buffer t)
        (pop-to-buffer buffer))
      (when (funcall
             (lambda ()
               (with-current-buffer buffer
                 (when-let* ((proc (get-buffer-process (current-buffer)))
                             ((process-live-p proc))
                             ((executable-find "pgrep")))
                   (ignore-errors
                     (process-lines "pgrep" "-P" (number-to-string (process-id proc)) "-f" "lazygit")
                     t)))))
        (with-current-buffer buffer
          (vterm-send-key "q"))))))

(defun +lazygit/toggle ()
  "Run lazygit in the shared project vterm buffer."
  (interactive)
  (let ((buffer (my/vterm-project-buffer)))
    (unless (get-buffer-window buffer t)
      (pop-to-buffer buffer))
    (with-current-buffer buffer
      (vterm-send-C-c)
      (vterm-send-string my/lazygit-command)
      (vterm-send-return))))

(defun my/switch-to-last-buffer-in-split ()
  "Show last buffer on split screen."
  (interactive)
  (let ((current-buffer (current-buffer)))
    (if (one-window-p) (progn (split-window-right) (evil-switch-to-windows-last-buffer) (switch-to-buffer current-buffer)))))

(after! org
  (define-key org-mode-map (kbd "C-c C-r") verb-command-map)
  (setq
   org-startup-numerated 1
   org-tag-beautify-mode 1
   org-link-beautify-mode 1
   org-modern-table-vertical 1
   org-modern-table-horizontal 0.2
   org-link-search-must-match-exact-headline nil
   ;; org-modern-priority-faces
   org-priority-faces '((?A :foreground "#e45649")
                        (?B :foreground "#da8548")
                        (?C :foreground "#0098dd"))
   org-modern-star ["◉" "○" "✸" "✿" "✤" "✜" "◆" "▶"]
   org-modern-list '((43 . "➤") (45 . "–") (42 . "•"))
   ;; org-modern-todo-faces
   org-todo-keyword-faces '(("DONE" :foreground "#50a14f" :weight normal :underline t)
                            ("TODO" :foreground "#7c7c75" :weight normal :underline t)
                            ("BLOCKED" :foreground "#ff9800" :weight normal :underline t)
                            ("CANCELLED" :foreground "#ff6480" :weight normal :underline t)
                            ("INPROGRESS" :foreground "#0098dd" :weight normal :underline t))
   ;; org-modern-todo
   org-todo-keywords  '((sequence "TODO(t)" "INPROGRESS(i)" "BLOCKED(b)" "|" "DONE(d)" "CANCELLED(c)")))
  ;; org-modern-todo nil
  ;; org-modern-priority nil
  ;; org-modern-footnote (cons nil (cadr org-script-display))
  ;; (custom-set-faces! '(org-modern-statistics :inherit org-checkbox-statistics-todo))
  ;; (after! spell-fu (cl-pushnew 'org-modern-tag (alist-get 'org-mode +spell-excluded-faces-alist)))

  (org-babel-do-load-languages 'org-babel-load-languages
                               (append org-babel-load-languages '((duckdb . t)))))

(after! magit
  (setopt magit-diff-refine-hunk 'all
          magit-log-margin-show-author t
          magit-revision-insert-related-refs t
          magit-log-margin-show-committer-date t
          magit-section-visibility-indicator '(" " . " ")
          magit-status-margin '(t age magit-log-margin-width t 22)
          magit-format-file-function #'magit-format-file-nerd-icons
          magit-revision-show-gravatars '("^Author:     " . "^Commit:     ")
          magit-log-arguments '("--graph" "--decorate" "--color" "--abbrev-commit" "-n256"))

  (add-hook 'magit-mode-hook (lambda ()
                               (hl-line-mode 1)
                               (magit-delta-mode 1)
                               ;; (display-line-numbers-mode 1)
                               ))
  (custom-set-faces
   '(magit-diff-context ((t (:foreground "#b0b0b0"))))
   '(magit-diff-hunk-heading ((t (:background "#3a3f5a"))))
   '(magit-section-heading ((t (:foreground "#ffff00" :weight bold))))
   '(magit-diff-added ((t (:foreground "#00ff00" :background "#002200"))))
   '(magit-diff-removed ((t (:foreground "#ff0000" :background "#220000"))))
   '(magit-diff-hunk-heading-highlight ((t (:background "#51576d" :foreground "#ffffff"))))))

;; (use-package! gptel
;;   :config
;;   (setopt gptel-use-tools t
;;         gptel-track-media t
;;         gptel-default-mode #'org-mode
;;         gptel-directives '((writing     . "You are a large language model and a writing assistant.")
;;                            (chat        . "You are a large language model and a conversation partner.")
;;                            (programming . "You are a large language model and a careful programmer. Provide code and only code as output without any additional text, prompt or note.")
;;                            (default     . "You are a large language model living in Doom Emacs and a helpful assistant. I'm using Doom Emacs with Evil Mode inside Arch Linux with Hyprland. I browse the web with Vivaldi and Surfingkeys. I also use Nix with home manager for configuration management, daily drive NixOS and Nix Darwin MacOS from time to time. I prefer to write code in Rust, and Nix. When responding for code snippets, always take best practices, design patterns, and scalability into account while keeping things simple. Always follow up your responses with questions and ideas. Do not be blunt when responding, provide justification and educate me if you notice that I may be misled."))
;;         gptel-model 'llama3.2:3b
;;         gptel-backend (gptel-make-ollama "Ollama"
;;                         :stream t
;;                         :host "localhost:11434"
;;                         :models '(llava:34b
;;                                   llama3.2:3b
;;                                   gpt-oss:20b
;;                                   gpt-oss:120b
;;                                   mistral:latest
;;                                   qwen2.5-coder:32b
;;                                   phind-codellama:34b))
;;         ;; gptel-api-key "your key"
;;         ;; gptel-model 'gpt-4.1
;;         ;; gptel-backend (gptel-make-gh-copilot "Copilot")
;;         )

;;   (gptel-make-preset 'gpt-4.1
;;     :model 'gpt-4.1
;;     :backend "Copilot"
;;     :description "GPT 4.1 from GitHub")

;;   (defun llm-tool-collection-register-with-gptel (tool-spec)
;;     "Register a tool defined by TOOL-SPEC with gptel.
;;   TOOL-SPEC is a plist that can be passed to `gptel-make-tool'."
;;     (let ((tool (apply #'gptel-make-tool tool-spec)))
;;       (setopt gptel-tools (cons tool (seq-remove (lambda (existing) (string= (gptel-tool-name existing) (gptel-tool-name tool))) gptel-tools)))))

;;   (add-hook 'llm-tool-collection-post-define-functions #'llm-tool-collection-register-with-gptel)
;;   (add-hook 'gptel-post-stream-hook 'gptel-auto-scroll 'gptel-post-response-functions 'gptel-end-of-response))

;; (use-package! llm-tool-collection)
;; (after! llm-tool-collection
;;   (mapcar (apply-partially #'apply #'gptel-make-tool) (llm-tool-collection-get-all)))

;; (define-derived-mode likec4-mode prog-mode "LikeC4" "Major mode for editing LikeC4 files.")
;; (add-to-list 'auto-mode-alist '("\\.c4\\'" . likec4-mode))
;; (after! lsp-mode
;;   (add-to-list 'lsp-language-id-configuration '(likec4-mode . "likec4"))
;;   (lsp-register-client
;;    (make-lsp-client
;;     :priority -1
;;     :server-id 'likec4
;;     :major-modes '(likec4-mode)
;;     ;; :new-connection (lsp-stdio-connection '("likec4-language-server" "--stdio"))
;;     :new-connection (lsp-stdio-connection '("npx" "@likec4/language-server" "--stdio")))))

;; https://git.sr.ht/~morgansmith/sway-ts-mode
;; ;; (load! "./extra/sway-ts-mode")
;; (setopt treesit-extra-load-path "./extra")

;; karthinks.com/software/emacs-window-management-almanac/
;; notes.justin.vc/config

;; Reconfigure packages with `after!' block wrap, otherwise Doom's defaults may override your settings. E.g.
;;   (after! PACKAGE
;;     (setopt x y))
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
;; - `add-load-path! directories to the `load-path', relative to
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

;; You do not need to run 'doom sync' after modifying this file!

;; Doom exposes five (optional) variables for controlling fonts in Doom:
;; - `doom-font' -- primary font to use
;; - `doom-big-font' -- used for `doom-big-font-mode'
;; - `doom-serif-font' -- for `fixed-pitch-serif' face
;; - `doom-symbol-font' -- for symbols
;; - `doom-variable-pitch-font' -- a non-monospace font (where applicable)
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
;; `load-theme' function.

;; https://www.ovistoica.com/blog/2024-7-05-modern-emacs-typescript-web-tsx-config
