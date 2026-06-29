;;; loco-rs.el --- loco-rs (cargo loco) project integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/loco-rs
;; Keywords: tools, languages
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (compile-multi "0.7") (nerd-icons "0.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;;; Code:

(require 'compile-multi)
(require 'nerd-icons)
(require 'seq)

(defgroup loco-rs ()
  "Compile-multi integration for the loco-rs (`cargo loco') framework."
  :prefix "loco-rs-"
  :group 'tools)

(defcustom loco-rs-tasks
  '(("start"      "nf-dev-rails"               ("start") :prodigy t)
     ("db"         "nf-dev-database"            ("db"))
     ("db:status"  "nf-md-database_eye"         ("db" "status"))
     ("db:migrate" "nf-md-database_arrow_right" ("db" "migrate"))
     ("db:down"    "nf-md-database_arrow_left"  ("db" "down"))
     ("db:seed"    "nf-md-database_plus"        ("db" "seed"))
     ("routes"     "nf-md-routes"               ("routes"))
     ("jobs"       "nf-md-cogs"                 ("jobs"))
     ("doctor"     "nf-fa-heart_pulse"          ("doctor")))
  "Compile-multi task specs for `cargo loco', each `(DISPLAY ICON ARGS . PLIST)'.
DISPLAY is the row label, ICON a nerd-icons `nf-SET-NAME' glyph (any set), ARGS
the `cargo loco' subcommand.  Remaining PLIST keys (e.g. `:prodigy', `:port')
pass through to the generated compile-multi task."
  :type '(repeat (cons (string :tag "Display")
                   (cons (string :tag "Nerd-icon name")
                     (cons (repeat :tag "loco args" string)
                       (repeat :tag "Task plist" sexp))))))

(defconst loco-rs--nerd-icon-functions
  '(("nf-md-"      . nerd-icons-mdicon)
     ("nf-dev-"     . nerd-icons-devicon)
     ("nf-fa-"      . nerd-icons-faicon)
     ("nf-cod-"     . nerd-icons-codicon)
     ("nf-seti-"    . nerd-icons-sucicon)
     ("nf-oct-"     . nerd-icons-octicon)
     ("nf-weather-" . nerd-icons-wicon))
  "Map nerd-icons `nf-SET-' name prefixes to their renderer functions.")

(defun loco-rs--nerd-icon (name)
  "Render nerd-icon NAME via the renderer for its `nf-SET-' prefix."
  (let ((render (cdr (seq-find (lambda (pair) (string-prefix-p (car pair) name))
                       loco-rs--nerd-icon-functions))))
    (funcall (or render #'nerd-icons-mdicon) name)))

(defun loco-rs--command (args)
  "Return the `cargo loco' shell command string for ARGS."
  (string-join (append '("cargo" "loco") args) " "))

(defun loco-rs--annotation ()
  "The right-aligned `cargo' annotation (microvisor colors the rust icon)."
  (concat "cargo " (nerd-icons-devicon "nf-dev-rust")))

(defcustom loco-rs-default-port 5150
  "Fallback server port used when loco's config can't be read.
Not a loco default (loco requires `server.port'); purely a UI fallback."
  :type 'integer)

(defun loco-rs--repo-root (&optional directory)
  "Return the project root (dir with `.cargo/config.toml') above DIRECTORY."
  (locate-dominating-file (or directory default-directory) ".cargo/config.toml"))

(defun loco-rs--config-folder (root)
  "Resolve loco's config folder under ROOT, mirroring `LOCO_CONFIG_FOLDER'.
Reads `.cargo/config.toml' (honoring cargo's `relative = true'), else the
`LOCO_CONFIG_FOLDER' env var, else ROOT's `config/'."
  (let ((cargo (expand-file-name ".cargo/config.toml" root)))
    (or (and (file-exists-p cargo)
          (with-temp-buffer
            (insert-file-contents cargo)
            (goto-char (point-min))
            (when (re-search-forward
                    "^[[:space:]]*LOCO_CONFIG_FOLDER[[:space:]]*=[[:space:]]*\\(.*\\)$" nil t)
              (let ((rhs (match-string 1)))
                (when (string-match "\"\\([^\"]+\\)\"" rhs)
                  (let ((value (match-string 1 rhs)))
                    (if (string-match-p "relative[[:space:]]*=[[:space:]]*true" rhs)
                      (expand-file-name value root)
                      value)))))))
      (getenv "LOCO_CONFIG_FOLDER")
      (expand-file-name "config" root))))

(defun loco-rs--environment ()
  "Resolve loco's environment, mirroring loco's `resolve_from_env'."
  (or (getenv "LOCO_ENV") (getenv "RAILS_ENV") (getenv "NODE_ENV") "development"))

(defun loco-rs--config-file (folder environment)
  "Return ENVIRONMENT's config file in FOLDER (`.local.yaml' wins), or nil."
  (seq-find #'file-exists-p
    (list (expand-file-name (format "%s.local.yaml" environment) folder)
      (expand-file-name (format "%s.yaml" environment) folder))))

(defun loco-rs--coerce-port (value)
  "Coerce a raw YAML port VALUE to an integer, or nil if not derivable.
Handles an integer literal and the `get_env(name=VAR, default=N)' tera idiom."
  (cond
    ((string-match-p "\\`[0-9]+\\'" value) (string-to-number value))
    ((string-match
       "get_env(name=\"\\([^\"]+\\)\"[^)]*default[[:space:]]*=[[:space:]]*\\([0-9]+\\)"
       value)
      (string-to-number (or (getenv (match-string 1 value)) (match-string 2 value))))))

(defun loco-rs--parse-port (file)
  "Return the `server.port' integer from loco config FILE, or nil."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (when (and (re-search-forward "^server:" nil t)
            (re-search-forward "^[[:space:]]+port:[[:space:]]*\\(.+?\\)[[:space:]]*$" nil t))
      (loco-rs--coerce-port (match-string 1)))))

(defun loco-rs--server-port (&optional directory)
  "Resolve the loco server port from config near DIRECTORY.
Mirrors loco's own resolution (environment, config folder, `<env>.yaml',
`server.port'), falling back to `loco-rs-default-port'."
  (or (when-let* ((root (loco-rs--repo-root directory))
                   (file (loco-rs--config-file (loco-rs--config-folder root)
                           (loco-rs--environment))))
        (loco-rs--parse-port file))
    loco-rs-default-port))

(defun loco-rs--task (spec)
  "Build a `(TITLE . PLIST)' compile-multi entry from SPEC.
SPEC is `(DISPLAY ICON ARGS . PLIST)'; PLIST keys pass through to the task.
A `:prodigy' (server) task is stamped with loco's derived `server.port'.
The title is grouped under a train-glyphed `loco' header."
  (let* ((train (nerd-icons-wicon "nf-weather-train"))
          (extra (nthcdr 3 spec))
          (extra (if (plist-get extra :prodigy)
                   (plist-put (copy-sequence extra) :port (loco-rs--server-port))
                   extra)))
    (cons (format "%s loco %s :%s %s"
            train train
            (loco-rs--nerd-icon (nth 1 spec))
            (nth 0 spec))
      (append (list :command    (loco-rs--command (nth 2 spec))
                :annotation (loco-rs--annotation))
        extra))))

(defun loco-rs-compile-multi-tasks ()
  "Return the `cargo loco' compile-multi task entries from `loco-rs-tasks'."
  (mapcar #'loco-rs--task loco-rs-tasks))

(defun loco-rs-project-p (&optional directory)
  "Non-nil when DIRECTORY sits in a project wired for `cargo loco'.
Walks up from DIRECTORY for a `.cargo/config.toml' that defines a `loco' cargo
alias (the alias is what makes `cargo loco' runnable)."
  (when-let* ((root (loco-rs--repo-root directory)))
    (with-temp-buffer
      (insert-file-contents (expand-file-name ".cargo/config.toml" root))
      (goto-char (point-min))
      (and (re-search-forward "^[[:space:]]*loco[[:space:]]*=" nil t) t))))

(add-to-list 'compile-multi-config
  '((loco-rs-project-p) . (loco-rs-compile-multi-tasks)))

(provide 'loco-rs)

;;; loco-rs.el ends here
