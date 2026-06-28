;;; platformio.el --- PlatformIO project integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright © 2025-2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/platformio
;; Keywords: tools, embedded
;; Package-Version: 0.0
;; Package-Revision: nil
;; Package-Requires: ((emacs "29.1") (compat "30"))

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
;; PlatformIO project integration: env/board/framework introspection from
;; `platformio.ini' (cached, parsed via `pio project config --json-output'),
;; a tabulated device-list buffer, and a serial monitor wrapper running
;; through vterm.
;;
;; Commands:
;;   pio-device-list                list detected devices
;;   pio-device-monitor             monitor device (Serial/Socket)
;;   pio-project-config-invalidate  drop the cached `platformio.ini' parse
;;   pio-system-info-invalidate     drop the cached `pio system info'
;;
;;; Code:

(require 'json)
(require 'map)
(require 'nerd-icons)
(require 'pcase)
(require 'vui-components)
(require 'xdg)

;;; Declarations

(defvar vterm-shell)
(defvar vterm-buffer-name)

;;; Customization
(defgroup pio ()
  "PlatformIO project integration."
  :prefix "pio-"
  :group 'tools
  :group 'embedded
  :link '(url-link :tag "GitHub" "https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/platformio")
  :link '(emacs-commentary-link :tag "Commentary" "platformio"))

(defcustom pio-executable nil
  "Path to the pio executable. If nil, search PATH for pio or platformio.
Set this to a specific path when multiple PlatformIO installations
exist on your system to choose which one to use."
  :type '(choice (const :tag "Auto-detect" nil) file)
  :group 'pio)

(defun pio--executable ()
  "Return the configured PlatformIO binary, falling back to PATH lookup."
  (or pio-executable
    (executable-find "pio")
    (executable-find "platformio")
    "pio"))

(defun pio--detect-executables ()
  "Return every `pio'/`platformio' executable found on PATH (deduped)."
  (let (results)
    (dolist (dir (split-string (or (getenv "PATH") "") path-separator t))
      (dolist (name '("pio" "platformio"))
        (let ((path (expand-file-name name dir)))
          (when (and (file-executable-p path)
                  (not (file-directory-p path)))
            (push path results)))))
    (delete-dups (nreverse results))))

(defvar pio--multiple-executables-warned nil
  "Non-nil after the multiple-executables warning has been shown once.")

(defun pio--warn-multiple-executables ()
  "Display a one-shot warning if more than one PlatformIO binary is on PATH."
  (unless pio--multiple-executables-warned
    (setq pio--multiple-executables-warned t)
    (let ((execs (pio--detect-executables)))
      (when (> (length execs) 1)
        (display-warning
          'pio
          (format "Multiple PlatformIO executables on PATH:\n%s\nUsing: %s\nSet `pio-executable' to override."
            (mapconcat (lambda (p) (concat "  " p)) execs "\n")
            (pio--executable))
          :warning)))))

(defun pio-p (&optional directory)
  "Non-nil if DIRECTORY contains a `platformio.ini' file."
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
  (when-let ((root (or project-root (pio-root))))
    (file-name-nondirectory (directory-file-name root))))

(defun pio-config-file (&optional project-root)
  "Return the absolute path of PROJECT-ROOT's `platformio.ini'."
  (when-let ((root (or project-root (pio-root))))
    (expand-file-name "platformio.ini" root)))

(defvar pio--config-cache (make-hash-table :test 'equal)
  "Per-project cache mapping ROOT -> (MTIME . PARSED-CONFIG).")

(defun pio--read-project-config (project-root)
  "Shell out to `pio project config --json-output' for PROJECT-ROOT (uncached)."
  (with-temp-buffer
    (let ((exit (call-process (pio--executable) nil t nil
                  "project" "config"
                  "--json-output"
                  "-d" (directory-file-name
                         (expand-file-name project-root)))))
      (unless (zerop exit)
        (error "pio project config failed (exit %d): %s"
          exit (buffer-string)))
      (mapcar (pcase-lambda (`(,section ,settings))
                (cons section
                  (mapcar (pcase-lambda (`(,k ,v)) (cons k v))
                    settings)))
        (json-parse-string (buffer-string)
          :array-type 'list
          :object-type 'plist
          :false-object nil
          :null-object nil)))))

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

(defun pio-envs (&optional project-root)
  "Return the list of env names declared in PROJECT-ROOT's `platformio.ini'."
  (seq-keep (pcase-lambda (`(,section . ,_))
              (when (string-prefix-p "env:" section)
                (substring section 4)))
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
    (cond ((null value)    nil)
      ((listp value)   value)
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

(defun pio-build-dir (&optional project-root)
  "Return PROJECT-ROOT's build directory (env var > `<root>/.pio')."
  (or (getenv "PLATFORMIO_BUILD_DIR")
    (when-let ((root (or project-root (pio-root))))
      (expand-file-name ".pio" root))))

(defun pio--device-list (kind)
  "Return parsed `pio device list --KIND --json-output' (KIND is serial/logical)."
  (json-parse-string
    (shell-command-to-string
      (format "%s device list --%s --json-output" (pio--executable) kind))))

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
  :type 'boolean
  :group 'pio)

(defcustom pio-device-list-exclude-regexps nil
  "Port paths matching any of these regexps are hidden from `pio-device-list'.
Applies on top of `pio-device-list-hide-unidentified'. Each entry is a
regexp matched against the device's port path (e.g.
\"/dev/cu.usbmodem1101\")."
  :type '(repeat regexp)
  :group 'pio)

(defun pio--device-unidentified-p (device)
  "Non-nil if DEVICE has no usable `hwid' (nil / empty / \"n/a\")."
  (let ((hwid (gethash "hwid" device)))
    (or (null hwid) (string-empty-p hwid) (string= hwid "n/a"))))

(defun pio--device-excluded-p (device)
  "Non-nil if DEVICE should be hidden by the heuristic + exclude regexps."
  (or (and pio-device-list-hide-unidentified
        (pio--device-unidentified-p device))
    (let ((port (gethash "port" device)))
      (seq-some (lambda (re) (string-match-p re port))
        pio-device-list-exclude-regexps))))

(defun pio--parse-hwid (hwid)
  "Parse a PIO hwid string into a plist `(:vid-pid :serial :location)'.
Returns nil if HWID is not a string."
  (when (stringp hwid)
    (let (result)
      (when (string-match "VID:PID=\\([^ ]+\\)" hwid)
        (setq result (plist-put result :vid-pid  (match-string 1 hwid))))
      (when (string-match "SER=\\([^ ]+\\)"     hwid)
        (setq result (plist-put result :serial   (match-string 1 hwid))))
      (when (string-match "LOCATION=\\([^ ]+\\)" hwid)
        (setq result (plist-put result :location (match-string 1 hwid))))
      result)))

(defun pio--device-list-entries ()
  "Build tabulated-list entries for the `*pio-device-list*' buffer."
  (mapcar (lambda (dev)
            (let* ((port   (gethash "port" dev))
                    (desc   (gethash "description" dev))
                    (parsed (pio--parse-hwid (gethash "hwid" dev))))
              (list port
                (vector
                  (propertize (or (plist-get parsed :serial)   "") 'face 'success)
                  (propertize (or (plist-get parsed :vid-pid)  "") 'face 'font-lock-constant-face)
                  (propertize port                                  'face 'warning)
                  (propertize (or (plist-get parsed :location) "") 'face 'font-lock-function-name-face)
                  (propertize (or desc "")                          'face 'font-lock-comment-face)))))
    (seq-remove #'pio--device-excluded-p (pio-serial-devices))))

(defun pio--device-list-refresh ()
  "Refresh `tabulated-list-entries' for `pio-device-list-mode'."
  (setq tabulated-list-entries (pio--device-list-entries)))

(defun pio-device-list-monitor ()
  "Open the serial monitor for the device at point, then return to the list."
  (interactive)
  (when-let* ((port      (tabulated-list-get-id))
               (source    (current-buffer))
               (settings  (pio-monitor-resolve :port port))
               (monitor-name (pio--monitor-buffer-name settings)))
    (pio-device-monitor :port port)
    (when-let ((monitor-buf (get-buffer monitor-name)))
      (with-current-buffer monitor-buf
        (add-hook 'kill-buffer-hook
          (lambda ()
            (when (buffer-live-p source)
              (when-let ((win (get-buffer-window (current-buffer))))
                (set-window-buffer win source))))
          nil t)))))
(put 'pio-device-list-monitor 'completion-predicate #'ignore)

(defvar pio-device-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "RET") #'pio-device-list-monitor)
    (define-key map (kbd "r")   #'revert-buffer)
    map))

(with-eval-after-load 'evil
  (evil-define-key 'normal pio-device-list-mode-map
    (kbd "RET") #'pio-device-list-monitor
    (kbd "r")   #'revert-buffer))

(define-derived-mode pio-device-list-mode tabulated-list-mode "pio-device-list"
  "Major mode for the `pio-device-list' buffer."
  (setq tabulated-list-format
    [("SERIAL"      19 t)
      ("VID:PID"     10 t)
      ("PORT"        24 t)
      ("LOCATION"    10 t)
      ("DESCRIPTION"  0 t)]
    tabulated-list-sort-key (cons "PORT" nil))
  (add-hook 'tabulated-list-revert-hook #'pio--device-list-refresh nil t)
  (tabulated-list-init-header))
(put 'pio-device-list-mode 'completion-predicate #'ignore)

(defun pio-device-list ()
  "List detected devices (old standalone buffer; superseded by `pio')."
  (interactive)
  (let ((buffer (get-buffer-create "*pio-device-list*")))
    (with-current-buffer buffer
      (pio-device-list-mode)
      (pio--device-list-refresh)
      (tabulated-list-print))
    (pop-to-buffer buffer)))
(put 'pio-device-list 'completion-predicate #'ignore)

(defvar pio--system-info-cache nil
  "In-memory cache of parsed `pio system info' (cleared via invalidate).")

(defun pio-system-info ()
  "Return parsed `pio system info --json-output' as a hash table (cached)."
  (or pio--system-info-cache
    (progn
      (pio--warn-multiple-executables)
      (setq pio--system-info-cache
        (json-parse-string
          (shell-command-to-string
            (format "%s system info --json-output" (pio--executable))))))))

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

(defconst pio--monitor-spec
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

(defun pio--monitor-coerce (type value)
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
    (pcase-dolist (`(,key ,ini-key _ ,type) pio--monitor-spec)
      (when ini-key
        (when-let ((value (pio--read-key section ini-key project-root)))
          (setq result (plist-put result key (pio--monitor-coerce type value))))))
    result))

(defcustom pio-monitor-profiles nil
  "Alist of named monitor profiles. Each value is a plist of monitor settings.

Example:
  ((esp32 :port \"/dev/cu.usbmodem1101\" :baud 115200
          :filters (\"esp32_exception_decoder\" \"colorize\"))
   (stm32 :port \"/dev/cu.usbserial-A50285BI\" :baud 9600 :rtscts t))"
  :type '(alist :key-type symbol :value-type plist)
  :group 'pio)

(defun pio-monitor-resolve (&rest overrides)
  "Merge env settings + named profile + explicit OVERRIDES into one plist."
  (let* ((env-name (or (plist-get overrides :env) (car (pio-default-envs))))
          (profile  (alist-get (plist-get overrides :profile) pio-monitor-profiles))
          (env-settings (when env-name (pio-env-monitor env-name))))
    (map-merge 'plist (or env-settings ()) (or profile ()) overrides)))

(defun pio-monitor-command-args (settings)
  "Convert resolved monitor SETTINGS plist into CLI argument strings."
  (mapcan (pcase-lambda (`(,key _ ,flag ,type))
            (when-let ((value (plist-get settings key)))
              (pcase type
                (:flag   (when value (list flag)))
                (:list   (mapcan (lambda (v) (list flag v)) value))
                (:number (list flag (number-to-string value)))
                (_       (list flag value)))))
    pio--monitor-spec))

(defun pio-monitor-command (&rest overrides)
  "Return the full `pio device monitor' command line as a list of strings."
  (append (list (pio--executable) "device" "monitor")
    (pio-monitor-command-args
      (apply #'pio-monitor-resolve overrides))))

(defun pio--monitor-buffer-name (settings)
  "Return the `*pio:monitor:<key>*' buffer name for SETTINGS."
  (format "*pio:monitor:%s*"
    (or (plist-get settings :port)
      (plist-get settings :profile)
      (plist-get settings :env)
      (car (pio-default-envs))
      "default")))

(defun pio--monitor-send-C-c ()
  "Send a literal Ctrl-c to the underlying serial process.
Bound to \\`C-c' in `pio-monitor-mode' so the RTOS shell, not Emacs,
receives the interrupt."
  (interactive)
  (vterm-send-key "c" nil nil t))

(defvar pio-monitor-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c") #'pio--monitor-send-C-c)
    map)
  "Keymap active in `pio-monitor-mode'.
Reserves \\`C-c' for the underlying RTOS shell so it doesn't act as
an Emacs prefix.  Buffer + window lifecycle is left to the user
(`SPC b d', `C-x 0', etc.) — vterm tears down the PTY on kill-buffer,
and evil's default \\`C-g' still toggles insert → normal state.")

(define-minor-mode pio-monitor-mode
  "Minor mode for pio serial-monitor vterm buffers.
Only side effect: \\`C-c' is sent to the inferior process instead of
being intercepted by Emacs as a prefix key."
  :lighter " pio-mon"
  :keymap pio-monitor-mode-map)

(defun pio-device-monitor (&rest overrides)
  "Monitor device (Serial/Socket) (as OVERRIDES)."
  (interactive
    (when current-prefix-arg
      (when-let* ((names (mapcar (lambda (p) (symbol-name (car p)))
                           pio-monitor-profiles))
                   (pick  (completing-read "Profile: " names nil t)))
        (list :profile (intern pick)))))
  (require 'vterm)
  (let* ((settings (apply #'pio-monitor-resolve overrides))
          (bufname  (pio--monitor-buffer-name settings))
          (buffer   (get-buffer bufname)))
    (if (and (buffer-live-p buffer)
          (process-live-p (get-buffer-process buffer)))
      (pop-to-buffer buffer)
      (when buffer (let (kill-buffer-query-functions) (kill-buffer buffer)))
      (let ((vterm-shell (mapconcat #'shell-quote-argument
                           (cons (pio--executable)
                             (cons "device" (cons "monitor"
                                              (pio-monitor-command-args settings))))
                           " "))
             (vterm-buffer-name bufname))
        (vterm))
      (when-let ((new-buf (get-buffer bufname)))
        (with-current-buffer new-buf
          (pio-monitor-mode 1))))))

;;; Error taxonomy
;; Subclasses of `pio-error' so callers can `condition-case' on specific
;; failure modes without parsing message strings.

(define-error 'pio-error       "PlatformIO error")
(define-error 'pio-exec-error  "PlatformIO CLI execution failed" 'pio-error)
(define-error 'pio-parse-error "PlatformIO output parse failed"  'pio-error)

;;; Generic JSON runner

(defun pio--run-json (&rest args)
  "Run pio with ARGS and parse stdout as JSON.
Signals `pio-exec-error' on non-zero exit, `pio-parse-error' on bad JSON."
  (with-temp-buffer
    (let ((exit-code (apply #'call-process
                            (pio--executable) nil t nil args)))
      (unless (zerop exit-code)
        (signal 'pio-exec-error
                (list :args args :exit-code exit-code
                      :output (buffer-string))))
      (condition-case parse-failure
          (json-parse-string (buffer-string)
                             :object-type 'hash-table
                             :array-type  'list
                             :false-object nil
                             :null-object  nil)
        (json-parse-error
         (signal 'pio-parse-error
                 (list :args args :output (buffer-string)
                       :cause parse-failure)))))))

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

(defun pio-account-profile        (&optional account) "Profile hash."           (gethash "profile"       (or account (pio-account-show))))
(defun pio-account-packages       (&optional account) "Installed packages."     (gethash "packages"      (or account (pio-account-show))))
(defun pio-account-subscriptions  (&optional account) "Active subscriptions."   (gethash "subscriptions" (or account (pio-account-show))))
(defun pio-account-user-id        (&optional account) "Stable user UUID."       (gethash "user_id"       (or account (pio-account-show))))
(defun pio-account-expire-at      (&optional account) "Account expiry epoch."   (gethash "expire_at"     (or account (pio-account-show))))

(defun pio-account-username (&optional account)
  "Return the profile username."
  (when-let* ((profile (pio-account-profile account)))
    (gethash "username" profile)))

(defun pio-account-email (&optional account)
  "Return the profile email."
  (when-let* ((profile (pio-account-profile account)))
    (gethash "email" profile)))

(defun pio-account-fullname (&optional account)
  "Return `Firstname Lastname' from the profile, or nil."
  (when-let* ((profile (pio-account-profile account))
              (first   (gethash "firstname" profile))
              (last    (gethash "lastname"  profile)))
    (string-trim (format "%s %s" first last))))

;;; Dashboard

(defconst pio-buffer-name "*pio*"
  "Name of the dashboard buffer.
Named so users can target it from `display-buffer-alist'.")

(defun pio-monitor-at-point ()
  "Open the serial monitor for the device row at point.
Reads the `pio-device-port' text property on the current line.
Reuses an already-open monitor for the same port; buffer/window
lifecycle is left to the user."
  (interactive)
  (when-let ((port (get-text-property (point) 'pio-device-port)))
    (pio-device-monitor :port port)))
(put 'pio-monitor-at-point 'completion-predicate #'ignore)

(defvar pio-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map (kbd "RET") #'pio-monitor-at-point)
    (define-key map (kbd "r")   #'revert-buffer)
    map))

(with-eval-after-load 'evil
  (evil-define-key 'normal pio-mode-map
    (kbd "RET") #'pio-monitor-at-point
    (kbd "r")   #'revert-buffer))

(define-derived-mode pio-mode special-mode "pio"
  "Major mode for the `*pio*' dashboard buffer."
  (setq-local truncate-lines t))
(put 'pio-mode 'completion-predicate #'ignore)

(with-eval-after-load 'nerd-icons
  (add-to-list 'nerd-icons-mode-icon-alist
               '(pio-mode nerd-icons-sucicon "nf-seti-platformio"
                          :face nerd-icons-yellow)))

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
  "Update `mode-name' with core version and ACCOUNT username."
  (let ((version (plist-get (pio-core-version) :value))
        (user    (pio-account-username account)))
    (setq mode-name
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

(defun pio--render-profile (account)
  "Render ACCOUNT profile / packages / subscriptions into the current buffer.
Currently unwired from `pio--render' — kept for future re-enable."
  (let ((packages      (pio-account-packages      account))
        (subscriptions (pio-account-subscriptions account)))
    (insert (propertize "PROFILE\n" 'face 'vui-heading-2))
    (pio--field "username" (pio-account-username account))
    (pio--field "name"     (pio-account-fullname account))
    (pio--field "email"    (pio-account-email    account))
    (pio--field "user id"  (pio-account-user-id  account))
    (insert "\n")
    (insert (propertize (format "PACKAGES (%d)\n" (length packages))
                        'face 'vui-heading-2))
    (mapc #'pio--render-package packages)
    (insert "\n")
    (insert (propertize (format "SUBSCRIPTIONS (%s)\n"
                                (if subscriptions
                                    (number-to-string (length subscriptions))
                                  "none"))
                        'face 'vui-heading-2))))

(defconst pio--device-columns
  '(("SERIAL"      . 18)
    ("VID:PID"     . 10)
    ("PORT"        . 21)
    ("LOCATION"    .  8)
    ("DESCRIPTION" .  0))
  "Column (LABEL . WIDTH) for the dashboard's DEVICES table.
Width 0 = unpadded last column.")

(defun pio--render-device-row (cells face &optional port)
  "Render one row of CELLS, applying FACE (or nil).
When PORT is non-nil, tag the row with it as `pio-device-port'
so `pio-monitor-at-point' can find it."
  (let ((start (point)))
    (cl-loop for (_ . width) in pio--device-columns
             for i from 0
             for cell = (aref cells i)
             for padded = (if (zerop width) cell (string-pad cell width))
             do (insert (if face (propertize padded 'face face) padded))
             unless (eq i (1- (length pio--device-columns)))
               do (insert " "))
    (insert "\n")
    (when port
      (put-text-property start (point) 'pio-device-port port))))

(defun pio--render-device (entry)
  "Render one ENTRY (id + cell vector from `pio--device-list-entries').
The entry's id (port) is attached as a row text property."
  (pio--render-device-row (cadr entry) nil (car entry)))

(defun pio--render-device-header ()
  "Insert the muted column-header row above the device rows."
  (pio--render-device-row
   (vconcat (mapcar #'car pio--device-columns))
   'vui-muted))

(defun pio--render-devices ()
  "Render the DEVICES section using `pio--device-list-entries'."
  (let ((entries (pio--device-list-entries)))
    (insert (propertize (format "DEVICES (%d)\n" (length entries))
                        'face 'vui-heading-2))
    (pio--render-device-header)
    (mapc #'pio--render-device entries)))

(defun pio--render (account)
  "Render the dashboard into the current buffer.
ACCOUNT is still fetched for the modeline; the PROFILE/PACKAGES/SUBSCRIPTIONS
sections live in `pio--render-profile' and are temporarily unwired."
  (pio--set-mode-line account)
  (pio--render-devices)
  ;; (pio--render-profile account)  ; re-enable when ready
  )

(defun pio--revert (&rest _)
  "Refresh the `*pio*' buffer (bound as `revert-buffer-function')."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (pio--render (pio-account-show t))
    (goto-char (point-min))))

;;;###autoload
(defun pio ()
  "Open the `*pio*' dashboard showing the active PlatformIO account."
  (interactive)
  (let ((buffer (get-buffer-create pio-buffer-name)))
    (with-current-buffer buffer
      (pio-mode)
      (setq-local revert-buffer-function #'pio--revert)
      (pio--revert))
    (pop-to-buffer buffer)))

(provide 'platformio)

;;; platformio.el ends here
