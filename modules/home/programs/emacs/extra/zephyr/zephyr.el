;;; zephyr.el --- Zephyr Project Support  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/zephyr
;; Keywords: tools, embedded
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (west "0.0") (yaml "0.5") (compile-multi "0.7"))

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
;; Zephyr RTOS ..
;;
;;; Code:

(require 'west)
(require 'xdg)
(require 'yaml)
(require 'treesit)
(require 'compile-multi)

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
  "Non-nil if DIRECTORY's `CMakeLists.txt' has `find_package(Zephyr)' and `project()'."
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
  (let* ((config (west-config))
          (env (getenv "ZEPHYR_BASE"))
          (config-value (cdr (assoc "zephyr.base" config)))
          (config-resolved (when config-value
                             (if (file-name-absolute-p config-value)
                               config-value
                               (when-let ((root (or workspace-root (west-workspace-root))))
                                 (expand-file-name config-value root)))))
          (prefer (or (cdr (assoc "zephyr.base-prefer" config)) "env"))
          (result (if (equal prefer "configfile")
                    (or config-resolved env)
                    (or env config-resolved))))
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
  (string-remove-prefix "zephyr-sdk-"
    (file-name-nondirectory (directory-file-name path))))

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

(defun zephyr--make-app-plist (app-path manifest-path)
  "Build a zephyr-app plist from APP-PATH + MANIFEST-PATH."
  (list :name     (or (zephyr-app-name app-path)
                    (file-name-nondirectory (directory-file-name app-path)))
    :path     app-path
    :manifest manifest-path
    :boards   (zephyr-app-boards app-path)))

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
      (ensure-list board-root))))

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
                (equal hint (string-replace "/" "_" (plist-get board :id))))
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

(defconst zephyr--sysbuild-soc-pattern "esp32s3"
  "Board-id substring identifying SoCs that build with `--sysbuild'.")

(defconst zephyr--emulated-board-pattern "qemu\\|native"
  "Board-id regexp identifying emulated targets (run, not flashed).")

(defun zephyr--board-sysbuild-p (board-id)
  "Non-nil if BOARD-ID targets the esp32s3 SoC."
  (and (string-match-p zephyr--sysbuild-soc-pattern board-id) t))

(defun zephyr--west-build-command (board-id app build-dir)
  "Return the `west build' command for BOARD-ID from APP source into BUILD-DIR."
  (string-join
    (append '("west" "build")
      (and (zephyr--board-sysbuild-p board-id) '("--sysbuild"))
      (list "-b" board-id "-d" build-dir app))
    " "))

(defun zephyr--west-flash-command (build-dir)
  "Return the `west flash' command targeting BUILD-DIR."
  (concat "west flash -d " build-dir))

(defun zephyr--board-emulated-p (board-id)
  "Non-nil if BOARD-ID is an emulated target (run via QEMU/native, not flashed)."
  (and (string-match-p zephyr--emulated-board-pattern board-id) t))

(defun zephyr--west-run-command (board-id app build-dir)
  "Return the `west build -t run' command for BOARD-ID from APP into BUILD-DIR."
  (string-join
    (append '("west" "build")
      (and (zephyr--board-sysbuild-p board-id) '("--sysbuild"))
      (list "-b" board-id "-d" build-dir "-t" "run" app))
    " "))

(defun zephyr--west-test-command (board-id app build-dir)
  "Return the run command layering test.conf for BOARD-ID from APP into BUILD-DIR."
  (concat (zephyr--west-run-command board-id app build-dir)
    " -- -DEXTRA_CONF_FILE=test.conf"))

(defconst zephyr--compile-multi-group "\U000f1985"
  "Kite glyph flanking the west compile-multi group header.")

(defconst zephyr--task-annotation (concat "west " zephyr--compile-multi-group)
  "Right-column annotation (label plus kite glyph) for west compile-multi tasks.")

(defconst zephyr--board-display-max 24
  "Maximum width of a board string shown in a compile-multi row.")

(defun zephyr--board-display (board-id &optional width)
  "Return BOARD-ID for display, middle-eliding the qualifier past WIDTH."
  (let ((width (or width zephyr--board-display-max)))
    (if (<= (length board-id) width)
      board-id
      (let* ((segments (split-string board-id "/" t))
              (elided (if (> (length segments) 2)
                        (concat (car segments) "/\u2026/" (car (last segments)))
                        board-id)))
        (if (<= (length elided) width)
          elided
          (concat (truncate-string-to-width elided (max 1 (1- width))) "\u2026"))))))

(defun zephyr-board-aliases (file)
  "Parse FILE's board-alias lines into an (ALIAS . BOARD) alist."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let (aliases)
        (while (re-search-forward
                 "set(\\([A-Za-z0-9_]+\\)_BOARD_ALIAS[ \t]+\\([^ \t)]+\\)" nil t)
          (push (cons (match-string 1) (match-string 2)) aliases))
        (nreverse aliases)))))

