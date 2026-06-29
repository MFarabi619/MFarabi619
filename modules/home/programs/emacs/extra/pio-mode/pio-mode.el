;;; pio-mode.el --- PlatformIO project integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright © 2025-2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/pio-mode
;; Keywords: tools, embedded
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

(require 'cl-lib)
(require 'compile-multi)
(require 'json)
(require 'map)
(require 'nerd-icons)
(require 'pcase)
(require 'seq)
(require 'vui-components)
(require 'xdg)

;;; Declarations

(defvar vterm-shell)
(defvar vterm-buffer-name)

(declare-function vterm          "vterm")
(declare-function vterm-send-key "vterm" (key &optional shift meta ctrl accept-proc-output))
(declare-function serial-term    "term"  (port speed &optional line-mode))
(declare-function evil-make-overriding-map "evil-core" (keymap &optional state copy))

;;; Customization
(defgroup pio ()
  "PlatformIO project integration."
  :prefix "pio-"
  :group 'tools
  :group 'embedded
  :link '(url-link :tag "GitHub" "https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/pio-mode")
  :link '(emacs-commentary-link :tag "Commentary" "pio-mode"))

(defcustom pio-executable nil
  "Path to the pio executable. If nil, search PATH for pio or platformio.
Set this to a specific path when multiple PlatformIO installations
exist on your system to choose which one to use."
  :type '(choice (const :tag "Auto-detect" nil) file))

(defun pio--executable ()
  "Return the configured PlatformIO binary, falling back to PATH lookup."
  (or pio-executable
    (executable-find "pio")
    (executable-find "platformio")
    "pio"))

(defun pio--detect-executables ()
  "Return each `pio'/`platformio' executable on variable `exec-path'.
Deduplicated, in original order."
  (delete-dups
    (cl-loop for dir in exec-path
      nconc (cl-loop for name in '("pio" "platformio")
              for path = (expand-file-name name dir)
              when (and (file-executable-p path)
                     (not (file-directory-p path)))
              collect path))))

(defvar pio--multiple-executables-warned nil
  "Non-nil after the multiple-executables warning has been shown once.")

(defun pio--warn-multiple-executables ()
  "Display a one-shot warning if more than one PlatformIO binary is on PATH."
  (unless pio--multiple-executables-warned
    (setq pio--multiple-executables-warned t)
    (let ((executables (pio--detect-executables)))
      (when (length> executables 1)
        (display-warning
          'pio
          (format "Multiple PlatformIO executables on PATH:\n%s\nUsing: %s\nSet `pio-executable' to override."
            (mapconcat (lambda (path) (concat "  " path)) executables "\n")
            (pio--executable))
          :warning)))))

(defun pio-p (&optional directory)
  "Non-nil if DIRECTORY has a `platformio.ini' file."
  (file-exists-p
    (expand-file-name "platformio.ini" (or directory default-directory))))

(defun pio-root (&optional directory)
  "Walk up from DIRECTORY to find the enclosing `platformio.ini' project."
  (locate-dominating-file (or directory default-directory) "platformio.ini"))

(defun pio-in-project-p (&optional directory)
  "Non-nil if DIRECTORY (or `default-directory') is inside a PlatformIO project."
  (and (pio-root directory) t))

(defun pio-name (&optional project-root)
  "Return the basename of PROJECT-ROOT (or the discovered project)."
  (when-let* ((root (or project-root (pio-root))))
    (file-name-nondirectory (directory-file-name root))))

(defun pio-config-file (&optional project-root)
  "Return the absolute path of PROJECT-ROOT's `platformio.ini'."
  (when-let* ((root (or project-root (pio-root))))
    (expand-file-name "platformio.ini" root)))

(defvar pio--config-cache (make-hash-table :test 'equal)
  "Per-project cache mapping ROOT -> (MTIME . PARSED-CONFIG).")

(defun pio--read-project-config (project-root)
  "Shell out to `pio project config --json-output' for PROJECT-ROOT (uncached).
Signals `pio-exec-error'/`pio-parse-error' on failure."
  (mapcar (pcase-lambda (`(,section ,settings))
            (cons section
              (mapcar (pcase-lambda (`(,k ,v)) (cons k v)) settings)))
    (pio--run-json-as 'hash-table 'list
      "project" "config" "--json-output"
      "-d" (directory-file-name (expand-file-name project-root)))))

(defun pio-project-config (&optional project-root)
  "Return parsed `platformio.ini' for PROJECT-ROOT, cached by file mtime."
  (when-let* ((root (or project-root (pio-root)))
               (ini  (pio-config-file root))
               ((file-exists-p ini)))
    (let* ((mtime  (file-attribute-modification-time (file-attributes ini)))
            (cached (gethash root pio--config-cache)))
      (if (and cached (equal (car cached) mtime))
        (cdr cached)
        (let ((parsed (pio--read-project-config root)))
          (puthash root (cons mtime parsed) pio--config-cache)
          parsed)))))

(defun pio-project-config-invalidate (&optional project-root)
  "Drop the cached `platformio.ini' parse for PROJECT-ROOT (or every project)."
  (interactive)
  (if project-root
    (remhash project-root pio--config-cache)
    (clrhash pio--config-cache)))
(put 'pio-project-config-invalidate 'completion-predicate #'ignore)

(defvar pio--project-metadata-cache (make-hash-table :test 'equal)
  "Per-project cache mapping ROOT -> (MTIME . PARSED-METADATA).")

(defun pio--read-project-metadata (project-root)
  "Shell out to `pio project metadata --json-output' for PROJECT-ROOT (uncached).
Returns a hash-table keyed by env name."
  (pio--run-json-as 'hash-table 'list
    "project" "metadata" "--json-output"
    "-d" (directory-file-name (expand-file-name project-root))))

(defun pio-project-metadata (&optional project-root)
  "Return parsed `pio project metadata' for PROJECT-ROOT, cached by file mtime."
  (when-let* ((root (or project-root (pio-root)))
               (ini  (pio-config-file root))
               ((file-exists-p ini)))
    (let* ((mtime  (file-attribute-modification-time (file-attributes ini)))
            (cached (gethash root pio--project-metadata-cache)))
      (if (and cached (equal (car cached) mtime))
        (cdr cached)
        (let ((parsed (pio--read-project-metadata root)))
          (puthash root (cons mtime parsed) pio--project-metadata-cache)
          parsed)))))

(defun pio-project-metadata-invalidate (&optional project-root)
  "Drop the cached `pio project metadata' parse for PROJECT-ROOT.
With no PROJECT-ROOT, clear every project's cache."
  (interactive)
  (if project-root
    (remhash project-root pio--project-metadata-cache)
    (clrhash pio--project-metadata-cache)))
(put 'pio-project-metadata-invalidate 'completion-predicate #'ignore)

(defun pio-env-targets (env &optional project-root)
  "Return ENV's buildable target names from PROJECT-ROOT's metadata."
  (when-let* ((metadata (pio-project-metadata project-root))
               (env-data (gethash env metadata))
               (targets  (gethash "targets" env-data)))
    (mapcar (lambda (target) (gethash "name" target)) targets)))

(defun pio-envs (&optional project-root)
  "Return the list of env names declared in PROJECT-ROOT's `platformio.ini'."
  (seq-keep (pcase-lambda (`(,section . ,_))
              (when (string-prefix-p "env:" section)
                (string-remove-prefix "env:" section)))
    (pio-project-config project-root)))

(defun pio--read-key (section key &optional project-root)
  "Look up KEY in SECTION of PROJECT-ROOT's resolved config."
  (when-let* ((config   (pio-project-config project-root))
               (settings (cdr (assoc section config))))
    (cdr (assoc key settings))))

(defun pio-default-envs (&optional project-root)
  "Return PROJECT-ROOT's default envs (env var > `[platformio]' `default_envs')."
  (let ((value (or (getenv "PLATFORMIO_DEFAULT_ENVS")
                 (pio--read-key "platformio" "default_envs" project-root))))
    (cond ((listp value)   value)            ; nil falls in here (empty list)
      ((stringp value) (split-string value "[ ,]+" t)))))

(defun pio-env-board (env &optional project-root)
  "Return the `board' key for `[env:ENV]' in PROJECT-ROOT."
  (pio--read-key (format "env:%s" env) "board" project-root))

(defun pio-env-platform (env &optional project-root)
  "Return the `platform' key for `[env:ENV]' in PROJECT-ROOT."
  (pio--read-key (format "env:%s" env) "platform" project-root))

(defun pio-env-framework (env &optional project-root)
  "Return the `framework' key for `[env:ENV]' in PROJECT-ROOT."
  (pio--read-key (format "env:%s" env) "framework" project-root))

(defun pio--compile-command (args &optional env project-root)
  "Return a `pio' shell command string from ARGS, scoped to ENV under PROJECT-ROOT.
ARGS is the subcommand list (e.g. (\"run\" \"-t\" \"upload\")).  ENV, when non-nil,
appends `--environment ENV'.  PROJECT-ROOT defaults to the discovered pio root."
  (let ((root (or project-root (pio-root) default-directory)))
    (mapconcat #'shell-quote-argument
      `(,(pio--executable)
         ,@args
         "--project-dir" ,(directory-file-name (expand-file-name root))
         ,@(when env (list "--environment" env)))
      " ")))

(defcustom pio-compile-multi-targets
  '(("pio run"              "nf-md-play"            ("run"))
     ("pio test"             "nf-dev-embeddedc"      ("test"))
     ("pio test --without"   "nf-md-alarm_light"     ("test" "--without-building" "--without-uploading"))
     ("pio run -t upload"    "nf-md-transfer_right"  ("run" "-t" "upload"))
     ("pio run -t compiledb" "nf-dev-vscode"         ("run" "-t" "compiledb"))
     ("pio run -t uploadfs"  "nf-fa-cloud_arrow_up"  ("run" "-t" "uploadfs"))
     ("pio device monitor"   "nf-md-telescope"       ("device" "monitor")))
  "Compile-multi tasks generated per env, each `(DISPLAY ICON ARGS)'.
DISPLAY is the row label, ICON a nerd-icons `nf-SET-NAME' glyph (any set), ARGS
the `pio' subcommand.  The command is scoped to the env via `--environment'."
  :type '(repeat (list (string :tag "Display")
                   (string :tag "Nerd-icon name")
                   (repeat :tag "pio args" string))))

(defcustom pio-compile-multi-all-envs nil
  "When non-nil, generate tasks for every env, not just `default_envs'."
  :type 'boolean)

(defcustom pio-compile-multi-show-label nil
  "When non-nil, show the \"platformio\" label beside each task's bee icon.
Off by default: the annotation is icon-only (just the bee)."
  :type 'boolean)

(defun pio--compile-multi-annotation ()
  "Build the right-aligned task annotation: the bee icon, optionally labeled.
Honors `pio-compile-multi-show-label'."
  (let ((bee (nerd-icons-sucicon "nf-seti-platformio" :face 'nerd-icons-yellow)))
    (if pio-compile-multi-show-label
      (concat "platformio " bee)
      bee)))

(defconst pio--nerd-icon-functions
  '(("nf-md-"   . nerd-icons-mdicon)
     ("nf-dev-"  . nerd-icons-devicon)
     ("nf-fa-"   . nerd-icons-faicon)
     ("nf-cod-"  . nerd-icons-codicon)
     ("nf-seti-" . nerd-icons-sucicon)
     ("nf-oct-"  . nerd-icons-octicon))
  "Map nerd-icons `nf-SET-' name prefixes to their renderer functions.")

(defun pio--nerd-icon (name)
  "Render nerd-icon NAME via the renderer for its `nf-SET-' prefix."
  (let ((render (cdr (seq-find (lambda (pair) (string-prefix-p (car pair) name))
                       pio--nerd-icon-functions))))
    (funcall (or render #'nerd-icons-mdicon) name)))

(defun pio--compile-multi-task (spec env root)
  "Build a `(TITLE . PLIST)' compile-multi entry from SPEC for ENV under ROOT.
SPEC is `(DISPLAY ICON ARGS)'; the task is grouped under ENV's bare name."
  (cons (format "%s  :%s %s"
          env
          (pio--nerd-icon (nth 1 spec))
          (nth 0 spec))
    (list :command    (pio--compile-command (nth 2 spec) env root)
      :annotation (pio--compile-multi-annotation))))

(defun pio-compile-multi-tasks ()
  "Return the per-env compile-multi tasks for the current pio project.
Generates `pio-compile-multi-targets' for each env, grouped by env name.
Honors `pio-compile-multi-all-envs' (otherwise only `default_envs')."
  (when-let* ((root (pio-root))
               (envs (or (and (not pio-compile-multi-all-envs)
                           (pio-default-envs root))
                       (pio-envs root))))
    (mapcan
      (lambda (env)
        (mapcar (lambda (spec) (pio--compile-multi-task spec env root))
          pio-compile-multi-targets))
      envs)))

(add-to-list 'compile-multi-config
  '((pio-in-project-p) . (pio-compile-multi-tasks)))

(defun pio-build-dir (&optional project-root)
  "Return PROJECT-ROOT's build directory (env var > `<root>/.pio')."
  (or (getenv "PLATFORMIO_BUILD_DIR")
    (when-let* ((root (or project-root (pio-root))))
      (expand-file-name ".pio" root))))

(defun pio--device-list (kind)
  "Return parsed `pio device list --KIND --json-output' (KIND is serial/logical).
Returns a vector of hash-tables.  Signals typed errors via `pio--run-json-as'."
  (pio--run-json-as 'hash-table 'array
    "device" "list" (format "--%s" kind) "--json-output"))

(defun pio-serial-devices ()
  "Return detected serial devices as a hash-table vector."
  (pio--device-list "serial"))

(defun pio-logical-devices ()
  "Return detected logical (filesystem-mountable) devices."
  (pio--device-list "logical"))

(defcustom pio-device-list-hide-unidentified t
  "When non-nil, hide devices whose `hwid' is missing or \"n/a\".
This catches Bluetooth audio peripherals, system serial endpoints, and
anything else `pio device list' cannot identify as a real serial device.
Real USB serial adapters always carry a `VID:PID=...' hwid."
  :type 'boolean)

(defcustom pio-device-list-exclude-regexps nil
  "Port paths matching any of these regexps are hidden from `pio-device-list'.
Applies on top of `pio-device-list-hide-unidentified'. Each entry is a
regexp matched against the device's port path (e.g.
\"/dev/cu.usbmodem1101\")."
  :type '(repeat regexp))

(defun pio--device-unidentified-p (device)
  "Non-nil if DEVICE has no usable `hwid' (nil / empty / \"n/a\")."
  (let ((hwid (gethash "hwid" device)))
    (or (null hwid) (string-empty-p hwid) (string= hwid "n/a"))))

(defun pio--device-excluded-p (device)
  "Non-nil if DEVICE should be hidden by the heuristic + exclude regexps."
  (or (and pio-device-list-hide-unidentified
        (pio--device-unidentified-p device))
    (let ((port (gethash "port" device)))
      (seq-some (lambda (regexp) (string-match-p regexp port))
        pio-device-list-exclude-regexps))))

(defconst pio--hwid-fields
  '((:vid-pid  . "VID:PID=\\([^ ]+\\)")
     (:serial   . "SER=\\([^ ]+\\)")
     (:location . "LOCATION=\\([^ ]+\\)"))
  "Alist of plist KEY → regex for extracting fields from a PIO hwid string.")

(defun pio--parse-hwid (hwid)
  "Parse a PIO hwid string into a plist `(:vid-pid :serial :location)'.
Returns nil if HWID is not a string; omits keys whose regex doesn't match."
  (when (stringp hwid)
    (cl-loop for (key . regexp) in pio--hwid-fields
      when (string-match regexp hwid)
      nconc (list key (match-string 1 hwid)))))

(defun pio--device-list-entries ()
  "Return `(PORT . [SERIAL VID:PID PORT LOCATION DESCRIPTION])' per device.
Cells are plain strings; the dashboard renders them through
`pio--render-device-row' which applies its own face logic."
  (mapcar (lambda (device)
            (let* ((port        (gethash "port"        device))
                    (description (gethash "description" device))
                    (parsed-hwid (pio--parse-hwid (gethash "hwid" device))))
              (list port
                (vector (or (plist-get parsed-hwid :serial)   "")
                  (or (plist-get parsed-hwid :vid-pid)  "")
                  port
                  (or (plist-get parsed-hwid :location) "")
                  (or description                       "")))))
    (seq-remove #'pio--device-excluded-p (pio-serial-devices))))

(defvar pio--system-info-cache nil
  "In-memory cache of parsed `pio system info' (cleared via invalidate).")

(defun pio-system-info ()
  "Return parsed `pio system info --json-output' as a hash table (cached).
Signals typed errors via `pio--run-json'."
  (or pio--system-info-cache
    (progn
      (pio--warn-multiple-executables)
      (setq pio--system-info-cache
        (pio--run-json "system" "info" "--json-output")))))

(defun pio-system-info-invalidate ()
  "Drop the cached system info + multi-exec warning state."
  (interactive)
  (setq pio--system-info-cache nil
    pio--multiple-executables-warned nil))
(put 'pio-system-info-invalidate 'completion-predicate #'ignore)

(defun pio--system-info-field (key)
  "Return the (:title :value) plist for KEY from `pio system info'."
  (when-let* ((info (pio-system-info))
               (entry (gethash key info)))
    (list :title (gethash "title" entry)
      :value (gethash "value" entry))))

(defun pio-core-version        () "PlatformIO Core version field."         (pio--system-info-field "core_version"))
(defun pio-python-version      () "Python version field."                  (pio--system-info-field "python_version"))
(defun pio-system              () "Operating system field."                (pio--system-info-field "system"))
(defun pio-platform            () "Platform string field."                 (pio--system-info-field "platform"))
(defun pio-filesystem-encoding () "Filesystem encoding field."             (pio--system-info-field "filesystem_encoding"))
(defun pio-locale-encoding     () "Locale encoding field."                 (pio--system-info-field "locale_encoding"))
(defun pio-core-dir            () "PlatformIO core directory field."       (pio--system-info-field "core_dir"))
(defun pio-platformio-exe      () "PlatformIO Core executable path field." (pio--system-info-field "platformio_exe"))
(defun pio-python-exe          () "Python executable path field."          (pio--system-info-field "python_exe"))
(defun pio-global-lib-nums     () "Global lib count field."                (pio--system-info-field "global_lib_nums"))
(defun pio-dev-platform-nums   () "Installed dev-platform count field."    (pio--system-info-field "dev_platform_nums"))
(defun pio-package-tool-nums   () "Installed package-tool count field."    (pio--system-info-field "package_tool_nums"))

(defconst pio--device-monitor-spec
  '((:port      "monitor_port"     "--port"        :string)
     (:baud      "monitor_speed"    "--baud"        :number)
     (:filters   "monitor_filters"  "--filter"      :list)
     (:eol       "monitor_eol"      "--eol"         :string)
     (:encoding  "monitor_encoding" "--encoding"    :string)
     (:parity    "monitor_parity"   "--parity"      :string)
     (:rtscts    "monitor_rtscts"   "--rtscts"      :flag)
     (:xonxoff   "monitor_xonxoff"  "--xonxoff"     :flag)
     (:rts       "monitor_rts"      "--rts"         :number)
     (:dtr       "monitor_dtr"      "--dtr"         :number)
     (:echo      "monitor_echo"     "--echo"        :flag)
     (:raw       "monitor_raw"      "--raw"         :flag)
     (:env       nil                "--environment" :string)))

(defun pio--device-monitor-coerce (type value)
  "Coerce VALUE to the declared TYPE (`:number', `:flag', `:list', etc.)."
  (pcase type
    (:number (if (numberp value) value (string-to-number value)))
    (:flag   (cond ((booleanp value) value)
               ((stringp value)
                 (and (member (downcase value) '("yes" "true" "1")) t))
               (t (and value t))))
    (:list   (cond ((listp value)   value)
               ((stringp value) (split-string value "[ ,]+" t))))
    (_       value)))

(defun pio-env-monitor (env &optional project-root)
  "Return a coerced plist of monitor settings declared for ENV in PROJECT-ROOT."
  (let ((section (format "env:%s" env))
         result)
    (pcase-dolist (`(,key ,ini-key _ ,type) pio--device-monitor-spec)
      (when ini-key
        (when-let* ((value (pio--read-key section ini-key project-root)))
          (setq result (plist-put result key (pio--device-monitor-coerce type value))))))
    result))

(defcustom pio-device-monitor-profiles nil
  "Alist of named monitor profiles. Each value is a plist of monitor settings.

Example:
  ((esp32 :port \"/dev/cu.usbmodem1101\" :baud 115200
          :filters (\"esp32_exception_decoder\" \"colorize\"))
   (stm32 :port \"/dev/cu.usbserial-A50285BI\" :baud 9600 :rtscts t))"
  :type '(alist :key-type symbol :value-type plist))

(defun pio-device-monitor-resolve (&rest overrides)
  "Merge env settings + named profile + explicit OVERRIDES into one plist."
  (let* ((env-name (or (plist-get overrides :env) (car (pio-default-envs))))
          (profile  (alist-get (plist-get overrides :profile) pio-device-monitor-profiles))
          (env-settings (when env-name (pio-env-monitor env-name))))
    (map-merge 'plist (or env-settings ()) (or profile ()) overrides)))

(defun pio-device-monitor-command-args (settings)
  "Convert resolved monitor SETTINGS plist into CLI argument strings."
  (mapcan (pcase-lambda (`(,key _ ,flag ,type))
            (when-let* ((value (plist-get settings key)))
              (pcase type
                (:flag   (when value (list flag)))
                (:list   (mapcan (lambda (filter-value) (list flag filter-value)) value))
                (:number (list flag (number-to-string value)))
                (_       (list flag value)))))
    pio--device-monitor-spec))

(defun pio-device-monitor-command (&rest overrides)
  "Return the full `pio device monitor' command line for OVERRIDES."
  (append (list (pio--executable) "device" "monitor")
    (pio-device-monitor-command-args
      (apply #'pio-device-monitor-resolve overrides))))

(defun pio--device-monitor-vterm-buffer-name (settings)
  "Return the `*pio:monitor:KEY*' buffer name for SETTINGS (vterm backend).
KEY is the first non-nil of SETTINGS' :port / :profile / :env."
  (format "*pio:monitor:%s*"
    (or (plist-get settings :port)
      (plist-get settings :profile)
      (plist-get settings :env)
      (car (pio-default-envs))
      "default")))

(defun pio--device-monitor-serial-term-find (port)
  "Return a live `serial-term' buffer connected to PORT, or nil."
  (seq-some (lambda (process)
              (and (eq (process-type process) 'serial)
                (equal (plist-get (process-contact process t) :port) port)
                (process-live-p process)
                (process-buffer process)))
    (process-list)))

(defun pio--device-monitor-send-C-c ()
  "Send a literal Ctrl-c to the underlying serial process.
Bound to \\`C-c' in `pio-device-monitor-mode' so the RTOS shell, not Emacs,
receives the interrupt."
  (interactive)
  (vterm-send-key "c" nil nil t))
(put 'pio--device-monitor-send-C-c 'completion-predicate #'ignore)

(defvar pio-device-monitor-mode-map
  (define-keymap
    "C-c" #'pio--device-monitor-send-C-c)
  "Keymap active in `pio-device-monitor-mode'.
Reserves \\`C-c' for the underlying RTOS shell so it doesn't act as
an Emacs prefix.  Buffer + window lifecycle is left to the user
(`SPC b d', `C-x 0', etc.) — vterm tears down the PTY on `kill-buffer',
and evil's default \\`C-g' still toggles insert → normal state.")

(define-minor-mode pio-device-monitor-mode
  "Minor mode for pio serial-monitor vterm buffers.
Only side effect: \\`C-c' is sent to the inferior process instead of
being intercepted by Emacs as a prefix key.

\\{pio-device-monitor-mode-map}"
  :lighter " pio-mon"
  :keymap pio-device-monitor-mode-map)
(put 'pio-device-monitor-mode 'completion-predicate #'ignore)

(defun pio--connected-serial-ports ()
  "Return the list of unique non-excluded serial ports currently connected.
Mirrors `pio--device-list-entries' filtering so the dashboard and the
auto-pick agree on which devices count."
  (mapcar #'car (pio--device-list-entries)))

(defcustom pio-device-monitor-backend 'serial-term
  "Backend used by `pio-device-monitor' to spawn a serial monitor.
Look up the spawn function in `pio-device-monitor-backends'."
  :type 'symbol)

(defcustom pio-device-monitor-backends
  '((vterm       . pio--device-monitor-spawn-vterm)
     (serial-term . pio--device-monitor-spawn-serial-term))
  "Alist of (BACKEND-NAME . SPAWN-FN) used by `pio-device-monitor'.
SPAWN-FN receives the resolved SETTINGS plist (port, baud, filters,
etc.) and is responsible for the full lifecycle: reusing a live
buffer for these settings if one exists, otherwise spawning a fresh
one.  Each backend owns its own buffer-naming convention.
Third parties can register their own backends via `add-to-list'."
  :type '(alist :key-type symbol :value-type function))

(defun pio--device-monitor-spawn-vterm (settings)
  "Spawn (or reuse) the monitor in vterm running `pio device monitor' on SETTINGS."
  (require 'vterm)
  (let* ((monitor-buffer-name (pio--device-monitor-vterm-buffer-name settings))
          (existing-buffer     (get-buffer monitor-buffer-name)))
    (cond
      ((and (buffer-live-p existing-buffer)
         (process-live-p (get-buffer-process existing-buffer)))
        (pop-to-buffer existing-buffer))
      (t
        (when existing-buffer
          (let (kill-buffer-query-functions) (kill-buffer existing-buffer)))
        (let ((vterm-shell (mapconcat #'shell-quote-argument
                             `(,(pio--executable) "device" "monitor"
                                ,@(pio-device-monitor-command-args settings))
                             " "))
               (vterm-buffer-name monitor-buffer-name))
          (vterm))
        (when-let* ((spawned-buffer (get-buffer monitor-buffer-name)))
          (with-current-buffer spawned-buffer (pio-device-monitor-mode 1)))))))

(defun pio--device-monitor-spawn-serial-term (settings)
  "Spawn (or reuse) the monitor as a native `serial-term' on SETTINGS' :port.
Bypasses `serial-read-name' / `serial-read-speed' by passing them
directly.  Does NOT rename the buffer — `serial-term' picks its own
name.  Reuse is via `pio--device-monitor-serial-term-find', which
matches by serial port (process identity), not by buffer name."
  (require 'term)
  (let* ((port     (plist-get settings :port))
          (baud     (plist-get settings :baud))
          (existing (pio--device-monitor-serial-term-find port)))
    (if existing
      (pop-to-buffer existing)
      (serial-term port baud))))

(defun pio-device-monitor (&rest overrides)
  "Monitor device (Serial/Socket) via the backend in `pio-device-monitor-backend'.
OVERRIDES are forwarded to `pio-device-monitor-resolve'.
The chosen backend owns buffer naming, reuse, and lifecycle.

Interactive use:
  - With prefix arg, prompt for a profile from `pio-device-monitor-profiles'.
  - With exactly one serial port connected, auto-use it.
  - Otherwise, drop into the `*pio*' dashboard to pick a row by hand."
  (interactive
    (cond
      (current-prefix-arg
        (when-let* ((names (mapcar (lambda (profile) (symbol-name (car profile)))
                             pio-device-monitor-profiles))
                     (pick  (completing-read "Profile: " names nil t)))
          (list :profile (intern pick))))
      (t
        (let ((ports (pio--connected-serial-ports)))
          (cond
            ((length= ports 1) (list :port (car ports)))
            (t (pio)
              (user-error "%d serial ports — pick one from *pio*" (length ports))))))))
  (let ((settings (apply #'pio-device-monitor-resolve overrides))
         (spawn    (alist-get pio-device-monitor-backend pio-device-monitor-backends)))
    (unless spawn
      (error "Unknown pio-device-monitor-backend: %s (see `pio-device-monitor-backends')"
        pio-device-monitor-backend))
    (funcall spawn settings)))
(put 'pio-device-monitor 'completion-predicate #'ignore)

;;; Error taxonomy
;; Subclasses of `pio-error' so callers can `condition-case' on specific
;; failure modes without parsing message strings.

(define-error 'pio-error       "PlatformIO error")
(define-error 'pio-exec-error  "PlatformIO CLI execution failed" 'pio-error)
(define-error 'pio-parse-error "PlatformIO output parse failed"  'pio-error)

;;; Generic JSON runner

(defun pio--run-json-as (object-type array-type &rest args)
  "Run pio with ARGS, parse stdout as JSON with the given OBJECT-TYPE/ARRAY-TYPE.
Uses `process-file' so the command runs on the remote host when
`default-directory' is a TRAMP path (local behavior is unchanged).
Signals `pio-exec-error' on non-zero exit, `pio-parse-error' on bad JSON."
  (with-temp-buffer
    (let ((exit-code (apply #'process-file
                       (pio--executable) nil t nil args)))
      (unless (zerop exit-code)
        (signal 'pio-exec-error
          (list :args args :exit-code exit-code
            :output (buffer-string))))
      (condition-case-unless-debug parse-failure
        (json-parse-string (buffer-string)
          :object-type object-type
          :array-type  array-type
          :false-object nil
          :null-object  nil)
        (json-parse-error
          (signal 'pio-parse-error
            (list :args args :output (buffer-string)
              :cause parse-failure)))))))

(defun pio--run-json (&rest args)
  "Run pio with ARGS, parse stdout as a hash-table tree (array → list).
Thin wrapper around `pio--run-json-as' for the common case."
  (apply #'pio--run-json-as 'hash-table 'list args))

;;; Account

(defvar pio--account-cache nil
  "In-memory cache of parsed `pio account show'.")

(defun pio-account-show (&optional refresh)
  "Return parsed `pio account show --json-output' (cached unless REFRESH)."
  (when refresh (setq pio--account-cache nil))
  (or pio--account-cache
    (setq pio--account-cache
      (pio--run-json "account" "show" "--json-output"))))

(defun pio-account-invalidate ()
  "Drop the cached `pio account show'."
  (interactive)
  (setq pio--account-cache nil))
(put 'pio-account-invalidate 'completion-predicate #'ignore)

(defmacro pio--define-account-field (name key docstring)
  "Define a `pio-account-' accessor named after NAME for KEY of ACCOUNT.
DOCSTRING is forwarded onto the generated defun."
  (declare (indent defun))
  `(defun ,(intern (format "pio-account-%s" name)) (&optional account)
     ,docstring
     (gethash ,key (or account (pio-account-show)))))

(pio--define-account-field profile       "profile"       "Profile hash.")
(pio--define-account-field packages      "packages"      "Installed packages.")
(pio--define-account-field subscriptions "subscriptions" "Active subscriptions.")
(pio--define-account-field user-id       "user_id"       "Stable user UUID.")
(pio--define-account-field expire-at     "expire_at"     "Account expiry epoch.")

(defun pio-account-username (&optional account)
  "Return ACCOUNT's profile username."
  (when-let* ((profile (pio-account-profile account)))
    (gethash "username" profile)))

(defun pio-account-email (&optional account)
  "Return ACCOUNT's profile email."
  (when-let* ((profile (pio-account-profile account)))
    (gethash "email" profile)))

(defun pio-account-fullname (&optional account)
  "Return `Firstname Lastname' from ACCOUNT's profile, or nil."
  (when-let* ((profile   (pio-account-profile account))
               (firstname (gethash "firstname" profile))
               (lastname  (gethash "lastname"  profile)))
    (string-trim (format "%s %s" firstname lastname))))

;;; Dashboard

(defconst pio-buffer-name "*pio*"
  "Name of the dashboard buffer.
Named so users can target it from `display-buffer-alist'.")

(defun pio-act-at-point ()
  "Act on the dashboard row at point.
For a device row (`pio-device-port' property), opens the serial monitor."
  (interactive)
  (when-let ((port (get-text-property (point) 'pio-device-port)))
    (pio-device-monitor :port port)))
(put 'pio-act-at-point 'completion-predicate #'ignore)

(defvar pio-mode-map
  (define-keymap :parent special-mode-map
    "RET" #'pio-act-at-point))

(define-derived-mode pio-mode special-mode "pio-mode"
  "Major mode for the `*pio*' dashboard buffer.

\\{pio-mode-map}"
  (setq-local truncate-lines t)
  ;; Under evil, normal-state keys (RET, g, q…) would shadow the dashboard;
  ;; let the map win without depending on evil being installed.
  (when (fboundp 'evil-make-overriding-map)
    (evil-make-overriding-map pio-mode-map 'normal)))
(put 'pio-mode 'completion-predicate #'ignore)

(add-to-list 'nerd-icons-mode-icon-alist
  '(pio-mode nerd-icons-sucicon "nf-seti-platformio"
     :face nerd-icons-yellow))

(defun pio--label (text)
  "Wrap TEXT in the muted-label face."
  (propertize text 'face 'vui-muted))

(defun pio--value (text)
  "Wrap TEXT in the strong face (or muted if nil)."
  (if text
    (propertize text 'face 'vui-strong)
    (propertize "—" 'face 'vui-muted)))

(defun pio--field (label value)
  "Render a `LABEL  VALUE' line."
  (insert "  " (string-pad (pio--label label) 12) "  "
    (pio--value value) "\n"))

(defun pio--set-mode-line (account)
  "Append core version + ACCOUNT username to the mode line.
Uses `mode-line-process' (the canonical per-buffer mode-state slot)
so `mode-name' stays the plain `pio' set by `define-derived-mode' —
ibuffer's Mode column and other consumers of `mode-name' see the
mode name they expect."
  (let ((version (plist-get (pio-core-version) :value))
         (user    (pio-account-username account)))
    (setq mode-line-process
      (list " v" (propertize (or version "?") 'face 'vui-muted)
        "  "
        (propertize (or user "?") 'face 'vui-heading-1)))))

(defun pio--render-package (package)
  "Render a single PACKAGE hash as two lines: title (bold) + description (muted)."
  (insert "  "
    (nerd-icons-mdicon "nf-md-package_variant" :face 'vui-success)
    " "
    (propertize (or (gethash "title" package)
                  (gethash "name"  package) "?")
      'face 'vui-strong)
    "\n      "
    (propertize (or (gethash "description" package) "")
      'face 'vui-muted)
    "\n"))

(defun pio--insert-heading (text)
  "Insert TEXT as a `vui-heading-2'-faced section heading + newline."
  (insert (propertize (concat text "\n") 'face 'vui-heading-2)))

(defun pio--render-profile (account)
  "Render ACCOUNT profile / packages / subscriptions into the current buffer.
Currently unwired from `pio--render' — kept for future re-enable."
  (let ((packages      (pio-account-packages      account))
         (subscriptions (pio-account-subscriptions account)))
    (pio--insert-heading "PROFILE")
    (pio--field "username" (pio-account-username account))
    (pio--field "name"     (pio-account-fullname account))
    (pio--field "email"    (pio-account-email    account))
    (pio--field "user id"  (pio-account-user-id  account))
    (insert "\n")
    (pio--insert-heading (format "PACKAGES (%d)" (length packages)))
    (mapc #'pio--render-package packages)
    (insert "\n")
    (pio--insert-heading
      (format "SUBSCRIPTIONS (%s)" (if subscriptions (length subscriptions) "none")))))

(defun pio--render-table-row (columns cells header-face &optional text-properties)
  "Render one table row using COLUMNS spec + CELLS vector.
COLUMNS is a list of (LABEL WIDTH CELL-FACE).  When HEADER-FACE is
non-nil it overrides every column's CELL-FACE (used for header rows).
TEXT-PROPERTIES is an optional plist applied over the row's extent."
  (let* ((start (point))
          (text (string-join
                  (seq-mapn (lambda (column cell)
                              (let* ((width (cadr column))
                                      (face  (or header-face (caddr column)))
                                      (padded (if (zerop width) cell
                                                (string-pad cell width))))
                                (propertize padded 'face face)))
                    columns cells)
                  " ")))
    (insert text "\n")
    (when text-properties
      (add-text-properties start (point) text-properties))))

(defun pio--render-table-header (columns)
  "Insert the muted column-header row for COLUMNS."
  (pio--render-table-row
    columns
    (vconcat (mapcar #'car columns))
    'vui-muted))

(defconst pio--device-columns
  '(("SERIAL"      18 success)
     ("VID:PID"     10 font-lock-constant-face)
     ("PORT"        21 warning)
     ("LOCATION"     8 font-lock-function-name-face)
     ("DESCRIPTION"  0 font-lock-comment-face))
  "(LABEL WIDTH CELL-FACE) per column for the dashboard's DEVICES table.")

(defun pio--render-device (entry)
  "Render one device ENTRY from `pio--device-list-entries'.
The entry's id (port) is attached as a row text property."
  (pio--render-table-row pio--device-columns (cadr entry) nil
    (list 'pio-device-port (car entry))))

(defun pio--render-devices ()
  "Render the DEVICES section using `pio--device-list-entries'."
  (let ((entries (pio--device-list-entries)))
    (pio--insert-heading (format "DEVICES (%d)" (length entries)))
    (pio--render-table-header pio--device-columns)
    (mapc #'pio--render-device entries)))

(defconst pio--env-columns
  '(("ENV"       16 vui-strong)
     ("BOARD"     24 font-lock-constant-face)
     ("PLATFORM"  12 font-lock-variable-name-face)
     ("FRAMEWORK" 12 font-lock-function-name-face)
     ("DEFAULT"    0 vui-success))
  "(LABEL WIDTH CELL-FACE) per column for the dashboard's ENVIRONMENTS table.")

(defun pio--cell-string (value)
  "Coerce a config VALUE into a string for a dashboard cell.
Lists join with single spaces (e.g. `(\"arduino\")' → \"arduino\");
non-strings are formatted with `%s'; nil becomes the empty string."
  (cond ((null value)    "")
    ((stringp value) value)
    ((listp value)   (string-join (mapcar #'pio--cell-string value) " "))
    (t               (format "%s" value))))

(defun pio--platform-display (value)
  "Return a short display name for platform VALUE.
Extracts NAME from PlatformIO's `platform-NAME.git' URL convention."
  (let ((string (pio--cell-string value)))
    (if (not (string-prefix-p "http" string))
      string
      (string-remove-prefix "platform-"
        (file-name-base (replace-regexp-in-string "#.*\\'" "" string))))))

(defun pio--render-env (env defaults)
  "Render one ENV row, marking it with a star if it's in DEFAULTS."
  (pio--render-table-row
    pio--env-columns
    (vector env
      (pio--cell-string     (pio-env-board     env))
      (pio--platform-display (pio-env-platform  env))
      (pio--cell-string     (pio-env-framework env))
      (if (member env defaults) "★" ""))
    nil))

(defun pio--render-envs ()
  "Render the ENVIRONMENTS section from `pio-envs' + per-env config lookups."
  (when-let ((envs (pio-envs)))
    (let ((defaults (pio-default-envs)))
      (pio--insert-heading (format "ENVIRONMENTS (%d)" (length envs)))
      (pio--render-table-header pio--env-columns)
      (dolist (env envs) (pio--render-env env defaults)))))

(defcustom pio-show-account-modeline nil
  "When non-nil, show core version + account username in the modeline.
Off by default; set to t to enable the `pio--set-mode-line' segment."
  :type 'boolean)

(defun pio--render ()
  "Render the dashboard into the current buffer.
PROFILE/PACKAGES/SUBSCRIPTIONS sections live in `pio--render-profile';
call that directly to re-enable them.  The modeline segment is gated
by `pio-show-account-modeline'."
  (when pio-show-account-modeline
    (pio--set-mode-line (pio-account-show)))
  (pio--render-devices)
  (insert "\n")
  (pio--render-envs))

(defun pio--revert (&rest _)
  "Refresh the `*pio*' buffer (bound as `revert-buffer-function')."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (pio--render)
    (goto-char (point-min))))

;;;###autoload
(defun pio ()
  "Open PlatformIO buffer."
  (interactive)
  (let ((buffer (get-buffer-create pio-buffer-name)))
    (with-current-buffer buffer
      (pio-mode)
      (setq-local revert-buffer-function #'pio--revert)
      (pio--revert))
    (pop-to-buffer buffer)))

(provide 'pio-mode)

;;; pio-mode.el ends here
