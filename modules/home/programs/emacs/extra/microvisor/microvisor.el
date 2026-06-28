;;; microvisor.el --- Project task and service orchestration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; Keywords: lisp, tools, convenience
;; Package-Requires: ((emacs "29.1") (compile-multi "0.7") (prodigy "0.7") (nerd-icons "0.1") (projectile "2.8"))

;; This file is not part of GNU Emacs.

;;; Commentary:

;;; Code:

(require 'seq)
(require 'cl-lib)
(require 'subr-x)
(require 'compile-multi)
(require 'prodigy)
(require 'nerd-icons)
(require 'projectile)

(let* ((this-dir   (file-name-directory (or load-file-name buffer-file-name)))
        (parent-dir (file-name-directory (directory-file-name this-dir))))
  (dolist (subdir '("pixi" "west" "zephyr" "pio-mode" "mcumgr" "tailscale"))
    (let ((sibling (expand-file-name subdir parent-dir)))
      (when (file-directory-p sibling)
        (add-to-list 'load-path sibling)))))

(load "pixi"      'noerror 'nomessage)
(load "west"      'noerror 'nomessage)
(load "zephyr"    'noerror 'nomessage)
(load "mcumgr"    'noerror 'nomessage)
(load "pio-mode"  'noerror 'nomessage)
(load "tailscale" 'noerror 'nomessage)

(defgroup microvisor ()
  "Project task and service orchestration."
  :prefix "microvisor-"
  :group 'tools)

(defcustom microvisor-icon-faces
  '(("emacs"      . nerd-icons-dpurple)
     ("dioxus"     . nerd-icons-blue)
     ("cargo"      . nerd-icons-orange)
     ("west"       . nerd-icons-purple)
     ("platformio" . nerd-icons-yellow)
     ("pulumi"     . nerd-icons-purple)
     ("pkg"        . nerd-icons-red)
     ("apt"        . nerd-icons-dred)
     ("pacman"     . nerd-icons-blue)
     ("guix"       . nerd-icons-yellow)
     ("pkg_add"    . nerd-icons-yellow)
     ("nix"        . nerd-icons-lblue)
     ("devenv"     . nerd-icons-lblue))
  "Alist mapping `:annotation' prefix words to nerd-icons faces.
The prefix is the first whitespace-separated word of an entry's
`:annotation' string; the last word is taken as the user-provided
icon glyph and rendered in the looked-up face."
  :type '(alist :key-type string :value-type symbol)
  :group 'microvisor)

(defun microvisor-icon-face (prefix)
  "Return the face for annotation PREFIX, or nil if not registered."
  (alist-get prefix microvisor-icon-faces nil nil #'equal))

(setq compile-multi-annotate-cmds        t
  compile-multi-annotate-limit       10
  compile-multi-annotate-string-cmds nil
  compile-multi-group-cmds           'group-and-replace)

(defun microvisor--icon-glyph-p (word)
  "Non-nil when WORD is a single nerd-icons glyph (Private Use Area)."
  (and (= (length word) 1) (>= (aref word 0) #xE000)))

(defun microvisor--annotation-function (original-function task)
  "Right-align the `:annotation' of TASK as an optional label plus an icon.
An annotation of `LABEL... ICON' colors ICON via the LABEL face key; a lone
glyph renders icon-only (caller owns its face).  Else call ORIGINAL-FUNCTION."
  (if-let* ((annotation-text (plist-get (cdr task) :annotation))
             ((stringp annotation-text))
             ((fboundp 'nerd-icons-icon-for-file))
             (words (split-string (string-trim-right annotation-text)
                      "[[:space:]]+" t))
             (spec (let ((face (and (> (length words) 1)
                                 (microvisor-icon-face (car words)))))
                     (cond
                       ((and (= (length words) 1)
                          (microvisor--icon-glyph-p (car words)))
                         (cons "" (car words)))
                       (face
                         (cons (string-join (butlast words) " ")
                           (propertize (car (last words)) 'face face)))))))
    (let* ((label (car spec))
            (icon  (cdr spec))
            (truncated (if (and compile-multi-annotate-limit
                             (> (length label) compile-multi-annotate-limit))
                         (concat (truncate-string-to-width
                                   label compile-multi-annotate-limit)
                           "…")
                         label))
            (rendered (if (string-empty-p label)
                        icon
                        (concat (propertize truncated 'face 'completions-annotations)
                          " " icon)))
            (width (string-width (substring-no-properties rendered))))
      (concat " "
        (propertize " " 'display
          `(space :align-to (- right ,(+ 1 width))))
        rendered))
    (funcall original-function task)))

(defun microvisor--prodigy-running-face-function (original-function tasks)
  (mapcar
    (lambda (task)
      (let* ((title       (car task))
              (plist       (cdr task))
              (plain-title (substring-no-properties title))
              (service     (and (plist-get plist :prodigy)
                             (prodigy-find-service plain-title))))
        (if (and service (prodigy-service-started-p service))
          (let ((title* (copy-sequence title)))
            (add-face-text-property 0 (length title*)
              'prodigy-green-face t title*)
            (cons title* plist))
          task)))
    (funcall original-function tasks)))

(defun microvisor--split-title (plain-title)
  "Split PLAIN-TITLE on the first colon into (GROUP . DISPLAY).
With no colon, both halves are PLAIN-TITLE."
  (if (string-match "\\`\\([^:]+\\):\\(.*\\)\\'" plain-title)
    (let ((group   (match-string 1 plain-title))
           (display (match-string 2 plain-title)))
      (cons (string-trim group) (string-trim display)))
    (cons plain-title plain-title)))

(defun microvisor--define-prodigy-service (task)
  (let* ((title        (car task))
          (plist        (cdr task))
          (port         (plist-get plist :port))
          (plain-title  (substring-no-properties title))
          (command      (or (get-text-property 0 'compile-multi--task title)
                          (plist-get plist :command)))
          (split        (microvisor--split-title plain-title))
          (group-label  (car split))
          (display-name (cdr split)))
    (apply #'prodigy-define-service
      (append
        (list :stop-signal                 'kill
          :name                        plain-title
          :display-name                display-name
          :group-label                 group-label
          :kill-process-buffer-on-stop 'unless-visible
          :command                     shell-file-name
          :cwd                         (projectile-project-root)
          :args                        (list shell-command-switch
                                         command))
        (when port (list :port port))))))

(defun microvisor-register-prodigy-services (&optional config)
  "Define a prodigy service for every `:prodigy' task in CONFIG.
CONFIG defaults to `compile-multi-dir-local-config'.
Tasks are expanded through compile-multi's fill / properties pipeline
so titles carry the same text properties prodigy expects."
  (let ((compile-multi-dir-local-config
          (or config compile-multi-dir-local-config)))
    (dolist (task (seq-filter
                    (lambda (task) (plist-get (cdr task) :prodigy))
                    (thread-first (compile-multi--config-tasks)
                      (compile-multi--fill-tasks)
                      (compile-multi--add-properties))))
      (microvisor--define-prodigy-service task))))

(defun microvisor--maybe-register-services ()
  (when (bound-and-true-p compile-multi-dir-local-config)
    (microvisor-register-prodigy-services)))

(unless (advice-member-p #'microvisor--annotation-function
          'compile-multi--annotation-function)
  (advice-add 'compile-multi--annotation-function
    :around #'microvisor--annotation-function))

(unless (advice-member-p #'microvisor--prodigy-running-face-function
          'compile-multi--add-properties)
  (advice-add 'compile-multi--add-properties
    :around #'microvisor--prodigy-running-face-function))

(add-hook 'compilation-filter-hook #'ansi-color-compilation-filter)
(add-hook 'hack-local-variables-hook #'microvisor--maybe-register-services)

(provide 'microvisor)

;;; microvisor.el ends here
