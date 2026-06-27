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

(defun zephyr-app-p (&optional directory)
  (let ((cmake-file (expand-file-name "CMakeLists.txt"
                      (or directory default-directory))))
    (when (file-exists-p cmake-file)
      (let ((content (with-temp-buffer
                       (insert-file-contents cmake-file)
                       (buffer-string)))
             (case-fold-search t))
        (and (string-match-p "find_package(\\s-*Zephyr\\b" content)
          (string-match-p "project(\\s-*\\w" content))))))

(defun zephyr-app-root (&optional directory)
  (locate-dominating-file (or directory default-directory) #'zephyr-app-p))

(defun zephyr-app-name (app-path)
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

(defun zephyr-app-boards (app-path)
  (let ((boards-dir (expand-file-name "boards" app-path)))
    (when (file-directory-p boards-dir)
      (seq-uniq
        (mapcar #'file-name-base
          (directory-files boards-dir nil "\\.\\(conf\\|overlay\\)\\'"))))))

(defun zephyr--cache-file (name)
  (expand-file-name (concat name ".eld") zephyr-cache-dir))

(defun zephyr--cache-load (name)
  (let ((cache-file (zephyr--cache-file name)))
    (when (file-exists-p cache-file)
      (with-temp-buffer
        (insert-file-contents cache-file)
        (read (current-buffer))))))

(defun zephyr--cache-save (name data)
  (make-directory zephyr-cache-dir t)
  (with-temp-file (zephyr--cache-file name)
    (prin1 data (current-buffer))))

(defun zephyr-base (&optional workspace-root)
  (let* ((cfg (west-config))
         (env (getenv "ZEPHYR_BASE"))
         (cfg-value (cdr (assoc "zephyr.base" cfg)))
         (cfg-resolved (when cfg-value
                         (if (file-name-absolute-p cfg-value)
                             cfg-value
                           (when-let ((root (or workspace-root (west-workspace-root))))
                             (expand-file-name cfg-value root)))))
         (prefer (or (cdr (assoc "zephyr.base-prefer" cfg)) "env"))
         (result (if (equal prefer "configfile")
                     (or cfg-resolved env)
                   (or env cfg-resolved))))
    (when result
      (file-name-as-directory result))))

(defun zephyr-version (&optional base)
  (when-let* ((effective-base (or base (zephyr-base)))
              (version-file (expand-file-name "VERSION" effective-base)))
    (when (file-exists-p version-file)
      (with-temp-buffer
        (insert-file-contents version-file)
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
      (directory-files path nil "zephyr-\\(elf\\|eabi\\)\\'"))))

(defun zephyr-toolchain-variant ()
  (or (getenv "ZEPHYR_TOOLCHAIN_VARIANT") "zephyr"))

(defun zephyr-board ()
  (or (getenv "BOARD")
      (cdr (assoc "build.board" (west-config)))))

(defun zephyr-shield ()
  (when-let ((value (getenv "SHIELD")))
    (split-string value ";" t " ")))

(defun zephyr-snippet ()
  (when-let ((value (getenv "SNIPPET")))
    (split-string value ";" t " ")))

(defun zephyr--env-list (var)
  (when-let ((value (getenv var)))
    (split-string value path-separator t " ")))

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
  (seq-keep (pcase-lambda (`(,key ,name ,getter))
              (zephyr--cmake-arg name
                                 (or (plist-get overrides key)
                                     (funcall getter))))
            zephyr--cmake-arg-spec))

(defun zephyr-build-dir (&optional workspace-root)
  (when-let ((root (or workspace-root (west-workspace-root))))
    (expand-file-name "build" root)))

(defun zephyr-build-command (app &optional overrides)
  (let* ((build-dir (or (plist-get overrides :build-dir) (zephyr-build-dir)))
         (sysbuild  (plist-get overrides :sysbuild))
         (source-dir (if sysbuild
                         (expand-file-name "share/sysbuild" (zephyr-base))
                       (directory-file-name app)))
         (extra-args (when sysbuild
                       (list (format "-DAPP_DIR=%s" (directory-file-name app))))))
    (concat
     (mapconcat #'shell-quote-argument
                `("cmake" "-B" ,build-dir "-GNinja"
                  ,@extra-args
                  ,@(zephyr-cmake-args overrides)
                  ,source-dir)
                " ")
     " && "
     (mapconcat #'shell-quote-argument
                `("ninja" "-C" ,build-dir)
                " "))))

(defun zephyr-build (app &optional overrides)
  (interactive
   (list (read-directory-name "Zephyr app: "
                              (or (zephyr-app-root) default-directory)
                              nil t)))
  (let* ((base (zephyr-base))
         (process-environment
          (if base
              (cons (format "ZEPHYR_BASE=%s" (directory-file-name base))
                    process-environment)
            process-environment)))
    (compile (zephyr-build-command app overrides))))

(defun zephyr-apps (&optional workspace-root)
  (or
   (seq-keep (lambda (manifest-app)
               (let ((path (plist-get manifest-app :path)))
                 (when (zephyr-app-p path)
                   (zephyr--make-app-plist path (plist-get manifest-app :manifest)))))
             (west-manifest-apps workspace-root))
   (when-let* ((root (or workspace-root (west-workspace-root)))
               (app-dir (file-name-as-directory (expand-file-name "app" root))))
     (when (zephyr-app-p app-dir)
       (list (zephyr--make-app-plist app-dir nil))))))

(defun zephyr--make-app-plist (path manifest-path)
  (list :name     (or (zephyr-app-name path)
                      (file-name-nondirectory (directory-file-name path)))
        :path     path
        :manifest manifest-path
        :boards   (zephyr-app-boards path)))

(defvar zephyr--boards-cache nil)

(defun zephyr-boards (&optional base)
  (cond
   (base
    (zephyr--boards-uncached base))
   (zephyr--boards-cache
    zephyr--boards-cache)
   (t
    (let* ((disk-cache (zephyr--cache-load "boards"))
           (current-version (zephyr-version)))
      (setq zephyr--boards-cache
            (if (and disk-cache (equal (plist-get disk-cache :version) current-version))
                (plist-get disk-cache :data)
              (let ((data (zephyr--boards-uncached)))
                (zephyr--cache-save "boards"
                                    (list :version current-version :data data))
                data)))))))

(defun zephyr-boards-invalidate ()
  (interactive)
  (setq zephyr--boards-cache nil)
  (let ((cache-file (zephyr--cache-file "boards")))
    (when (file-exists-p cache-file) (delete-file cache-file))))

(defun zephyr-module-board-roots (&optional workspace-root)
  (when-let* ((root (or workspace-root (west-workspace-root)))
              (module-file (expand-file-name "zephyr/module.yml" root))
              ((file-exists-p module-file))
              (parsed (with-temp-buffer
                        (insert-file-contents module-file)
                        (yaml-parse-string (buffer-string)
                                           :object-type 'hash-table
                                           :sequence-type 'list)))
              (board-root (map-nested-elt parsed '(build settings board_root))))
    (mapcar (lambda (relative) (expand-file-name relative root))
            (if (listp board-root) board-root (list board-root)))))

(defun zephyr--boards-uncached (&optional base)
  (let* ((effective-base (or base (zephyr-base)))
         (base-boards (when effective-base
                        (expand-file-name "boards" effective-base)))
         (app-boards (mapcar (lambda (app)
                               (expand-file-name "boards" (plist-get app :path)))
                             (zephyr-apps)))
         (module-boards (mapcar (lambda (module-root)
                                  (expand-file-name "boards" module-root))
                                (zephyr-module-board-roots)))
         (all-dirs (seq-filter #'file-directory-p
                               (cons base-boards
                                     (append app-boards module-boards)))))
    (when all-dirs
      (seq-keep #'zephyr--parse-board-file
                (mapcan (lambda (dir)
                          (directory-files-recursively dir "\\.yaml\\'"))
                        all-dirs)))))

(defun zephyr-board-id-from-hint (hint)
  (plist-get
   (seq-find (lambda (board)
               (equal hint (replace-regexp-in-string "/" "_" (plist-get board :id))))
             (zephyr-boards))
   :id))

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

(defun zephyr-patches-yml (&optional app-path)
  (when-let* ((root (or app-path (zephyr-app-root))))
    (let ((yml (expand-file-name "zephyr/patches.yml" root)))
      (when (file-exists-p yml) yml))))

(defun zephyr--resolve-app (&optional app-path filter)
  (or app-path
      (let ((current (zephyr-app-root)))
        (when (and current (or (null filter) (funcall filter current)))
          current))
      (let* ((all  (zephyr-apps))
             (apps (if filter
                       (seq-filter (lambda (a) (funcall filter (plist-get a :path)))
                                   all)
                     all)))
        (cond
         ((null apps)
          (user-error "No matching Zephyr apps found in this workspace"))
         ((= 1 (length apps))
          (plist-get (car apps) :path))
         (t
          (let* ((by-name (mapcar (lambda (a)
                                    (cons (plist-get a :name)
                                          (plist-get a :path)))
                                  apps))
                 (choice  (completing-read "App: " (mapcar #'car by-name)
                                           nil t)))
            (cdr (assoc choice by-name))))))))

(defun zephyr--patch-run (subcommands label app-path)
  (let* ((root      (zephyr--resolve-app app-path #'zephyr-patches-yml))
         (workspace (and root (west-workspace-root root))))
    (unless (zephyr-patches-yml root)
      (user-error "No zephyr/patches.yml found for %s"
                  (or root "current app")))
    (unless workspace
      (user-error "No west workspace found for %s" root))
    (let* ((default-directory (expand-file-name workspace))
           (module (shell-quote-argument
                    (directory-file-name
                     (file-relative-name root workspace))))
           (subs (if (listp subcommands) subcommands (list subcommands))))
      (west--compile label
                     (mapconcat
                      (lambda (sub) (format "west patch -sm %s %s" module sub))
                      subs " && ")))))

(defun zephyr-patch-apply (&optional app-path)
  (interactive)
  (zephyr--patch-run "apply" "patch-apply" app-path))

(defun zephyr-patch-clean (&optional app-path)
  (interactive)
  (zephyr--patch-run "clean" "patch-clean" app-path))

(defun zephyr-patch-clean-apply (&optional app-path)
  (interactive)
  (zephyr--patch-run '("clean" "apply") "patch-clean-apply" app-path))

(provide 'zephyr)

;;; zephyr.el ends here
