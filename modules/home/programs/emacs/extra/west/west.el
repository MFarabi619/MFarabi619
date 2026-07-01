;;; west.el --- West (Zephyr's meta-tool) integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/west
;; Keywords: tools, embedded
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (projectile "2.8") (yaml "0.5") (compile-multi "0.7"))

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
;; Lightweight wrappers around the `west' CLI (Zephyr RTOS's meta-tool).
;; Generic workspace + manifest layer only; Zephyr-specific logic lives in
;; zephyr.el.
;;
;; Commands:
;;   west-update      update projects described in west manifest
;;
;;; Code:

(require 'map)
(require 'vc-git)
(require 'projectile)
(require 'yaml)
(require 'compile-multi)

(declare-function vterm "vterm")
(defvar vterm-shell)
(defvar vterm-buffer-name)

(defgroup west ()
  "West, the Zephyr RTOS project's meta-tool."
  :prefix "west-"
  :group 'lisp)

(defun west-vc-root (&optional directory)
  "Return the git VC root containing DIRECTORY (or `default-directory')."
  (vc-git-root (or directory default-directory)))

(defun west-vc-in-git-repo-p (&optional directory)
  "Non-nil if DIRECTORY (or `default-directory') is inside a git repo."
  (and (west-vc-root directory) t))

(defun west-projectile-root (&optional directory)
  "Return the Projectile root containing DIRECTORY (or `default-directory')."
  (let ((default-directory (or directory default-directory)))
    (projectile-project-root)))

(defun west-projectile-in-project-p (&optional directory)
  "Non-nil if DIRECTORY (or `default-directory') is inside a Projectile project."
  (and (west-projectile-root directory) t))

(defun west-workspace-root (&optional directory)
  "Walk up from DIRECTORY (or `default-directory') to find a `.west' workspace."
  (locate-dominating-file (or directory default-directory) ".west"))

(defun west-in-workspace-p (&optional directory)
  "Non-nil if DIRECTORY (or `default-directory') is inside a west workspace."
  (and (west-workspace-root directory) t))

(defun west-topdir ()
  "Return `west topdir' as a string."
  (car (process-lines "west" "topdir")))

(defun west-config ()
  "Return `west config -l' parsed as an alist of (KEY . VALUE) pairs."
  (mapcar #'west--parse-config-line
    (process-lines "west" "config" "-l")))

(defun west--parse-config-line (line)
  "Split LINE on the first `=' into a (KEY . VALUE) cons."
  (let ((separator-index (string-search "=" line)))
    (cons (substring line 0 separator-index) (substring line (1+ separator-index)))))

(defun west-list ()
  "Return `west list' as a list of per-project plists."
  (mapcar #'west--parse-list-line
    (process-lines "west" "list" "-f" "{name}\t{path}\t{revision}\t{url}")))

(defun west--parse-list-line (line)
  "Parse a tab-separated `west list' LINE into a plist."
  (let ((fields (split-string line "\t")))
    (list :name     (nth 0 fields)
      :path     (nth 1 fields)
      :revision (nth 2 fields)
      :url      (nth 3 fields))))

(defun west-version ()
  "Return the installed west CLI version string."
  (west--parse-version (car (process-lines "west" "--version"))))

(defun west--parse-version (line)
  "Strip the `West version: ' prefix from LINE."
  (string-remove-prefix "West version: " line))

(defun west-boards ()
  "Return `west boards' as a list of board names."
  (process-lines "west" "boards"))

