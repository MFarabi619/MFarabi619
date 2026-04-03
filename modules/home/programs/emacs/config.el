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

;; https://git.sr.ht/~morgansmith/sway-ts-mode
;; ;; (load! "./extra/sway-ts-mode")
;; (setq treesit-extra-load-path "./extra")

;; (parrot-mode)
;; (nyan-mode t)
;; (minimap-mode)
(display-time-mode 1)
(kitty-graphics-mode 1)
(window-divider-mode -1)
(global-undo-tree-mode 1)
;; (keycast-tab-line-mode)
;; (+global-word-wrap-mode +1)
(dape-breakpoint-global-mode 1)
(set-language-environment "UTF-8")
(set-default-coding-systems 'utf-8)
(set-frame-parameter nil 'undecorated t)
(add-to-list 'default-frame-alist '(undecorated . t))

(setq nyan-wavy-trail t
      doom-modeline-hud t
      nyan-animate-nyancat t
      doom-theme 'doom-gruvbox
      ;; doom-theme 'catppuccin
      which-key-idle-delay 0.25
      evil-split-window-below t
      doom-modeline-time-icon t
      evil-vsplit-window-right t
      doom-modeline-persp-name t
      doom-symbol-font doom-font
      display-time-day-and-date t
      compilation-scroll-output t
      treemacs-git-mode 'extended
      find-file-visit-truename nil
      evil-escape-key-sequence "jk"
      org-latex-compiler "lualatex"
      ;; doom-lantern-padded-modeline t
      doom-modeline-major-mode-icon t
      org-directory "~/Documents/org/"
      user-full-name "Mumtahin Farabi"
      display-line-numbers-type 'relative
      plantuml-default-exec-mode "executable"
      which-key-allow-multiple-replacements t ;; Remove 'evil-' in too many popups
      user-mail-address "mfarabi619@gmail.com"
      ;; plstore-cache-passphrase-for-symmetric-encryption t
      browse-url-browser-function 'browse-url-default-browser
      fancy-splash-image "~/MFarabi619/assets/apollyon-emacs.png"
      projectile-project-search-path '("~/workspace/" "~/Documents/")
      doom-font (font-spec :family "JetBrainsMono Nerd Font" :size 14)
      doom-big-font (font-spec :family "JetBrainsMono Nerd Font" :size 32)
      doom-variable-pitch-font (font-spec :family "JetBrainsMono Nerd Font" :size 14))

;; https://github.com/cuspymd/tramp-term.el
(after! tramp
  (setq tramp-verbose 1
        tramp-default-method "sshx"
        tramp-connection-timeout 10))

(after! treesit
  (setq treesit-font-lock-level 4
        treesit-auto-install-grammar 'always))

(after! treemacs
  (setq treemacs-position 'left
        treemacs-follow-mode t
        lsp-treemacs-theme "Default" ;; "Idea" "Eclipse" "NetBeans"
        ;; treemacs-indent-guide-mode t
        treemacs-git-commit-diff-mode t
        treemacs-nerd-icons-icon-size 2.0
        treemacs-display-in-side-window t
        ;; treemacs-load-theme "doom-colors"
        lsp-treemacs-symbols-position-params '((side . right) (slot . 2) (window-width . 100))))

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

(add-hook! 'sql-mode-hook #'lsp!)
;; (add-hook! 'sql-mode-hook #'sqlup-mode!)
;; (add-hook! 'sql-interactive-mode-hook #'sqlup-mode!)

(add-hook! 'conf-toml-mode-hook #'lsp!)
;; (add-hook! 'lsp-mode-hook #'lsp-inlay-hints-mode)

(after! sql
  (setq sql-port 5432
        sql-password ""
        sql-user "mfarabi"
        sql-server "127.0.0.1"
        sql-database "microvisor"))

(setopt lsp-postgres-server-path "postgrestools")
(add-hook! '(sql-mode-hook sql-interactive-mode-hook)
  (setq-local sql-default-directory (projectile-project-root))
  (sql-highlight-postgres-keywords))

(after! lsp
  (setq lsp-enable-folding t
        lsp-eldoc-render-all t
        lsp-before-save-edits t
        lsp-inlay-hint-enable t
        lsp-completion-enable t
        lsp-auto-execute-action t
        lsp-describe-thing-at-point t))

(after! lsp-clangd
  (set-lsp-priority! 'clangd 2)
  (setq lsp-clients-clangd-args '("-j=3"
                                  "--clang-tidy"
                                  "--background-index"
                                  "--header-insertion=never"
                                  "--completion-style=detailed"
                                  "--header-insertion-decorators=0")))

(after! dape
  (setopt dape-adapter-dir "~/.local/share/nix-doom/debug-adapters/")
  (defvar my/dape-use-custom-layout nil)

  ;; Forward RTT output into the DAPE REPL.
  (cl-defmethod dape-handle-event (conn (_event (eql probe-rs-rtt-data)) body)
    (when-let ((data (plist-get body :data))) (dape--repl-insert (concat data "\n"))))

  ;; Tell probe-rs that the RTT terminal window is open.
  (cl-defmethod dape-handle-event (conn (_event (eql probe-rs-rtt-channel-config)) _body)
    (dape-request conn "rttWindowOpened" '((channelNumber . 0) (windowIsOpen . t))))

  (setq dape-request-timeout 60
        dape-repl-echo-shell-output t
        dape-info-variable-table-aligned t
        dape-buffer-window-arrangement 'gud
        ;; Keep source in the selected main window.
        dape-display-source-buffer-action '((display-buffer-reuse-window display-buffer-same-window))
        dape-info-buffer-window-groups '(
                                         ((dape-info-scope-mode 3) dape-info-breakpoints-mode dape-info-threads-mode)
                                         ((dape-info-scope-mode 0) dape-info-watch-mode)
                                         ((dape-info-scope-mode 2))
                                         (dape-info-stack-mode (dape-info-scope-mode 1) dape-info-modules-mode dape-info-sources-mode)
                                         ))

  (setq display-buffer-alist
        (append
         '(((lambda (_buffer alist)
              (and (eq dape-buffer-window-arrangement 'gud)
                   (eq (alist-get 'category alist) 'dape-info-1)))
            (display-buffer-reuse-window display-buffer-in-side-window)
            (side . bottom)
            (slot . -1)
            (window-width . 0.70))
           ((lambda (_buffer alist)
              (and (eq dape-buffer-window-arrangement 'gud)
                   (eq (alist-get 'category alist) 'dape-info-2)))
            (display-buffer-reuse-window display-buffer-in-side-window)
            (side . bottom)
            (slot . 0)
            (window-width . 0.15))
           ((lambda (_buffer alist)
              (and (eq dape-buffer-window-arrangement 'gud)
                   (eq (alist-get 'category alist) 'dape-info-4)))
            (display-buffer-reuse-window display-buffer-in-side-window)
            (side . bottom)
            (slot . 1)
            (window-width . 0.15)))
         display-buffer-alist))

  (when my/dape-use-custom-layout
    (setq dape-buffer-window-arrangement nil
          dape-info-buffer-window-groups '(((dape-info-scope-mode 3))
                                           ((dape-info-scope-mode 1))
                                           (dape-info-watch-mode)
                                           ((dape-info-scope-mode 0))
                                           ((dape-info-scope-mode 2))
                                           (dape-info-breakpoints-mode)
                                           (dape-info-threads-mode)
                                           (dape-info-stack-mode dape-info-modules-mode dape-info-sources-mode))
          display-buffer-alist
          (append
           '(
             ;; LEFT TOP: Variables
             ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-0))
              (display-buffer-reuse-window display-buffer-in-side-window)
              (side . left)
              (slot . 0)
              (window-width . 0.25))

             ;; RIGHT MID: Static
             ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-1))
              (display-buffer-reuse-window display-buffer-in-side-window)
              (side . right)
              (slot . 1)
              (window-width . 0.45)
              (window-height . 0.38))

             ;; LEFT: Stack / Modules / Sources
             ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-3))
              (display-buffer-reuse-window display-buffer-in-side-window)
              (side . left)
              (slot . 2)
              (window-width . 0.25)
              (window-height . 0.18))

             ;; LEFT LOWER: Watch
             ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-2))
              (display-buffer-reuse-window display-buffer-in-side-window)
              (side . left)
              (slot . 3)
              (window-width . 0.25)
              (window-height . 0.05))

             ;; LEFT BOTTOM: Breakpoints
             ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-5))
              (display-buffer-reuse-window
               (lambda (buffer alist)
                 (let ((window (display-buffer-in-side-window buffer alist)))
                   (with-current-buffer buffer
                     (setq-local truncate-lines nil
                                 word-wrap t)
                     (visual-line-mode 1))
                   window)))
              (side . left)
              (slot . 4)
              (window-width . 0.25)
              (window-height . 0.03))

             ;; LEFT BOTTOM: Threads
             ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-6))
              (display-buffer-reuse-window
               (lambda (buffer alist)
                 (let ((window (display-buffer-in-side-window buffer alist)))
                   (with-current-buffer buffer
                     (setq-local truncate-lines nil
                                 word-wrap t)
                     (visual-line-mode 1))
                   window)))
              (side . left)
              (slot . 5)
              (window-width . 0.25)
              (window-height . 0.03))

             ;; LEFT MID: Registers
             ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-4))
              (display-buffer-reuse-window
               (lambda (buffer alist)
                 (let ((window (display-buffer-in-side-window buffer alist)))
                   (with-current-buffer buffer
                     (setq-local dape-info-variable-table-aligned t))
                   window)))
              (side . left)
              (slot . 1)
              (window-width . 0.25)
              (window-height . 0.24))

             ;; RIGHT TOP: Peripherals
             ((lambda (_buffer alist) (eq (alist-get 'category alist) 'dape-info-7))
              (display-buffer-reuse-window
               (lambda (buffer alist)
                 (let ((window (display-buffer-in-side-window buffer alist)))
                   (with-current-buffer buffer
                     (setq-local dape-info-variable-table-aligned t
                                 dape-info-variable-table-row-config '((name . 0) (value . 0) (type . 0))
                                 face-remapping-alist
                                 '((default (:height 0.84))
                                   (header-line (:height 0.84)))))
                   window)))
              (side . right)
              (slot . 0)
              (window-width . 0.45)
              (window-height . 0.62))

             ;; REPL: top half of the center area only
             ("^\\*dape-repl\\*$"
              (display-buffer-reuse-window display-buffer-in-direction)
              (direction . above)
              (window-height . 0.3))
             ("^\\*Welcome to the Dape REPL\\*$"
              (display-buffer-reuse-window display-buffer-in-direction)
              (direction . above)
              (window-height . 0.3)))
           display-buffer-alist)))

  (add-to-list
   'dape-configs
   '(probe-rs-esp32s3
     fn (lambda (config) (if (derived-mode-p 'dape-repl-mode) config (plist-put config 'compile nil)))
     :chip "esp32s3"
     :request "launch"
     :type "probe-rs-debug"
     :consoleLogLevel "Console"
     :flashingConfig (:flashingEnabled t)

     port :autoport
     host "localhost"
     command "probe-rs"
     modes (rust-mode rustic-mode)
     command-args ("dap-server" "--port" ":autoport")
     command-cwd (lambda () (project-root (project-current)))
     compile "cargo +esp probe-rs-debug-esp32s3"
     :coreConfigs [(
                    :coreIndex 0
                    :rttEnabled t
                    :rttChannelFormats [(:channelNumber 0 :showTimestamps t :dataFormat "String")]
                    :svdFile (lambda () (expand-file-name "boards/esp32s3.svd" (project-root (project-current))))
                    :programBinary (lambda () (expand-file-name "target/xtensa-esp32s3-none-elf/debug/esp32s3" (project-root (project-current)))))]))

  :config
  (add-hook 'dape-display-source-hook #'pulse-momentary-highlight-one-line)
  (add-hook 'dape-repl-mode-hook (defun dape--repl-wrap ()
                                   (setq-local truncate-lines nil word-wrap t)
                                   (visual-line-mode 1)))
  (add-hook 'dape-info-parent-mode-hook
            (defun dape--info-compact ()
              (when (string-prefix-p "Registers" (format-mode-line header-line-format))
                (setq-local dape-info-variable-table-aligned t
                            dape-info-variable-table-row-config
                            '((name . 8) (value . 10) (type . 14))))
              (face-remap-add-relative 'header-line :height 0.9)
              (face-remap-add-relative 'default :height 0.9))))

(setq gdb-debuginfod-enable-setting t
      gud-gdb-command-name "arm-none-eabi-gdb -i=mi")

(after! dap-gdb
  (setq dap-gdb-debug-program '("arm-none-eabi-gdb" "-i" "dap")))

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

(after! dired
  (setq dirvish-peek-mode t
        dirvish-side-auto-close t
        dirvish-side-follow-mode t
        dired-listing-switches "-alhX"
        dirvish-side-display-alist '((side . right) (slot . -1))))

(after! dirvish
  (setq dirvish-default-layout '(1 0.11 0.70)
        dirvish-quick-access-entries
        `(("h" "~/"                          "Home")
          ("t" "~/.local/share/Trash/files/" "Trash")
          ("p" "~/Pictures/"                 "Pictures")
          ("w" "~/workspace/"                "Workspace")
          ("d" "~/Downloads/"                "Downloads")
          ("a" "~/Documents/"                "Documents")
          ("m" "/mnt/"                       "Mounted drives")
          ("e" ,user-emacs-directory         "Emacs user directory"))))

;; (add-load-path! "pio-mode")
;; (use-package! pio-mode)

(use-package! kbd-mode)
(unless (eq system-type 'berkeley-unix) ; *BSD/Solaris
  (use-package! exercism))

(use-package! gptel-integrations)
(use-package! gptel
  :config
  (setq gptel-use-tools t
        gptel-track-media t
        gptel-default-mode #'org-mode
        gptel-directives '((writing     . "You are a large language model and a writing assistant.")
                           (chat        . "You are a large language model and a conversation partner.")
                           (programming . "You are a large language model and a careful programmer. Provide code and only code as output without any additional text, prompt or note.")
                           (default     . "You are a large language model living in Doom Emacs and a helpful assistant. I'm using Doom Emacs with Evil Mode inside Arch Linux with Hyprland. I browse the web with Vivaldi and Surfingkeys. I also use Nix with home manager for configuration management, daily drive NixOS and Nix Darwin MacOS from time to time. I prefer to write code in Rust, and Nix. When responding for code snippets, always take best practices, design patterns, and scalability into account while keeping things simple. Always follow up your responses with questions and ideas. Do not be blunt when responding, provide justification and educate me if you notice that I may be misled."))
        gptel-model 'llama3.2:3b
        gptel-backend (gptel-make-ollama "Ollama"
                        :stream t
                        :host "localhost:11434"
                        :models '(llava:34b
                                  llama3.2:3b
                                  gpt-oss:20b
                                  gpt-oss:120b
                                  mistral:latest
                                  qwen2.5-coder:32b
                                  phind-codellama:34b))
        ;; gptel-api-key "your key"
        ;; gptel-model 'gpt-4.1
        ;; gptel-backend (gptel-make-gh-copilot "Copilot")
        )

  (gptel-make-preset 'gpt-4.1
    :model 'gpt-4.1
    :backend "Copilot"
    :description "GPT 4.1 from GitHub")

  (defun llm-tool-collection-register-with-gptel (tool-spec)
    "Register a tool defined by TOOL-SPEC with gptel.
  TOOL-SPEC is a plist that can be passed to `gptel-make-tool'."
    (let ((tool (apply #'gptel-make-tool tool-spec)))
      (setq gptel-tools (cons tool (seq-remove (lambda (existing) (string= (gptel-tool-name existing) (gptel-tool-name tool))) gptel-tools)))))

  (add-hook 'llm-tool-collection-post-define-functions #'llm-tool-collection-register-with-gptel)
  (add-hook 'gptel-post-stream-hook 'gptel-auto-scroll 'gptel-post-response-functions 'gptel-end-of-response))

(use-package! llm-tool-collection)
(after! llm-tool-collection
  (mapcar (apply-partially #'apply #'gptel-make-tool) (llm-tool-collection-get-all)))

(map! :n "C-'" #'+vterm/toggle
      :leader :desc "Open Dirvish" "k" #'dirvish
      :leader :desc "Toggle vterm" "j" #'+vterm/toggle
      :leader :desc "Open Lazygit" "l" #'+lazygit/toggle
      ;; :leader :desc "Open Dirvish Side" "[" #'dirvish-side
      :leader :desc "Open Dirvish Side" "[" #'+treemacs/toggle)

(map! :map evil-window-map
      "SPC"       #'rotate-layout
      "<up>"      #'evil-window-up
      "<left>"    #'evil-window-left
      "<down>"    #'evil-window-down
      "<right>"   #'evil-window-right
      "C-<up>"    #'+evil/window-move-up
      "C-<left>"  #'+evil/window-move-left
      "C-<down>"  #'+evil/window-move-down
      "C-<right>" #'+evil/window-move-right)

(set-popup-rule! "*Ollama*"
  :ttl 0
  :size 0.5
  :vslot -4
  :quit nil
  :select t
  :modeline t
  :side 'left)

(set-popup-rule! "*Copilot*"
  :ttl 0
  :size 0.5
  :vslot -4
  :quit nil
  :select t
  :modeline t
  :side 'left)

(set-popup-rule! "^\\*Flycheck errors\\*$"
  :size 0.4
  :select t
  :side 'bottom)

(set-popup-rule! "*doom:vterm-popup:*"
  :quit t
  :slot 0
  :ttl nil
  :vslot 0
  :select t
  :width 0.5
  :height 0.5
  :modeline nil
  :side 'right)

(defconst my/lazygit-command " lazygit status -sm normal")
(defvar my/vterm-warmed-projects (make-hash-table :test #'equal))

(defun my/project-root ()
  (let ((root (or (doom-project-root default-directory)
                  (and (fboundp 'projectile-project-root)
                       (ignore-errors (projectile-project-root)))
                  default-directory)))
    (file-name-as-directory (expand-file-name root))))

(defun my/vterm-buffer-name ()
  (format "*doom:vterm-popup:project-%s*"
          (if (bound-and-true-p persp-mode)
              (safe-persp-name (get-current-persp))
            "main")))

(defun my/vterm-project-buffer ()
  (let* ((buffer-name (my/vterm-buffer-name))
         (buffer (get-buffer-create buffer-name))
         (root (my/project-root)))
    (with-current-buffer buffer
      (let ((default-directory root))
        (unless (derived-mode-p 'vterm-mode)
          (vterm-mode))
        (setq-local +vterm--id buffer-name)))
    buffer))

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

(after! compile-multi
  (setopt compile-multi-default-directory #'projectile-project-root))

(after! projectile
  (add-hook 'projectile-after-switch-project-hook #'my/warm-project-vterm))

(add-hook 'doom-first-buffer-hook #'my/warm-project-vterm)

(add-hook 'find-file-hook #'my/warm-project-vterm)

(after! direnv
  (direnv-mode -1))

(defun my/switch-to-last-buffer-in-split ()
  "Show last buffer on split screen."
  (interactive)
  (let ((current-buffer (current-buffer)))
    (if (one-window-p)
        (progn
          (split-window-right)
          (evil-switch-to-windows-last-buffer)
          (switch-to-buffer current-buffer)))))

(map! ;; Remap switching to last buffer from 'SPC+`' to 'SPC+e'
 :desc "Switch to last buffer"
 :leader "e" #'evil-switch-to-windows-last-buffer
 ;; "e" #'my/switch-to-last-buffer-in-split
 )

(defadvice! prompt-for-buffer (&rest _)
  :after '(evil-window-split evil-window-vsplit)
  (consult-buffer))

(add-hook
 'pdf-view-mode-hook
 'pdf-view-midnight-minor-mode
 'doom-modeline-mode-hook #'nyan-mode)

(after! evil
  (setq evil-ex-substitute-global t)
  (add-hook 'evil-local-mode-hook 'turn-on-undo-tree-mode)
  (define-key evil-normal-state-map (kbd "j") 'evil-next-visual-line)
  (define-key evil-normal-state-map (kbd "k") 'evil-previous-visual-line))

(use-package! ob-duckdb
  :ensure t
  :after org
  :custom
  (org-babel-duckdb-max-rows 200)
  (org-babel-duckdb-show-progress t)
  (org-babel-duckdb-queue-display 'auto) ; or 'manual
  (org-babel-duckdb-queue-position 'side)
  (org-babel-duckdb-progress-display 'popup)
  (org-babel-duckdb-output-buffer "*DuckDB Results*")

  ;; :config
  ;; ;; Optional: MotherDuck token from file
  ;; (setq org-babel-duckdb-motherduck-token
  ;;       (lambda ()
  ;;         (with-temp-buffer
  ;;           (insert-file-contents "~/.config/duckdb/.motherduck_token")
  ;;           (string-trim (buffer-string)))))
  )

(use-package! org-anki)

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
  ;; (use-package! magit-todos
  ;;   :config (magit-todos-mode 1))
  (setq magit-diff-refine-hunk 'all
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

(after! magit-delta
  (setq magit-delta-hide-plus-minus-markers t
        ;; magit-delta-default-dark-theme "Gruvbox"
        magit-delta-delta-args (append magit-delta-delta-args '("--side-by-side" "--line-numbers"))))

(after! verb-mode
  (setq verb-auto-show-headers-buffer t
        verb-json-use-mode #'json-ts-mode
        verb-auto-kill-response-buffers t))

;; (gfm-mode-hook 'gfm-view-mode)

(after! nerd-icons
  (setq nerd-icons-completion-mode t))

(after! pdf-tools
  (setq pdf-view-continuous t))

(after! nov-xwidget
  :demand t
  :after nov
  :config
  (define-key nov-mode-map (kbd "o") 'nov-xwidget-view)
  (add-hook 'nov-mode-hook 'nov-xwidget-inject-all-files))

(use-package! fretboard)
(after! fretboard
  (setq fretboard-fret-count 15)
  (add-hook 'fretboard-mode-hook #'evil-emacs-state))

(after! osm
  (setopt osm-copyright t
          osm-home (list 45.38730243858645 -75.69539479599302 15)))

(after! which-key
  (pushnew!
   which-key-replacement-alist
   '(("" . "\\`+?evil[-:]?\\(?:a-\\)?\\(.*\\)") . (nil . "◂\\1"))
   '(("\\`g s" . "\\`evilem--?motion-\\(.*\\)") . (nil . "◃\\1"))))

(load! "./dashboard.el")

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
