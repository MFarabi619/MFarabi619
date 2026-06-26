;;; west.el --- West (Zephyr's meta-tool) support for GNU EMACS  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; Keywords: lisp, tools

;; This file is not part of GNU Emacs.

;;; Code:

(require 'vc-git)
(require 'projectile)

(defgroup west ()
  "West, the Zephyr RTOS project's meta-tool."
  :prefix "west-"
  :group 'lisp)

(defun west-vc-root (&optional directory)
  (vc-git-root (or directory default-directory)))

(defun west-vc-in-git-repo-p (&optional directory)
  (and (west-vc-root directory) t))

(defun west-projectile-root (&optional directory)
  (let ((default-directory (or directory default-directory)))
    (projectile-project-root)))

(defun west-projectile-in-project-p (&optional directory)
  (and (west-projectile-root directory) t))

(defun west-workspace-root (&optional directory)
  (locate-dominating-file (or directory default-directory) ".west"))

(defun west-in-workspace-p (&optional directory)
  (and (west-workspace-root directory) t))

(defun west-app-p (&optional directory)
  (let ((cmake-file (expand-file-name "CMakeLists.txt"
                      (or directory default-directory))))
    (when (file-exists-p cmake-file)
      (let ((content (with-temp-buffer
                       (insert-file-contents cmake-file)
                       (buffer-string)))
             (case-fold-search t))
        (and (string-match-p "find_package(\\s-*Zephyr\\b" content)
          (string-match-p "project(\\s-*\\w" content))))))

(defun west-app-root (&optional directory)
  (locate-dominating-file (or directory default-directory) #'west-app-p))

(defun west-app-name (app-path)
  (require 'treesit)
  (let ((cmake-file (expand-file-name "CMakeLists.txt" app-path)))
    (when (and (file-exists-p cmake-file)
            (treesit-language-available-p 'cmake))
      (with-temp-buffer
        (insert-file-contents cmake-file)
        (treesit-parser-create 'cmake)
        (when-let* ((query (treesit-query-compile 'cmake
                             '(((normal_command
                                  (identifier) @cmd
                                  (argument_list (argument) @arg))
                                 (:match "^[Pp][Rr][Oo][Jj][Ee][Cc][Tt]$" @cmd)))))
                     (captures (treesit-query-capture
                                 (treesit-buffer-root-node 'cmake) query))
                     (arg-node (alist-get 'arg captures)))
          (treesit-node-text arg-node))))))

(defun west-topdir ()
  (car (process-lines "west" "topdir")))

(defun west-config ()
  (mapcar #'west--parse-config-line
    (process-lines "west" "config" "-l")))

(defun west--parse-config-line (line)
  (let ((i (string-search "=" line)))
    (cons (substring line 0 i) (substring line (1+ i)))))

(defun west-list ()
  (mapcar #'west--parse-list-line
    (process-lines "west" "list" "-f" "{name}\t{path}\t{revision}\t{url}")))

(defun west--parse-list-line (line)
  (let ((fields (split-string line "\t")))
    (list :name     (nth 0 fields)
      :path     (nth 1 fields)
      :revision (nth 2 fields)
      :url      (nth 3 fields))))

(defun west-version ()
  (west--parse-version (car (process-lines "west" "--version"))))

(defun west--parse-version (line)
  (if (string-match "\\`West version: \\(.+\\)\\'" line)
    (match-string 1 line)
    line))

(defun west-boards ()
  (process-lines "west" "boards"))

(defun west-manifest-path (&optional workspace-root)
  (when-let ((root (or workspace-root (west-workspace-root))))
    (expand-file-name "manifest.yml" root)))

(defun west-manifest (&optional path)
  (require 'yaml)
  (let ((file (or path (west-manifest-path))))
    (when (and file (file-exists-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (yaml-parse-string (buffer-string)
          :object-type 'hash-table
          :sequence-type 'list)))))

(defun west-manifest-self-imports (manifest)
  (when-let* ((m manifest)
               (inner (gethash 'manifest m))
               (self (gethash 'self inner))
               (imports (gethash 'import self)))
    (cond ((stringp imports) (list imports))
      ((listp imports)   imports)
      (t                 nil))))

(defun west-manifest-projects (manifest)
  (when-let* ((m manifest)
               (inner (gethash 'manifest m))
               (projects (gethash 'projects inner)))
    (mapcar #'west--parse-manifest-project projects)))

(defun west--parse-manifest-project (entry)
  (list :name     (gethash 'name entry)
    :path     (gethash 'path entry)
    :revision (gethash 'revision entry)
    :remote   (gethash 'remote entry)
    :url      (gethash 'url entry)
    :groups   (gethash 'groups entry)))

(defun west-app-boards (app-path)
  (let ((boards-dir (expand-file-name "boards" app-path)))
    (when (file-directory-p boards-dir)
      (seq-uniq
        (mapcar #'file-name-base
          (directory-files boards-dir nil "\\.\\(conf\\|overlay\\)\\'"))))))

(defun west-manifest-apps (&optional workspace-root)
  (when-let* ((root (or workspace-root (west-workspace-root)))
               (manifest-file (west-manifest-path root))
               (imports (west-manifest-self-imports (west-manifest manifest-file))))
    (mapcar (lambda (import-path)
              (let* ((abs-manifest (expand-file-name import-path root))
                      (app-dir (file-name-directory abs-manifest)))
                (list :name (file-name-nondirectory
                              (directory-file-name app-dir))
                  :path app-dir
                  :manifest abs-manifest)))
      imports)))

(provide 'west)

;;; west.el ends here
