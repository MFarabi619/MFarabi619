;;; dioxus.el --- Dioxus (dx) project integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/dioxus
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

(defgroup dioxus ()
  "Compile-multi integration for the Dioxus CLI (`dx')."
  :prefix "dioxus-"
  :group 'tools)

(defcustom dioxus-tasks
  '(("serve"         "nf-md-cursor_default_click" ("serve")                        :server t)
     ("serve:desktop" "nf-md-desktop_classic"      ("serve" "--platform" "desktop") :server t)
     ("serve:ssg"     "nf-fa-scroll"               ("serve" "-r" "--ssg")           :server t)
     ("build"         "nf-md-crane"                ("build")))
  "Compile-multi task specs for `dx', each `(DISPLAY ICON ARGS . PLIST)'.
DISPLAY is the row label, ICON a nerd-icons `nf-SET-NAME' glyph (any set), ARGS
the `dx' subcommand and flags (the `-p PKG' flag is appended automatically).
A `:server' key marks a long-running dev server: it becomes a prodigy service
on `dioxus-serve-port'."
  :type '(repeat (cons (string :tag "Display")
                   (cons (string :tag "Nerd-icon name")
                     (cons (repeat :tag "dx args" string)
                       (repeat :tag "Task plist" sexp))))))

(defcustom dioxus-serve-port 8080
  "Port the `dx serve' dev server listens on (its built-in default)."
  :type 'integer)

(defconst dioxus--nerd-icon-functions
  '(("nf-md-"      . nerd-icons-mdicon)
     ("nf-dev-"     . nerd-icons-devicon)
     ("nf-fa-"      . nerd-icons-faicon)
     ("nf-cod-"     . nerd-icons-codicon)
     ("nf-seti-"    . nerd-icons-sucicon)
     ("nf-oct-"     . nerd-icons-octicon)
     ("nf-weather-" . nerd-icons-wicon))
  "Map nerd-icons `nf-SET-' name prefixes to their renderer functions.")

(defun dioxus--nerd-icon (name)
  "Render nerd-icon NAME via the renderer for its `nf-SET-' prefix."
  (let ((render (cdr (seq-find (lambda (pair) (string-prefix-p (car pair) name))
                       dioxus--nerd-icon-functions))))
    (funcall (or render #'nerd-icons-mdicon) name)))

(defun dioxus--command (args package)
  "Return the `dx' shell command string for ARGS targeting PACKAGE."
  (string-join (append '("dx") args (list "-p" package)) " "))

(defun dioxus--annotation ()
  "The right-aligned `dioxus' annotation (microvisor colors the icon)."
  (concat "dioxus " (nerd-icons-faicon "nf-fa-dna")))

(defun dioxus--workspace-root (&optional directory)
  "Return the workspace root at or above DIRECTORY (a `.git/' or Cargo dir)."
  (let ((start (or directory default-directory)))
    (or (locate-dominating-file start ".git")
      (locate-dominating-file start "Cargo.toml"))))

(defun dioxus--toml (&optional directory)
  "Return the path to the workspace's `Dioxus.toml', or nil.
Globs conventional app locations under the workspace root, since the manifest
typically sits in a member crate rather than the root."
  (when-let* ((root (dioxus--workspace-root directory)))
    (car (seq-mapcat
           (lambda (pattern) (file-expand-wildcards (expand-file-name pattern root)))
           '("Dioxus.toml" "*/Dioxus.toml" "apps/*/Dioxus.toml" "crates/*/Dioxus.toml")))))

(defun dioxus--package (&optional directory)
  "Return the Dioxus app's Cargo package name near DIRECTORY, or nil.
Reads the `name' field of the `Cargo.toml' beside the discovered `Dioxus.toml'."
  (when-let* ((toml (dioxus--toml directory))
               (cargo (expand-file-name "Cargo.toml" (file-name-directory toml)))
               ((file-exists-p cargo)))
    (with-temp-buffer
      (insert-file-contents cargo)
      (goto-char (point-min))
      (when (re-search-forward
              "^[[:space:]]*name[[:space:]]*=[[:space:]]*\"\\([^\"]+\\)\"" nil t)
        (match-string 1)))))

(defun dioxus-project-p (&optional directory)
  "Non-nil when DIRECTORY sits in a workspace containing a Dioxus app."
  (and (dioxus--toml directory) t))

(defun dioxus--task (spec package)
  "Build a `(TITLE . PLIST)' compile-multi entry from SPEC for PACKAGE.
SPEC is `(DISPLAY ICON ARGS . PLIST)'; a `:server' key becomes a prodigy
service on `dioxus-serve-port'.  The title is grouped under a dioxus-glyphed
PACKAGE header."
  (let* ((glyph (nerd-icons-mdicon "nf-md-monitor_cellphone"))
          (server (plist-get (nthcdr 3 spec) :server)))
    (cons (format "%s %s %s :%s %s"
            glyph package glyph
            (dioxus--nerd-icon (nth 1 spec))
            (nth 0 spec))
      (append (list :command    (dioxus--command (nth 2 spec) package)
                :annotation (dioxus--annotation))
        (when server (list :prodigy t :port dioxus-serve-port))))))

(defun dioxus-compile-multi-tasks ()
  "Return the `dx' compile-multi task entries from `dioxus-tasks'."
  (when-let* ((root (dioxus--workspace-root))
               (package (dioxus--package root)))
    (mapcar (lambda (spec) (dioxus--task spec package)) dioxus-tasks)))

(add-to-list 'compile-multi-config
  '((dioxus-project-p) . (dioxus-compile-multi-tasks)))

(provide 'dioxus)

;;; dioxus.el ends here
