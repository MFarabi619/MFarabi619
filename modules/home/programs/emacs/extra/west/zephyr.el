;;; zephyr.el --- Zephyr RTOS workspace integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; Keywords: lisp, tools

;; This file is not part of GNU Emacs.

;;; Code:

(require 'west)
(require 'xdg)
(require 'yaml)
(require 'treesit)

(defgroup zephyr ()
  "Zephyr RTOS workspace integration."
  :prefix "zephyr-"
  :group 'lisp)

(defcustom zephyr-cache-dir
  (expand-file-name "zephyr/" (xdg-cache-home))
  "Directory for zephyr.el's on-disk caches."
  :type 'directory
  :group 'zephyr)

(defun zephyr--cache-file (name)
  (expand-file-name (concat name ".eld") zephyr-cache-dir))

(defun zephyr--cache-load (name)
  (let ((f (zephyr--cache-file name)))
    (when (file-exists-p f)
      (with-temp-buffer
        (insert-file-contents f)
        (read (current-buffer))))))

(defun zephyr--cache-save (name data)
  (make-directory zephyr-cache-dir t)
  (with-temp-file (zephyr--cache-file name)
    (prin1 data (current-buffer))))

(defun zephyr-base (&optional workspace-root)
  (or (getenv "ZEPHYR_BASE")
      (when-let ((root (or workspace-root (west-workspace-root))))
        (expand-file-name "zephyrproject/zephyr/" root))))

(defun zephyr-version (&optional base)
  (when-let* ((b (or base (zephyr-base)))
              (vfile (expand-file-name "VERSION" b)))
    (when (file-exists-p vfile)
      (with-temp-buffer
        (insert-file-contents vfile)
        (string-trim (buffer-string))))))

(defcustom zephyr-sdk-search-paths
  `("~/zephyr-sdk-*"
    "/opt/zephyr-sdk-*"
    ,(expand-file-name "zephyr-sdk-*" (xdg-data-home)))
  "Glob patterns to search for Zephyr SDK installations.
The XDG_DATA_HOME entry honors the user's XDG environment at file load time."
  :type '(repeat string)
  :group 'zephyr)

(defun zephyr-sdk-path ()
  (or (getenv "ZEPHYR_SDK_INSTALL_DIR")
      (car (zephyr--sdk-discover))))

(defun zephyr--sdk-discover ()
  (sort (seq-filter
         (lambda (dir) (file-exists-p (expand-file-name "sdk_version" dir)))
         (mapcan (lambda (pattern)
                   (file-expand-wildcards (expand-file-name pattern)))
                 zephyr-sdk-search-paths))
        (lambda (a b)
          (version< (zephyr--sdk-version-from-path b)
                    (zephyr--sdk-version-from-path a)))))

(defun zephyr--sdk-version-from-path (path)
  (if (string-match "zephyr-sdk-\\(.+?\\)/?\\'" path)
      (match-string 1 path)
    path))

(defun zephyr-sdk-version (&optional sdk-path)
  (let* ((path (or sdk-path (zephyr-sdk-path)))
         (version-file (and path (expand-file-name "sdk_version" path))))
    (when (and version-file (file-exists-p version-file))
      (with-temp-buffer
        (insert-file-contents version-file)
        (string-trim (buffer-string))))))

(defun zephyr-sdk-toolchains (&optional sdk-path)
  (let ((path (or sdk-path (zephyr-sdk-path))))
    (when (and path (file-directory-p path))
      (seq-filter (lambda (name)
                    (string-match-p "zephyr-\\(elf\\|eabi\\)\\'" name))
                  (directory-files path)))))

(defun zephyr-toolchain-variant ()
  (or (getenv "ZEPHYR_TOOLCHAIN_VARIANT") "zephyr"))

(defun zephyr-board ()
  (or (getenv "BOARD")
      (cdr (assoc "build.board" (west-config)))))

(defun zephyr-shield ()
  (when-let ((v (getenv "SHIELD")))
    (split-string v ";" t " ")))

(defun zephyr-snippet ()
  (when-let ((v (getenv "SNIPPET")))
    (split-string v ";" t " ")))

(defun zephyr--env-list (var)
  (when-let ((v (getenv var)))
    (split-string v path-separator t " ")))

(defun zephyr-board-roots       () (zephyr--env-list "BOARD_ROOT"))
(defun zephyr-shield-roots      () (zephyr--env-list "SHIELD_ROOT"))
(defun zephyr-snippet-roots     () (zephyr--env-list "SNIPPET_ROOT"))
(defun zephyr-soc-roots         () (zephyr--env-list "SOC_ROOT"))
(defun zephyr-arch-roots        () (zephyr--env-list "ARCH_ROOT"))
(defun zephyr-dts-roots         () (zephyr--env-list "DTS_ROOT"))
(defun zephyr-module-ext-roots  () (zephyr--env-list "MODULE_EXT_ROOT"))

(defun zephyr-modules ()
  (zephyr--env-list "ZEPHYR_MODULES"))

(defun zephyr-extra-modules ()
  (zephyr--env-list "EXTRA_ZEPHYR_MODULES"))

(defun zephyr--cmake-arg (key value)
  (when value
    (format "-D%s=%s" key
            (if (listp value) (string-join value ";") value))))

(defconst zephyr--cmake-arg-spec
  '((:board             "BOARD"                     zephyr-board)
    (:shield            "SHIELD"                    zephyr-shield)
    (:snippet           "SNIPPET"                   zephyr-snippet)
    (:toolchain-variant "ZEPHYR_TOOLCHAIN_VARIANT"  zephyr-toolchain-variant)
    (:sdk-path          "ZEPHYR_SDK_INSTALL_DIR"    zephyr-sdk-path)
    (:board-roots       "BOARD_ROOT"                zephyr-board-roots)
    (:shield-roots      "SHIELD_ROOT"               zephyr-shield-roots)
    (:snippet-roots     "SNIPPET_ROOT"              zephyr-snippet-roots)
    (:soc-roots         "SOC_ROOT"                  zephyr-soc-roots)
    (:arch-roots        "ARCH_ROOT"                 zephyr-arch-roots)
    (:dts-roots         "DTS_ROOT"                  zephyr-dts-roots)
    (:modules           "ZEPHYR_MODULES"            zephyr-modules)
    (:extra-modules     "EXTRA_ZEPHYR_MODULES"      zephyr-extra-modules)))

(defun zephyr-cmake-args (&optional overrides)
  (delq nil
        (mapcar (pcase-lambda (`(,key ,name ,getter))
                  (zephyr--cmake-arg name
                                     (or (plist-get overrides key)
                                         (funcall getter))))
                zephyr--cmake-arg-spec)))

(defun zephyr-apps (&optional workspace-root)
  (seq-keep (lambda (app)
              (let ((path (plist-get app :path)))
                (when (west-app-p path)
                  (list :name     (or (west-app-name path)
                                      (plist-get app :name))
                        :path     path
                        :manifest (plist-get app :manifest)
                        :boards   (west-app-boards path)))))
            (west-manifest-apps workspace-root)))

(defvar zephyr--boards-cache nil)

(defun zephyr-boards (&optional base)
  (cond
   (base
    (zephyr--boards-uncached base))
   (zephyr--boards-cache
    zephyr--boards-cache)
   (t
    (let* ((disk (zephyr--cache-load "boards"))
           (current-version (zephyr-version)))
      (setq zephyr--boards-cache
            (if (and disk (equal (plist-get disk :version) current-version))
                (plist-get disk :data)
              (let ((data (zephyr--boards-uncached)))
                (zephyr--cache-save "boards"
                                    (list :version current-version :data data))
                data)))))))

(defun zephyr-boards-invalidate ()
  (interactive)
  (setq zephyr--boards-cache nil)
  (let ((f (zephyr--cache-file "boards")))
    (when (file-exists-p f) (delete-file f))))

(defun zephyr--boards-uncached (&optional base)
  (when-let* ((b (or base (zephyr-base)))
              (boards-dir (expand-file-name "boards" b)))
    (when (file-directory-p boards-dir)
      (seq-keep #'zephyr--parse-board-file
                (directory-files-recursively boards-dir "\\.yaml\\'")))))

(defun zephyr--parse-board-file (path)
  (when (file-exists-p path)
    (let ((parsed (with-temp-buffer
                    (insert-file-contents path)
                    (yaml-parse-string (buffer-string)
                                       :object-type 'hash-table
                                       :sequence-type 'list))))
      (when (and (hash-table-p parsed)
                 (gethash 'identifier parsed))
        (list :id        (gethash 'identifier parsed)
              :name      (gethash 'name parsed)
              :arch      (gethash 'arch parsed)
              :type      (gethash 'type parsed)
              :vendor    (gethash 'vendor parsed)
              :toolchain (gethash 'toolchain parsed)
              :supported (gethash 'supported parsed)
              :path      path)))))

(provide 'zephyr)

;;; zephyr.el ends here
