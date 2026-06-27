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
;; TODO Platformio is ....
;; Commands:
;;   access    Manage resource access
;;   account   Manage PlatformIO account
;;   boards    Board Explorer
;;   check     Static Code Analysis
;;   ci        Continuous Integration
;;   debug     Unified Debugger
;;   device    Device manager & Serial/Socket monitor
;;   home      GUI to manage PIO
;;   org       Manage organizations
;;   pkg       Unified Package Manager
;;   project   Project Manager
;;   remote    Remote Development
;;   run       Run project targets (build, upload, clean, etc.)
;;   settings  Manage system settings
;;   system    Miscellaneous system commands
;;   team      Manage organization teams
;;   test      Unit Testing
;;   upgrade   Upgrade PlatformIO Core to the latest version
;;
;;; Code:

(require 'xdg)
(require 'json)
(require 'map)
(require 'pcase)

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
  (or pio-executable
    (executable-find "pio")
    (executable-find "platformio")
    "pio"))

(defun pio--detect-executables ()
  (let (results)
    (dolist (dir (split-string (or (getenv "PATH") "") path-separator t))
      (dolist (name '("pio" "platformio"))
        (let ((path (expand-file-name name dir)))
          (when (and (file-executable-p path)
                  (not (file-directory-p path)))
            (push path results)))))
    (delete-dups (nreverse results))))

(defvar pio--multiple-executables-warned nil)

(defun pio--warn-multiple-executables ()
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
  (file-exists-p
    (expand-file-name "platformio.ini" (or directory default-directory))))

(defun pio-root (&optional directory)
  (locate-dominating-file (or directory default-directory) "platformio.ini"))

(defun pio-in-project-p (&optional directory)
  (and (pio-root directory) t))

(defun pio-name (&optional project-root)
  (when-let ((root (or project-root (pio-root))))
    (file-name-nondirectory (directory-file-name root))))

(defun pio-config-file (&optional project-root)
  (when-let ((root (or project-root (pio-root))))
    (expand-file-name "platformio.ini" root)))

(defun pio-envs (&optional project-root)
  (when-let* ((ini (pio-config-file project-root))
               ((file-exists-p ini)))
    (with-temp-buffer
      (insert-file-contents ini)
      (let (envs)
        (goto-char (point-min))
        (while (re-search-forward "^\\[env:\\([^]]+\\)\\]" nil t)
          (push (match-string 1) envs))
        (nreverse envs)))))

(defun pio--read-key (section key &optional project-root)
  (when-let* ((ini (pio-config-file project-root))
               ((file-exists-p ini)))
    (with-temp-buffer
      (insert-file-contents ini)
      (goto-char (point-min))
      (when (re-search-forward (format "^\\[%s\\]" (regexp-quote section)) nil t)
        (let ((section-end (save-excursion
                             (if (re-search-forward "^\\[" nil t)
                               (match-beginning 0)
                               (point-max)))))
          (when (re-search-forward
                  (format "^\\s-*%s\\s-*=\\s-*\\(.+?\\)\\s-*$" (regexp-quote key))
                  section-end t)
            (match-string 1)))))))

(defun pio-default-envs (&optional project-root)
  (when-let ((value (or (getenv "PLATFORMIO_DEFAULT_ENVS")
                      (pio--read-key "platformio" "default_envs" project-root))))
    (split-string value "[ ,]+" t)))

(defun pio-env-board (env &optional project-root)
  (pio--read-key (format "env:%s" env) "board" project-root))

(defun pio-env-platform (env &optional project-root)
  (pio--read-key (format "env:%s" env) "platform" project-root))

(defun pio-env-framework (env &optional project-root)
  (pio--read-key (format "env:%s" env) "framework" project-root))

(defun pio-build-dir (&optional project-root)
  (or (getenv "PLATFORMIO_BUILD_DIR")
    (when-let ((root (or project-root (pio-root))))
      (expand-file-name ".pio" root))))

(defun pio--device-list (kind)
  (json-parse-string
    (shell-command-to-string
      (format "%s device list --%s --json-output" (pio--executable) kind))))

(defun pio-serial-devices ()
  (pio--device-list "serial"))

(defun pio-logical-devices ()
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
  (let ((hwid (gethash "hwid" device)))
    (or (null hwid) (string-empty-p hwid) (string= hwid "n/a"))))

(defun pio--device-excluded-p (device)
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
  (mapcar (lambda (dev)
            (let* ((port   (gethash "port" dev))
                   (desc   (gethash "description" dev))
                   (parsed (pio--parse-hwid (gethash "hwid" dev))))
              (list port
                    (vector
                     (propertize port 'face 'success)
                     (propertize (or (plist-get parsed :serial)   "") 'face 'warning)
                     (propertize (or (plist-get parsed :vid-pid)  "") 'face 'font-lock-constant-face)
                     (propertize (or (plist-get parsed :location) "") 'face 'font-lock-function-name-face)
                     (propertize (or desc "")                          'face 'font-lock-comment-face)))))
    (seq-remove #'pio--device-excluded-p (pio-serial-devices))))

(defun pio--device-list-refresh ()
  (setq tabulated-list-entries (pio--device-list-entries)))

(defun pio-device-list-monitor ()
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

(define-derived-mode pio-device-list-mode tabulated-list-mode "pio-device-list"
  "Major mode for the `pio-device-list' buffer."
  (setq tabulated-list-format
    [("Port"        24 t)
     ("SERIAL"      19 t)
     ("VID:PID"     10 t)
     ("LOCATION"    10 t)
     ("Description"  0 t)]
    tabulated-list-sort-key (cons "Port" nil))
  (add-hook 'tabulated-list-revert-hook #'pio--device-list-refresh nil t)
  (tabulated-list-init-header))
(put 'pio-device-list-mode 'completion-predicate #'ignore)

(defun pio-device-list ()
  (interactive)
  (let ((buffer (get-buffer-create "*pio-device-list*")))
    (with-current-buffer buffer
      (pio-device-list-mode)
      (pio--device-list-refresh)
      (tabulated-list-print))
    (pop-to-buffer buffer)))

(defvar pio--system-info-cache nil)

(defun pio-system-info ()
  (or pio--system-info-cache
    (progn
      (pio--warn-multiple-executables)
      (setq pio--system-info-cache
        (json-parse-string
          (shell-command-to-string
            (format "%s system info --json-output" (pio--executable))))))))

(defun pio-system-info-invalidate ()
  (interactive)
  (setq pio--system-info-cache nil
    pio--multiple-executables-warned nil))

(defun pio--system-info-field (key)
  (when-let* ((info (pio-system-info))
               (entry (gethash key info)))
    (list :title (gethash "title" entry)
      :value (gethash "value" entry))))

(defun pio-core-version        () (pio--system-info-field "core_version"))
(defun pio-python-version      () (pio--system-info-field "python_version"))
(defun pio-system              () (pio--system-info-field "system"))
(defun pio-platform            () (pio--system-info-field "platform"))
(defun pio-filesystem-encoding () (pio--system-info-field "filesystem_encoding"))
(defun pio-locale-encoding     () (pio--system-info-field "locale_encoding"))
(defun pio-core-dir            () (pio--system-info-field "core_dir"))
(defun pio-platformio-exe      () (pio--system-info-field "platformio_exe"))
(defun pio-python-exe          () (pio--system-info-field "python_exe"))
(defun pio-global-lib-nums     () (pio--system-info-field "global_lib_nums"))
(defun pio-dev-platform-nums   () (pio--system-info-field "dev_platform_nums"))
(defun pio-package-tool-nums   () (pio--system-info-field "package_tool_nums"))

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
  (pcase type
    (:number (string-to-number value))
    (:flag   (and (member (downcase value) '("yes" "true" "1")) t))
    (:list   (split-string value "[ ,]+" t))
    (_       value)))

(defun pio-env-monitor (env &optional project-root)
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
  (let* ((env-name (or (plist-get overrides :env) (car (pio-default-envs))))
          (profile  (alist-get (plist-get overrides :profile) pio-monitor-profiles))
          (env-settings (when env-name (pio-env-monitor env-name))))
    (map-merge 'plist (or env-settings ()) (or profile ()) overrides)))

(defun pio-monitor-command-args (settings)
  (mapcan (pcase-lambda (`(,key _ ,flag ,type))
            (when-let ((value (plist-get settings key)))
              (pcase type
                (:flag   (when value (list flag)))
                (:list   (mapcan (lambda (v) (list flag v)) value))
                (:number (list flag (number-to-string value)))
                (_       (list flag value)))))
    pio--monitor-spec))

(defun pio-monitor-command (&rest overrides)
  (append (list (pio--executable) "device" "monitor")
    (pio-monitor-command-args
      (apply #'pio-monitor-resolve overrides))))

(defun pio--monitor-buffer-name (settings)
  (format "*pio:monitor:%s*"
    (or (plist-get settings :port)
      (plist-get settings :profile)
      (plist-get settings :env)
      (car (pio-default-envs))
      "default")))

(defun pio-device-monitor (&rest overrides)
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
        (vterm)))))

(provide 'platformio)

;;; platformio.el ends here
