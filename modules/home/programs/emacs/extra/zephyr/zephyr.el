;;; zephyr.el --- Zephyr RTOS workspace integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/zephyr
;; Keywords: tools, embedded
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (west "0.0") (yaml "0.5"))

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
;; Zephyr RTOS workspace integration: app detection, SDK + toolchain
;; resolution, CMake build command assembly, and `west patch' wrappers.
;; Generic west / manifest logic lives in west.el.
;;
;; Commands:
;;   zephyr-build              compile a Zephyr application
;;   zephyr-patch-apply        apply patches
;;   zephyr-patch-clean        clean patches
;;   zephyr-patch-clean-apply  clean then apply
;;   zephyr-boards-invalidate  drop the boards cache (in-memory + on-disk)
;;
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
  "Non-nil if DIRECTORY's `CMakeLists.txt' has `find_package(Zephyr)'
and `project()'."
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
  "Walk up from DIRECTORY to find the enclosing Zephyr app root."
  (locate-dominating-file (or directory default-directory) #'zephyr-app-p))

(defun zephyr-app-name (app-path)
  "Return the CMake project name declared in APP-PATH's `CMakeLists.txt'."
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
  "Return deduped board names from APP-PATH's `boards/' `.conf'/`.overlay' files."
  (let ((boards-dir (expand-file-name "boards" app-path)))
    (when (file-directory-p boards-dir)
      (seq-uniq
        (mapcar #'file-name-base
          (directory-files boards-dir nil "\\.\\(conf\\|overlay\\)\\'"))))))

(defun zephyr--cache-file (name)
  "Return the path of cache file NAME under `zephyr-cache-dir'."
  (expand-file-name (concat name ".eld") zephyr-cache-dir))

(defun zephyr--cache-load (name)
  "Read and return the Lisp value cached under NAME, or nil if absent."
  (let ((cache-file (zephyr--cache-file name)))
    (when (file-exists-p cache-file)
      (with-temp-buffer
        (insert-file-contents cache-file)
        (read (current-buffer))))))

(defun zephyr--cache-save (name data)
  "Persist DATA to the on-disk cache under NAME."
  (make-directory zephyr-cache-dir t)
  (with-temp-file (zephyr--cache-file name)
    (prin1 data (current-buffer))))

(defun zephyr-base (&optional workspace-root)
  "Return ZEPHYR_BASE: env var, else `.west/config' value, as a directory."
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
  "Return the trimmed contents of the `VERSION' file at BASE (or `zephyr-base')."
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
  "Return ZEPHYR_SDK_INSTALL_DIR, else the highest-version SDK on disk."
  (or (getenv "ZEPHYR_SDK_INSTALL_DIR")
      (car (zephyr--sdk-discover))))

(defun zephyr--sdk-discover ()
  "Return SDK directories matching `zephyr-sdk-search-paths', newest first."
  (sort (seq-filter
         (lambda (dir) (file-exists-p (expand-file-name "sdk_version" dir)))
         (mapcan (lambda (pattern)
                   (file-expand-wildcards (expand-file-name pattern)))
                 zephyr-sdk-search-paths))
        (lambda (a b)
          (version< (zephyr--sdk-version-from-path b)
                    (zephyr--sdk-version-from-path a)))))

(defun zephyr--sdk-version-from-path (path)
  "Extract the version suffix from a `zephyr-sdk-X.Y.Z' PATH."
  (if (string-match "zephyr-sdk-\\(.+?\\)/?\\'" path)
      (match-string 1 path)
    path))

(defun zephyr-sdk-version (&optional sdk-path)
  "Return the `sdk_version' contents at SDK-PATH (or `zephyr-sdk-path')."
  (let* ((path (or sdk-path (zephyr-sdk-path)))
         (version-file (and path (expand-file-name "sdk_version" path))))
    (when (and version-file (file-exists-p version-file))
      (with-temp-buffer
        (insert-file-contents version-file)
        (string-trim (buffer-string))))))

(defun zephyr-sdk-toolchains (&optional sdk-path)
  "List `zephyr-elf'/`zephyr-eabi' toolchain subdirs of SDK-PATH."
  (let ((path (or sdk-path (zephyr-sdk-path))))
    (when (and path (file-directory-p path))
      (directory-files path nil "zephyr-\\(elf\\|eabi\\)\\'"))))

(defun zephyr-toolchain-variant ()
  "Return ZEPHYR_TOOLCHAIN_VARIANT env var (defaults to \"zephyr\")."
  (or (getenv "ZEPHYR_TOOLCHAIN_VARIANT") "zephyr"))

(defun zephyr-board ()
  "Return BOARD env var, falling back to `build.board' in `.west/config'."
  (or (getenv "BOARD")
      (cdr (assoc "build.board" (west-config)))))

(defun zephyr-shield ()
  "Return the SHIELD env var as a list (semicolon-separated)."
  (when-let ((value (getenv "SHIELD")))
    (split-string value ";" t " ")))

(defun zephyr-snippet ()
  "Return the SNIPPET env var as a list (semicolon-separated)."
  (when-let ((value (getenv "SNIPPET")))
    (split-string value ";" t " ")))

