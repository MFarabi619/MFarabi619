;;; config.el -*- lexical-binding: t; -*-

;;; Lockdowns. The container is the actual security boundary; this is
;;; belt-and-suspenders so a clever visitor doesn't trivially M-x their
;;; way into a shell.

;; Disable shell escapes
(dolist (cmd '(shell eshell vterm term ansi-term
               async-shell-command shell-command
               dired-do-shell-command compile recompile
               grep find-grep find-name-dired
               proced))
  (put cmd 'disabled "Shell access is disabled in browse mode."))

;; Disable file-write paths
(advice-add 'save-buffer       :override #'ignore)
(advice-add 'write-file        :override #'ignore)
(advice-add 'write-region      :override (lambda (&rest _) nil))
(advice-add 'rename-file       :override #'ignore)
(advice-add 'delete-file       :override #'ignore)
(advice-add 'make-directory    :override #'ignore)
(advice-add 'copy-file         :override #'ignore)

;; Block tramp / network primitives from elisp
(setq tramp-mode nil)
(advice-add 'url-retrieve              :override (lambda (&rest _) (error "Network disabled")))
(advice-add 'url-retrieve-synchronously :override (lambda (&rest _) (error "Network disabled")))
(advice-add 'open-network-stream       :override (lambda (&rest _) (error "Network disabled")))
(advice-add 'make-network-process      :override (lambda (&rest _) (error "Network disabled")))

;; Land on README.org, force read-only
(add-hook 'doom-after-init-hook
          (lambda ()
            (when (file-readable-p "/repo/README.org")
              (find-file "/repo/README.org")
              (read-only-mode 1))))

;; UI niceties for visitors
(setq inhibit-startup-message t
      initial-scratch-message
      ";; Apidae Systems --- public read-only Emacs.\n;; All keybindings work; nothing you do is persisted.\n\n")