(defun west--run-interactive (label command)
  "Run COMMAND in a fresh vterm buffer `*west:LABEL*' for interactive targets."
  (require 'vterm)
  (let* ((buffer-name (format "*west:%s*" label))
          (existing    (get-buffer buffer-name)))
    (when existing
      (let (kill-buffer-query-functions) (kill-buffer existing)))
    (let ((vterm-shell command)
           (vterm-buffer-name buffer-name))
      (vterm))))

(defun west-update ()
  "Update projects described in west manifest."
  (interactive)
  (compile "west update"))

(defcustom west-update-show-in-m-x nil
  "When non-nil, offer `west-update' in \\[execute-extended-command]."
  :type 'boolean
  :group 'west)

(put 'west-update 'completion-predicate
  (lambda (_symbol _buffer) west-update-show-in-m-x))

(defun west-patches-path (&optional app-path)
  "Return APP-PATH's `zephyr/patches.yml' (defaults to the current app), or nil."
  (when-let* ((app-path (or app-path (west--current-app))))
    (let ((yml (expand-file-name "zephyr/patches.yml" app-path)))
      (when (file-exists-p yml) yml))))

(defun west--current-app ()
  "Return the manifest app directory containing `default-directory', or nil."
  (seq-some (lambda (app)
              (let ((path (plist-get app :path)))
                (and path (file-in-directory-p default-directory path) path)))
    (west-manifest-apps)))

(defun west--resolve-patch-app (&optional app-path)
  "Resolve a manifest app with a `zephyr/patches.yml': APP-PATH, current, sole, or prompt."
  (or app-path
    (let ((current (west--current-app)))
      (and current (west-patches-path current) current))
    (let ((apps (seq-filter (lambda (app) (west-patches-path (plist-get app :path)))
                  (west-manifest-apps))))
      (cond
        ((null apps) nil)
        ((= 1 (length apps)) (plist-get (car apps) :path))
        (t (let* ((by-name (mapcar (lambda (app)
                                     (cons (plist-get app :name) (plist-get app :path)))
                             apps))
                   (choice (completing-read "App: " (mapcar #'car by-name) nil t)))
             (cdr (assoc choice by-name))))))))

(defun west--patch-run (subcommands app-path)
  "Run `west patch SUBCOMMANDS' for APP-PATH's module."
  (let* ((app-path  (west--resolve-patch-app app-path))
          (workspace (and app-path (west-workspace-root app-path))))
    (unless (and app-path (west-patches-path app-path))
      (user-error "No zephyr/patches.yml found for %s" (or app-path "current app")))
    (unless workspace
      (user-error "No west workspace found for %s" app-path))
    (let* ((default-directory (expand-file-name workspace))
            (module (shell-quote-argument
                      (directory-file-name (file-relative-name app-path workspace))))
            (subs (ensure-list subcommands)))
      (compile
        (mapconcat
          (lambda (sub) (format "west patch -sm %s %s" module sub))
          subs " && ")))))

(defcustom west-patch-apply-clean-first t
  "When non-nil, `west-patch-apply' resets patches (clean) before applying."
  :type 'boolean
  :group 'west)

(defun west-patch-apply (&optional app-path)
  "Apply APP-PATH's patches; clean first when `west-patch-apply-clean-first'."
  (interactive)
  (west--patch-run
    (if west-patch-apply-clean-first '("clean" "apply") "apply")
    app-path))

(defun west-patch-clean (&optional app-path)
  "Reset patches declared in APP-PATH's `zephyr/patches.yml'."
  (interactive)
  (west--patch-run "clean" app-path))

(defun west-patch-clean-apply (&optional app-path)
  "Clean then apply patches declared in APP-PATH's `zephyr/patches.yml'."
  (interactive)
  (west--patch-run '("clean" "apply") app-path))

(defun west-manifest-path (&optional workspace-root)
  "Return the absolute path of the manifest file for WORKSPACE-ROOT."
  (when-let ((root (or workspace-root (west-workspace-root))))
    (let* ((config (west-config))
           (path (or (cdr (assoc "manifest.path" config)) "."))
           (file (or (cdr (assoc "manifest.file" config)) "west.yml")))
      (expand-file-name file (expand-file-name path root)))))

(defun west-manifest (&optional path)
  "Parse the west manifest at PATH (default: the workspace's) into a hash table."
  (require 'yaml)
  (let ((file (or path (west-manifest-path))))
    (when (and file (file-exists-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (yaml-parse-string (buffer-string)
          :object-type 'hash-table
          :sequence-type 'list)))))

(defun west-manifest-self-imports (manifest)
  "Return the `manifest.self.import' list from MANIFEST (string -> 1-list)."
  (when-let ((imports (and manifest
                           (map-nested-elt manifest '(manifest self import)))))
    (ensure-list imports)))

(defun west-manifest-projects (manifest)
  "Return MANIFEST's `manifest.projects' as a list of per-project plists."
  (when-let ((projects (and manifest
                            (map-nested-elt manifest '(manifest projects)))))
    (mapcar #'west--parse-manifest-project projects)))

(defun west--parse-manifest-project (entry)
  "Convert one manifest-project hash ENTRY into a plist."
  (list :name     (gethash 'name entry)
    :path     (gethash 'path entry)
    :revision (gethash 'revision entry)
    :remote   (gethash 'remote entry)
    :url      (gethash 'url entry)
    :groups   (gethash 'groups entry)))

(defun west-manifest-apps (&optional workspace-root)
  "Return apps discovered via `manifest.self.import' in WORKSPACE-ROOT.
Each entry is a plist with :name, :path (directory), and :manifest (file)."
  (when-let* ((root (or workspace-root (west-workspace-root)))
              (manifest-file (west-manifest-path root))
              (manifest-repo (file-name-directory manifest-file))
              (imports (west-manifest-self-imports (west-manifest manifest-file))))
    (mapcar (lambda (import-path)
              (let* ((app-manifest-path (expand-file-name import-path manifest-repo))
                     (app-dir (file-name-directory app-manifest-path)))
                (list :name (file-name-nondirectory
                             (directory-file-name app-dir))
                      :path app-dir
                      :manifest app-manifest-path)))
            imports)))

(defconst west--compile-multi-group "\U000f1985"
  "Kite glyph flanking the west compile-multi group header.")

(defconst west--task-annotation (concat "west " west--compile-multi-group)
  "Right-column annotation (label plus kite glyph) for west compile-multi tasks.")

(defun west-compile-multi-tasks ()
  "Workspace-level west compile-multi tasks (update, patch apply/clean)."
  (when (west-in-workspace-p)
    (list
      (cons (format "%s west %s :\U0000e726 update"
              west--compile-multi-group west--compile-multi-group)
        (list :command "west update" :annotation west--task-annotation))
      (cons (format "%s west %s :\U0000e729 patch apply"
              west--compile-multi-group west--compile-multi-group)
        (list :command #'west-patch-apply :annotation west--task-annotation)))))

(add-to-list 'compile-multi-config
  '((west-in-workspace-p) . (west-compile-multi-tasks)))

(provide 'west)

;;; west.el ends here