(defun zephyr--board-base (board)
  "Return BOARD's base name: its first `/'-segment with any `@revision' dropped."
  (car (split-string (car (split-string board "/")) "@")))

(defun zephyr--app-board-entries (app-path)
  "Return (LABEL . BOARD) entries for APP-PATH.
Every alias in `boards/aliases.cmake' is used as-is; each supported board
whose base is not already aliased is added under its canonical name."
  (let* ((aliases (zephyr-board-aliases
                    (expand-file-name "boards/aliases.cmake" app-path)))
          (aliased-bases (mapcar (lambda (entry) (zephyr--board-base (cdr entry)))
                           aliases)))
    (append
      aliases
      (seq-keep
        (lambda (hint)
          (let ((board (or (zephyr-board-id-from-hint hint) hint)))
            (unless (member (zephyr--board-base board) aliased-bases)
              (cons (string-replace "/" "_" board) board))))
        (zephyr-app-boards app-path)))))

(defun zephyr--app-compile-multi-tasks (app-plist workspace)
  "Build + flash/run compile-multi entries for APP-PLIST relative to WORKSPACE."
  (let* ((path (plist-get app-plist :path))
          (app  (directory-file-name (file-relative-name path workspace))))
    (mapcan
      (lambda (entry)
        (let* ((label (car entry))
                (board (cdr entry))
                (shown (zephyr--board-display board))
                (build-dir (concat "build/" label)))
          (append
            (list
              (cons (format "%s west %s :\U000f0862 build %s"
                      zephyr--compile-multi-group zephyr--compile-multi-group shown)
                (list :command (zephyr--west-build-command board app build-dir)
                  :annotation (propertize "\U0000e794" 'face 'nerd-icons-lgreen))))
            (if (zephyr--board-emulated-p board)
              (list
                (cons (format "%s west %s :\U000f0379 run %s"
                        zephyr--compile-multi-group zephyr--compile-multi-group shown)
                  (list :command
                    (lambda ()
                      (west--run-interactive
                        "run" (zephyr--west-run-command board app build-dir)))
                    :annotation zephyr--task-annotation))
                (cons (format "%s west %s :\U000f0cea test %s"
                        zephyr--compile-multi-group zephyr--compile-multi-group shown)
                  (list :command (zephyr--west-test-command
                                   board app (concat build-dir "-test"))
                    :annotation zephyr--task-annotation)))
              (list
                (cons (format "%s west %s :\U000f0530 flash %s"
                        zephyr--compile-multi-group zephyr--compile-multi-group shown)
                  (list :command (zephyr--west-flash-command build-dir)
                    :annotation zephyr--task-annotation)))))))
      (zephyr--app-board-entries path))))

(defun zephyr-compile-multi-tasks ()
  "Workspace-wide `west build'/`west flash' compile-multi entries per board."
  (when-let* ((workspace (west-workspace-root)))
    (mapcan (lambda (app) (zephyr--app-compile-multi-tasks app workspace))
      (zephyr-apps workspace))))

(add-to-list 'compile-multi-config
  '((west-in-workspace-p) . (zephyr-compile-multi-tasks)))

(provide 'zephyr)

;;; zephyr.el ends here