(defun zephyr--env-list (var)
  "Return env VAR as a list split on `path-separator', or nil if unset."
  (when-let ((value (getenv var)))
    (split-string value path-separator t " ")))

(defun zephyr-board-roots       () "BOARD_ROOT as a list."        (zephyr--env-list "BOARD_ROOT"))
(defun zephyr-shield-roots      () "SHIELD_ROOT as a list."       (zephyr--env-list "SHIELD_ROOT"))
(defun zephyr-snippet-roots     () "SNIPPET_ROOT as a list."      (zephyr--env-list "SNIPPET_ROOT"))
(defun zephyr-soc-roots         () "SOC_ROOT as a list."          (zephyr--env-list "SOC_ROOT"))
(defun zephyr-arch-roots        () "ARCH_ROOT as a list."         (zephyr--env-list "ARCH_ROOT"))
(defun zephyr-dts-roots         () "DTS_ROOT as a list."          (zephyr--env-list "DTS_ROOT"))
(defun zephyr-module-ext-roots  () "MODULE_EXT_ROOT as a list."   (zephyr--env-list "MODULE_EXT_ROOT"))

(defun zephyr-modules ()
  "Return ZEPHYR_MODULES as a list."
  (zephyr--env-list "ZEPHYR_MODULES"))

(defun zephyr-extra-modules ()
  "Return EXTRA_ZEPHYR_MODULES as a list."
  (zephyr--env-list "EXTRA_ZEPHYR_MODULES"))

(defun zephyr--cmake-arg (key value)
  "Format `-DKEY=VALUE' (list VALUE joined by `;'); nil when VALUE is nil."
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
  "Return a list of `-DKEY=VALUE' args from env.
Plist OVERRIDES take precedence."
  (seq-keep (pcase-lambda (`(,key ,name ,getter))
              (zephyr--cmake-arg name
                                 (or (plist-get overrides key)
                                     (funcall getter))))
            zephyr--cmake-arg-spec))

(defun zephyr-build-dir (&optional workspace-root)
  "Return `<WORKSPACE-ROOT>/build' (defaults to the active workspace)."
  (when-let ((root (or workspace-root (west-workspace-root))))
    (expand-file-name "build" root)))

(defun zephyr-build-command (app &optional overrides)
  "Return a shell command that configures + builds APP with optional OVERRIDES."
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
  "Compile a Zephyr application at APP using `compile' with optional OVERRIDES."
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
  "Return Zephyr apps in WORKSPACE-ROOT as plists (:name :path :manifest :boards).
Falls back to `<WORKSPACE-ROOT>/app/' when the manifest declares none."
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
  "Build a zephyr-app plist from PATH + MANIFEST-PATH."
  (list :name     (or (zephyr-app-name path)
                      (file-name-nondirectory (directory-file-name path)))
        :path     path
        :manifest manifest-path
        :boards   (zephyr-app-boards path)))

(defvar zephyr--boards-cache nil
  "In-memory cache of parsed boards; mirrors the on-disk `boards' cache file.")

(defun zephyr-boards (&optional base)
  "Return all parsed board plists; cached unless BASE overrides the lookup."
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
  "Drop the in-memory + on-disk boards cache."
  (interactive)
  (setq zephyr--boards-cache nil)
  (let ((cache-file (zephyr--cache-file "boards")))
    (when (file-exists-p cache-file) (delete-file cache-file))))

(defun zephyr-module-board-roots (&optional workspace-root)
  "Return absolute board roots from WORKSPACE-ROOT's `zephyr/module.yml'."
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
  "Parse every `boards/**/*.yaml' under BASE + apps + module roots."
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
  "Resolve underscore-slugified HINT to the canonical `board/soc/core' ID."
  (plist-get
   (seq-find (lambda (board)
               (equal hint (replace-regexp-in-string "/" "_" (plist-get board :id))))
             (zephyr-boards))
   :id))

(defun zephyr--parse-board-file (path)
  "Parse a single board YAML at PATH into a plist (nil for HWMv2 files)."
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
  "Return APP-PATH's `zephyr/patches.yml' (defaults to current app), or nil."
  (when-let* ((root (or app-path (zephyr-app-root))))
    (let ((yml (expand-file-name "zephyr/patches.yml" root)))
      (when (file-exists-p yml) yml))))

(defun zephyr--resolve-app (&optional app-path filter)
  "Resolve a Zephyr app: APP-PATH, then current, then sole match, then prompt.
FILTER, if non-nil, must accept an APP path and return non-nil to keep it."
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
  "Run `west patch SUBCOMMANDS' for APP-PATH; output to `*west:LABEL*'."
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
  "Apply patches declared in APP-PATH's `zephyr/patches.yml'."
  (interactive)
  (zephyr--patch-run "apply" "patch-apply" app-path))

(defun zephyr-patch-clean (&optional app-path)
  "Reset patches declared in APP-PATH's `zephyr/patches.yml'."
  (interactive)
  (zephyr--patch-run "clean" "patch-clean" app-path))

(defun zephyr-patch-clean-apply (&optional app-path)
  "Clean then apply patches declared in APP-PATH's `zephyr/patches.yml'."
  (interactive)
  (zephyr--patch-run '("clean" "apply") "patch-clean-apply" app-path))

(provide 'zephyr)

;;; zephyr.el ends here
