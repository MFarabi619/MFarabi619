;;; west.el --- West (Zephyr's meta-tool) integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/west
;; Keywords: tools, embedded
;; Package-Version: 0.0
;; Package-Revision: nil
;; Package-Requires: ((emacs "29.1") (projectile "2.8") (yaml "0.5"))

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
  (let ((eq-pos (string-search "=" line)))
    (cons (substring line 0 eq-pos) (substring line (1+ eq-pos)))))

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
  (if (string-match "\\`West version: \\(.+\\)\\'" line)
    (match-string 1 line)
    line))

(defun west-boards ()
  "Return `west boards' as a list of board names."
  (process-lines "west" "boards"))

(defun west--compile (label command)
  "Run COMMAND via `compile' in an isolated `*west:LABEL*' buffer."
  (let ((compilation-buffer-name-function
         (lambda (_mode) (format "*west:%s*" label))))
    (compile command)))

(defun west-update ()
  "Update projects described in west manifest."
  (interactive)
  (west--compile "update" "west update"))

(defun west-manifest-path (&optional workspace-root)
  "Return the absolute path of the manifest file for WORKSPACE-ROOT."
  (when-let ((root (or workspace-root (west-workspace-root))))
    (let* ((cfg (west-config))
           (path (or (cdr (assoc "manifest.path" cfg)) "."))
           (file (or (cdr (assoc "manifest.file" cfg)) "west.yml")))
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
    (if (stringp imports) (list imports) imports)))

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

(provide 'west)

;;; west.el ends here
