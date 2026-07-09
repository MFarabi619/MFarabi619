;;; process-compose.el --- Process Compose integration  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/process-compose
;; Keywords: tools, processes
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (vui "0.1") (nerd-icons "0.1"))

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
;; Client front-end for Process Compose: a supervisor daemon owns the
;; processes (they outlive Emacs), a monitor stream pushes state changes,
;; and the dashboard renders them TUI-style with a following log pane.
;;
;;; Code:

(require 'ansi-color)
(require 'cl-lib)
(require 'face-remap)
(require 'map)
(require 'nerd-icons)
(require 'seq)
(require 'subr-x)
(require 'vui)
(require 'vui-components)

(declare-function evil-define-key* "evil-core" (state keymap &rest bindings))

(defconst process-compose--package-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory this library was loaded from; anchors the bundled fixtures.")

;;; Customization

(defgroup process-compose ()
  "Process Compose integration."
  :prefix "process-compose-"
  :group 'tools)

(defcustom process-compose-executable "process-compose"
  "Name or path of the Process Compose binary."
  :type 'string
  :group 'process-compose)

(defcustom process-compose-processes
  '((:name "pc-log" :namespace "debug" :display-name "pc log"
     :command "tail -F -n100 process-compose-${USER}.log"
     :config ((working_dir . "/tmp"))))
  "Process declarations: the Lisp source of truth the daemon is spawned from.
Each entry is a plist of :name (unique handle), :namespace, :display-name,
:command, optional :disabled, and an optional :config alist of raw
snake_case process keys.  The sole default is the daemon's own log
tail: package mechanism, not project policy.  Project processes come
from declarers (microvisor's task registry, ros2) or user setq."
  :type '(repeat plist)
  :group 'process-compose)

(defcustom process-compose-hidden-namespaces '("debug")
  "Namespaces hidden from the board until toggled visible."
  :type '(repeat string)
  :group 'process-compose)

(defcustom process-compose-visible-columns
  '("●" "PID" "NAME" "NAMESPACE" "STATUS" "AGE" "HEALTH"
    "MEM" "CPU" "RESTARTS" "EXIT CODE")
  "Headers of the table columns to display, for narrow side-window layouts.
Order is fixed by the table; this only selects.  NAME is always shown:
its cells carry the row identity that navigation and actions rely on."
  :type '(repeat string)
  :group 'process-compose)

(defcustom process-compose-log-window-height 0.5
  "Fraction of the frame given to the log pane below the table."
  :type 'number
  :group 'process-compose)

(defcustom process-compose-metrics-refresh-seconds 2
  "Seconds between metric polls while any process is active.
The monitor stream only pushes status transitions, so live PID, MEM,
CPU, and AGE come from folding `process list' at this cadence, exactly
as the TUI does."
  :type 'number
  :group 'process-compose)

(defcustom process-compose-log-tail-length 200
  "Lines of history requested when a log pane opens."
  :type 'natnum
  :group 'process-compose)

(defcustom process-compose-namespace-icons
  '(("loco"     "nf-weather-train"   nerd-icons-orange)
    ("web"      "nf-fa-dna"          nerd-icons-blue)
    ("firmware" "nf-md-chip"         nerd-icons-purple)
    ("microtop" "nf-md-monitor"      nerd-icons-lgreen)
    ("tui"      "nf-md-application"  nerd-icons-orange)
    ("nix"      "nf-md-nix"          nerd-icons-lblue)
    ("ceratina" "nf-seti-platformio" nerd-icons-yellow)
    ("emacs"    "nf-custom-emacs"    nerd-icons-purple)
    ("debug"    "nf-md-bug"          nerd-icons-silver))
  "Glyph shown beside each namespace; entries are (NAMESPACE ICON FACE)."
  :type '(repeat (list string string symbol))
  :group 'process-compose)

(defface process-compose-table-header
  '((t :inherit bold :foreground "#D0B344"))
  "Table header face, matching the TUI Monokai theme's `headerFgColor'."
  :group 'process-compose)

(defface process-compose-scheduled
  '((t :inherit nerd-icons-lblue))
  "Face for cron processes waiting on the clock."
  :group 'process-compose)

(defface process-compose-terminating
  '((t :inherit nerd-icons-purple))
  "Face for processes shutting down."
  :group 'process-compose)

(defface process-compose-pending
  '((t :inherit nerd-icons-lsilver))
  "Face for processes queued behind a dependency: dim white, above muted."
  :group 'process-compose)

(defface process-compose-attention
  '((t :inherit nerd-icons-orange))
  "Face for noteworthy-but-healthy cells: restart counts, hot resources."
  :group 'process-compose)

(defcustom process-compose-cpu-thresholds '(50.0 . 85.0)
  "CPU percentages above which a live cell turns attention, then error."
  :type '(cons number number)
  :group 'process-compose)

(defcustom process-compose-mem-thresholds
  (cons (* 1024 1024 1024) (* 4 1024 1024 1024))
  "Memory bytes above which a live cell turns attention, then error."
  :type '(cons natnum natnum)
  :group 'process-compose)

;;; Process state model

(defconst process-compose-buffer-name "*process-compose*"
  "Name of the dashboard buffer.")

(defconst process-compose--daemon-buffer-name " *process-compose-daemon*"
  "Name of the hidden buffer collecting the spawned daemon's output.")

(defvar process-compose--states nil
  "Current list of process state hashes rendered by the dashboard.")

(defconst process-compose--transitional-statuses
  '("Launching" "Launched" "Restarting" "Terminating")
  "Statuses between steady states; rendered with a spinner.")

(defvar process-compose-after-update-hook nil
  "Hook run after a monitor burst updates `process-compose--states'.
Other packages rendering process state hang their re-render here.")

(defun process-compose-state (name)
  "Return the current state hash of the process NAME, or nil."
  (seq-find (lambda (state) (equal (gethash "name" state) name))
            process-compose--states))

;;; Daemon and monitor

(defvar process-compose--daemon-process nil
  "The supervisor daemon running as an Emacs child process, if we spawned it.")

(defvar process-compose--monitor-process nil
  "The `process monitor' subprocess streaming state events.")

(defvar process-compose--monitor-fragment ""
  "Partial line buffered between monitor output chunks.")

(defvar process-compose--metrics-timer nil
  "Timer folding `process list' snapshots while processes are active.")

(defvar process-compose--project nil
  "Expanded root of the project this session manages.
One Emacs session drives one project; `process-compose-ensure' enforces
it, and the socket path derives from it, so async callbacks can never
address a different repo's daemon.")

(defun process-compose--socket-path ()
  "Return the daemon socket path derived from the managed project root.
Deliberately ignores PC_SOCKET_PATH: attaching to a foreign daemon would
let `process-compose-reconcile' delete processes we never declared."
  (format "/tmp/process-compose-%s-%s.sock" (user-login-name)
          (substring (md5 (or process-compose--project
                              (expand-file-name
                               (process-compose--project-root))))
                     0 8)))

(defun process-compose--project-root ()
  "Return the project root, anchored on the enclosing Git repository."
  (or (locate-dominating-file default-directory ".git")
      (user-error "Not inside a Git project: %s" default-directory)))

(defun process-compose--daemon-log-file ()
  "Return the daemon's internal log path, pinned via PC_LOG_FILE at spawn."
  (format "/tmp/process-compose-%s.log" (user-login-name)))

(defun process-compose--daemon-log-excerpt (name)
  "Return the last daemon-log lines mentioning the process NAME."
  (let ((log-file (process-compose--daemon-log-file)))
    (when (file-readable-p log-file)
      (with-temp-buffer
        (insert-file-contents log-file)
        (let (lines)
          (goto-char (point-min))
          (while (search-forward name nil t)
            (push (buffer-substring-no-properties (line-beginning-position)
                                                  (line-end-position))
                  lines)
            (forward-line 1))
          (last (nreverse lines) 5))))))

(defun process-compose--daemon-reachable-p ()
  "Non-nil when the project's daemon socket answers.
Socket files outlive crashed daemons, so existence alone proves nothing:
trust our own live child, otherwise probe with a cheap client call."
  (and (file-exists-p (process-compose--socket-path))
       (or (process-live-p process-compose--daemon-process)
           (eq 0 (call-process process-compose-executable nil nil nil
                               "project" "state"
                               "--unix-socket"
                               (process-compose--socket-path))))))

(defvar process-compose--config-keys nil
  "Cached ProcessConfig key list, loaded from the bundled upstream schema.")

(defun process-compose--config-keys ()
  "Return the legal process config keys per the bundled upstream schema."
  (or process-compose--config-keys
      (setq process-compose--config-keys
            (hash-table-keys
             (map-nested-elt
              (with-temp-buffer
                (insert-file-contents
                 (expand-file-name "fixtures/process-compose-schema.json"
                                   process-compose--package-directory))
                (json-parse-string (buffer-string)))
              '("$defs" "ProcessConfig" "properties"))))))

(defun process-compose--project-config (project-name)
  "Serialise the declarations into a project document named PROJECT-NAME.
Processes run from the monorepo root (the daemon's spawn directory)
unless a declaration's :config carries an explicit working_dir.
Config keys are checked against the bundled upstream schema, naming
typos here instead of at daemon spawn."
  (let ((processes (make-hash-table :test #'equal)))
    (dolist (declaration process-compose-processes)
      (let ((process-config (make-hash-table :test #'equal)))
        (when-let* ((namespace (plist-get declaration :namespace)))
          (puthash "namespace" namespace process-config))
        (puthash "command" (plist-get declaration :command) process-config)
        (when (plist-get declaration :disabled)
          (puthash "disabled" t process-config))
        (dolist (config-entry (plist-get declaration :config))
          (let ((key (symbol-name (car config-entry)))
                (value (cdr config-entry)))
            (unless (member key (process-compose--config-keys))
              (user-error "Unknown config key %s in declaration %s"
                          key (plist-get declaration :name)))
            (puthash key
                     (if (equal key "working_dir")
                         (expand-file-name value)
                       value)
                     process-config)))
        (puthash (plist-get declaration :name) process-config processes)))
    (json-serialize
     `((version . "0.5")
       (name . ,project-name)
       (is_strict . t)
       (ordered_shutdown . t)
       (log_length . 3000)
       (environment . ["CLICOLOR_FORCE=1" "FORCE_COLOR=1"
                       "TERM=xterm-256color"])
       (processes . ,processes)))))

(defun process-compose--project-name (root)
  "Return the project name for ROOT: its directory name."
  (file-name-nondirectory (directory-file-name root)))

(defun process-compose--write-config (project-name)
  "Write the PROJECT-NAME config to its stable per-project path.
Reusing one path per project keeps repeated spawns and reconciles from
littering the temp directory."
  (let ((config-file (expand-file-name
                      (format "process-compose-%s.yaml" project-name)
                      temporary-file-directory)))
    (with-temp-file config-file
      (insert (process-compose--project-config project-name)))
    config-file))

(defun process-compose--await-socket ()
  "Block briefly until the daemon's socket appears, or signal an error."
  (let ((tries 0))
    (while (and (not (file-exists-p (process-compose--socket-path)))
                (process-live-p process-compose--daemon-process)
                (< tries 50))
      (cl-incf tries)
      (accept-process-output nil 0.1)))
  (unless (file-exists-p (process-compose--socket-path))
    (error "Daemon failed to start; see buffer %s"
           process-compose--daemon-buffer-name)))

(defun process-compose--ensure-daemon ()
  "Spawn the supervisor as an Emacs child unless its daemon answers.
A socket file whose daemon is gone is deleted so the spawn can rebind it."
  (let ((socket (process-compose--socket-path)))
    (unless (process-compose--daemon-reachable-p)
      (when (file-exists-p socket)
        (delete-file socket))
      (let* ((default-directory (process-compose--project-root))
           (project-name (process-compose--project-name default-directory))
           (process-environment
            (cons (concat "PC_LOG_FILE=" (process-compose--daemon-log-file))
                  process-environment)))
      (setq process-compose--daemon-process
            (make-process
             :name "process-compose-daemon"
             :buffer process-compose--daemon-buffer-name
             :command (list process-compose-executable "up"
                            "-f" (process-compose--write-config project-name)
                            "-t=false" "--keep-project"
                            "--unix-socket" socket)
             :connection-type 'pipe
             :noquery t
             :sentinel
             (lambda (daemon event)
               (unless (process-live-p daemon)
                 (message "process-compose daemon exited: %s"
                          (string-trim event)))))))
      (process-compose--await-socket))))

(defun process-compose--apply-state (state)
  "Insert or replace STATE in `process-compose--states' by process name."
  (let* ((name (gethash "name" state))
         (existing (seq-find (lambda (candidate)
                               (equal (gethash "name" candidate) name))
                             process-compose--states)))
    (setq process-compose--states
          (if existing
              (mapcar (lambda (candidate)
                        (if (eq candidate existing) state candidate))
                      process-compose--states)
            (append process-compose--states (list state))))))

(defun process-compose--fold-monitor-line (line)
  "Fold one monitor stream LINE into the states; non-nil when it applied."
  (if-let* ((frame (ignore-errors
                     (json-parse-string line :false-object nil)))
            (state (gethash "state" frame)))
      (progn (process-compose--apply-state state) t)
    (message "process-compose monitor: unparseable line %S" line)
    nil))

(defun process-compose--monitor-filter (_monitor chunk)
  "Fold monitor CHUNK line by line, rendering once for the whole burst."
  (setq process-compose--monitor-fragment
        (concat process-compose--monitor-fragment chunk))
  (let ((any-applied-p nil))
    (while (string-match "\n" process-compose--monitor-fragment)
      (let ((line (substring process-compose--monitor-fragment 0
                             (match-beginning 0))))
        (setq process-compose--monitor-fragment
              (substring process-compose--monitor-fragment (match-end 0)))
        (unless (string-empty-p line)
          (when (process-compose--fold-monitor-line line)
            (setq any-applied-p t)))))
    (when any-applied-p
      (process-compose--publish-update))))

(defun process-compose--publish-update ()
  "Re-render the dashboard, reapply the log pane, and notify subscribers."
  (when-let* ((dashboard-buffer (get-buffer process-compose-buffer-name)))
    (with-current-buffer dashboard-buffer
      (process-compose--rerender)
      (process-compose--follow-log-window)))
  (run-hooks 'process-compose-after-update-hook))

(defun process-compose--any-process-active-p ()
  "Non-nil while any process is running or between steady states."
  (seq-some (lambda (state)
              (or (gethash "is_running" state)
                  (member (gethash "status" state)
                          (cons "Running"
                                process-compose--transitional-statuses))))
            process-compose--states))

(defun process-compose--refresh-metrics ()
  "Fold a fresh `process list' snapshot to keep the live columns current."
  (when (and (process-live-p process-compose--monitor-process)
             (process-compose--any-process-active-p))
    (let ((output-buffer (generate-new-buffer " *process-compose-metrics*")))
      (make-process
       :name "process-compose-metrics"
       :buffer output-buffer
       :command (list process-compose-executable "process" "list" "-o" "json"
                      "--unix-socket" (process-compose--socket-path))
       :connection-type 'pipe
       :noquery t
       :sentinel
       (lambda (list-process _event)
         (unless (process-live-p list-process)
           (unwind-protect
               (when-let* (((zerop (process-exit-status list-process)))
                           (states
                            (ignore-errors
                              (json-parse-string
                               (with-current-buffer output-buffer
                                 (buffer-string))
                               :false-object nil))))
                 (mapc #'process-compose--apply-state (append states nil))
                 (process-compose--publish-update))
             (kill-buffer output-buffer))))))))

(defun process-compose--monitor-sentinel (monitor event)
  "Reconnect after MONITOR dies with EVENT, unless we killed it."
  (unless (process-live-p monitor)
    (when process-compose--metrics-timer
      (cancel-timer process-compose--metrics-timer)
      (setq process-compose--metrics-timer nil))
    (unless (process-get monitor 'process-compose-deliberate)
      (message "process-compose monitor exited: %s" (string-trim event))
      (when (process-compose--daemon-reachable-p)
        (run-with-timer 2 nil #'process-compose--ensure-monitor)))))

(defun process-compose--await-first-snapshot ()
  "Wait briefly for the monitor's first snapshot."
  (let ((tries 0))
    (while (and (null process-compose--states)
                (process-live-p process-compose--monitor-process)
                (< tries 40))
      (cl-incf tries)
      (accept-process-output process-compose--monitor-process 0.05))))

(defun process-compose--ensure-monitor ()
  "Start the monitor stream unless it is already live."
  (unless (process-live-p process-compose--monitor-process)
    (process-compose--start-monitor)
    (process-compose--await-first-snapshot)))

(defun process-compose-ensure ()
  "Ensure the current project's daemon and monitor stream are both up.
Signals a `user-error' when this session already manages another project."
  (let ((root (expand-file-name (process-compose--project-root))))
    (when (and process-compose--project
               (not (equal root process-compose--project)))
      (user-error "Session already manages %s; run process-compose-down there first"
                  process-compose--project))
    (setq process-compose--project root))
  (process-compose--ensure-daemon)
  (process-compose--ensure-monitor))

(defun process-compose--start-monitor ()
  "Start the state stream that feeds the dashboard, replacing a live one."
  (when (process-live-p process-compose--monitor-process)
    (process-put process-compose--monitor-process 'process-compose-deliberate t)
    (kill-process process-compose--monitor-process))
  (setq process-compose--states nil
        process-compose--monitor-fragment "")
  (setq process-compose--monitor-process
        (make-process
         :name "process-compose-monitor"
         :buffer nil
         :command (list process-compose-executable "process" "monitor"
                        "-o" "json"
                        "--unix-socket" (process-compose--socket-path))
         :connection-type 'pipe
         :noquery t
         :stderr (get-buffer-create " *process-compose-monitor-stderr*")
         :filter #'process-compose--monitor-filter
         :sentinel #'process-compose--monitor-sentinel))
  (when process-compose--metrics-timer
    (cancel-timer process-compose--metrics-timer))
  (setq process-compose--metrics-timer
        (run-with-timer process-compose-metrics-refresh-seconds
                        process-compose-metrics-refresh-seconds
                        #'process-compose--refresh-metrics)))

;;; Status classification

(defun process-compose-declare (declaration)
  "Insert or replace DECLARATION in `process-compose-processes' by :name."
  (let ((name (plist-get declaration :name)))
    (setq process-compose-processes
          (append (seq-remove (lambda (existing)
                                (equal (plist-get existing :name) name))
                              process-compose-processes)
                  (list declaration)))))

(defun process-compose-reconcile ()
  "Push the current declarations into a running daemon."
  (when (process-compose--daemon-reachable-p)
    (process-compose--run-command
     "project" "update" "-f"
     (process-compose--write-config
      (process-compose--project-name (process-compose--project-root))))))

(defun process-compose--exit-code-success-p (state)
  "Return non-nil when STATE's exit code is in `success_exit_codes' (default 0)."
  (memql (gethash "exit_code" state 0)
         (or (append (gethash "success_exit_codes" state) nil) '(0))))

(defun process-compose--log-worthy-p (state)
  "Non-nil when STATE has output worth a log pane.
Judged by status alone: the daemon emits transition frames before the
pid and is_running are populated, so those fields cannot be trusted."
  (not (member (gethash "status" state)
               '("Disabled" "Foreground" "Pending" "Skipped"))))

(defun process-compose--scheduled-p (state)
  "Return non-nil when STATE is a cron process waiting for its next run."
  (and (gethash "next_run_time" state)
       (not (gethash "is_running" state))))

(defun process-compose--status-class (state)
  "Classify STATE into a status-class symbol."
  (if (process-compose--scheduled-p state)
      'scheduled
    (pcase (gethash "status" state)
      ((or "Running" "Launching" "Launched")
       (cond
        ((equal (gethash "is_ready" state) "Not Ready") 'running-not-ready)
        ((gethash "is_elevated" state) 'running-elevated)
        (t 'running)))
      ("Pending" 'pending)
      ("Restarting" 'restarting)
      ("Terminating" 'terminating)
      ((or "Disabled" "Foreground") 'disabled)
      ("Skipped" 'skipped)
      ("Error" 'failed)
      ("Completed" (if (process-compose--exit-code-success-p state)
                       'completed
                     'failed))
      (_ 'running))))

(defun process-compose--status-face (status-class)
  "Return the face colouring a row for STATUS-CLASS."
  (pcase status-class
    ((or 'running 'completed)  'vui-success)
    ((or 'running-not-ready 'running-elevated 'skipped) 'vui-warning)
    ('failed                   'vui-error)
    ('pending                  'process-compose-pending)
    ('disabled                 'vui-muted)
    ('restarting               'process-compose-attention)
    ('terminating              'process-compose-terminating)
    ('scheduled                'process-compose-scheduled)
    (_                         'default)))

(defun process-compose--display-name (name)
  "Return the declared display name for the process NAME, or NAME itself."
  (or (plist-get (seq-find (lambda (declaration)
                             (equal (plist-get declaration :name) name))
                           process-compose-processes)
                 :display-name)
      name))

(defun process-compose--display-process-status (state)
  "Return STATE's STATUS column word."
  (cond
   ((process-compose--scheduled-p state) "Scheduled")
   ((and (equal (gethash "status" state) "Completed")
         (not (process-compose--exit-code-success-p state)))
    "Failed")
   (t (gethash "status" state))))

;;; Column formatting

(defun process-compose--byte-count-iec (bytes)
  "Format BYTES with one decimal in IEC units; sub-MiB still renders in MiB."
  (let ((mib (* 1024 1024)))
    (if (< bytes mib)
        (format "%.1f MiB" (/ bytes 1.0 mib))
      (let ((divisor 1024)
            (exponent 0)
            (quotient (/ bytes 1024)))
        (while (>= quotient 1024)
          (setq divisor (* divisor 1024)
                exponent (1+ exponent)
                quotient (/ quotient 1024)))
        (format "%.1f %ciB" (/ bytes 1.0 divisor) (aref "KMGTPE" exponent))))))

(defun process-compose--str-for-mem (mem running-p)
  "Render MEM for the MEM column when RUNNING-P."
  (cond ((not running-p) "-")
        ((< mem 0) "unknown")
        ((= mem 0) "-")
        (t (process-compose--byte-count-iec mem))))

(defun process-compose--str-for-cpu (cpu running-p)
  "Render CPU for the CPU column when RUNNING-P."
  (cond ((not running-p) "-")
        ((< cpu 0) "unknown")
        (t (format "%.1f%%" cpu))))

(defun process-compose--threshold-face (value thresholds fallback)
  "Return FALLBACK, attention, or error as VALUE crosses THRESHOLDS."
  (cond ((>= value (cdr thresholds)) 'vui-error)
        ((>= value (car thresholds)) 'process-compose-attention)
        (t fallback)))

(defun process-compose--str-for-exit-code (state)
  "Render STATE's EXIT CODE column."
  (let ((exit-code (gethash "exit_code" state 0)))
    (cond
     ((and (gethash "is_running" state) (eql exit-code 0)) "-")
     ((member (gethash "status" state) '("Disabled" "Pending" "Foreground")) "-")
     (t (number-to-string exit-code)))))

;;; Rendering

(defun process-compose--icon (icon-name face)
  "Return nerd-icon ICON-NAME rendered in FACE."
  (funcall
   (cond
    ((string-prefix-p "nf-seti-"    icon-name) #'nerd-icons-sucicon)
    ((string-prefix-p "nf-custom-"  icon-name) #'nerd-icons-sucicon)
    ((string-prefix-p "nf-dev-"     icon-name) #'nerd-icons-devicon)
    ((string-prefix-p "nf-fa-"      icon-name) #'nerd-icons-faicon)
    ((string-prefix-p "nf-cod-"     icon-name) #'nerd-icons-codicon)
    ((string-prefix-p "nf-oct-"     icon-name) #'nerd-icons-octicon)
    ((string-prefix-p "nf-weather-" icon-name) #'nerd-icons-wicon)
    (t #'nerd-icons-mdicon))
   icon-name :face face))

(defconst process-compose--spinner-frames ["⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷"]
  "Braille frames animated for transitional processes.")

(defconst process-compose--spinner-frames-per-second 8
  "Spinner animation rate in frames per second.")

(defconst process-compose--spinner-refresh-seconds 0.1
  "Seconds between dashboard re-renders while any spinner is animating.")

(defun process-compose--spinner ()
  "Return the current spinner frame, derived from the wall clock."
  (aref process-compose--spinner-frames
        (mod (truncate (* process-compose--spinner-frames-per-second (float-time)))
             (length process-compose--spinner-frames))))

(defun process-compose--namespace-cell (namespace row-face)
  "Return NAMESPACE in ROW-FACE, wrapped by its registered glyph on both sides."
  (let ((icon-spec (cdr (assoc namespace process-compose-namespace-icons))))
    (if icon-spec
        (let ((icon (process-compose--icon (nth 0 icon-spec) (nth 1 icon-spec))))
          (concat icon " " (propertize namespace 'face row-face) " " icon))
      (propertize namespace 'face row-face))))

(defun process-compose--gutter-icon (state status-class)
  "Return the gutter glyph for STATE with STATUS-CLASS."
  (cond
   ((member (gethash "status" state) process-compose--transitional-statuses)
    (process-compose--spinner))
   ((and (gethash "is_elevated" state) (gethash "is_running" state)) "▲")
   ((eq status-class 'failed) "✘")
   ((eq status-class 'disabled) "◯")
   (t "●")))

(defvar process-compose--show-hidden-namespaces nil
  "Non-nil when hidden namespaces are toggled visible.")

(defun process-compose--sorted-states ()
  "Return the visible states ordered by namespace, then name."
  (sort (if process-compose--show-hidden-namespaces
            (copy-sequence process-compose--states)
          (seq-remove (lambda (state)
                        (member (gethash "namespace" state)
                                process-compose-hidden-namespaces))
                      process-compose--states))
        (lambda (left right)
          (let ((left-namespace (or (gethash "namespace" left) ""))
                (right-namespace (or (gethash "namespace" right) "")))
            (if (string= left-namespace right-namespace)
                (string< (gethash "name" left) (gethash "name" right))
              (string< left-namespace right-namespace))))))

(defun process-compose--row (state)
  "Return the vui table row for STATE, one cell per TUI column."
  (let* ((status-class (process-compose--status-class state))
         (row-face (process-compose--status-face status-class))
         (running-p (and (gethash "is_running" state) t))
         (name (gethash "name" state))
         (restarts (gethash "restarts" state 0)))
    (process-compose--visible-cells
     (list
     (vui-text (process-compose--gutter-icon state status-class) :face row-face)
     (vui-text (number-to-string (gethash "pid" state 0)) :face row-face)
     (vui-text (propertize (process-compose--display-name name) 'face row-face)
       'process-compose-name name)
     (vui-text (process-compose--namespace-cell
                (or (gethash "namespace" state) "default") row-face))
     (vui-text (process-compose--display-process-status state) :face row-face)
     (vui-text (gethash "system_time" state "-") :face row-face)
     (vui-text (gethash "is_ready" state "-") :face row-face)
     (vui-text (process-compose--str-for-mem (gethash "mem" state 0) running-p)
       :face (if running-p
                 (process-compose--threshold-face
                  (gethash "mem" state 0) process-compose-mem-thresholds
                  row-face)
               row-face))
     (vui-text (process-compose--str-for-cpu (gethash "cpu" state 0) running-p)
       :face (if running-p
                 (process-compose--threshold-face
                  (gethash "cpu" state 0) process-compose-cpu-thresholds
                  row-face)
               row-face))
     (vui-text (if (> restarts 0) (number-to-string restarts) "-")
       :face (if (> restarts 0) 'process-compose-attention row-face))
      (vui-text (process-compose--str-for-exit-code state)
        :face row-face)))))

(defconst process-compose--columns
  '((:header "●"         :width 2)
    (:header "PID"       :width 6)
    (:header "NAME"      :width 20 :truncate t)
    (:header "NAMESPACE" :width 14)
    (:header "STATUS"    :width 11)
    (:header "AGE"       :width 7)
    (:header "HEALTH"    :width 10)
    (:header "MEM"       :width 10)
    (:header "CPU"       :width 6)
    (:header "RESTARTS"  :width 8)
    (:header "EXIT CODE" :width 9))
  "Column specs for the process table, in the TUI's order.")

(defun process-compose--column-visible-p (column)
  "Non-nil when COLUMN's header is selected in the visible set."
  (or (equal (plist-get column :header) "NAME")
      (member (plist-get column :header) process-compose-visible-columns)))

(defun process-compose--visible-cells (cells)
  "Return the row CELLS filtered to the visible columns."
  (cl-mapcan (lambda (column cell)
               (when (process-compose--column-visible-p column)
                 (list cell)))
             process-compose--columns cells))

(vui-defcomponent process-compose-dashboard ()
  "Full-window dashboard mirroring the Process Compose TUI's process table."
  :render
  (let ((any-transitional-p
         (seq-some (lambda (state)
                     (member (gethash "status" state)
                             process-compose--transitional-statuses))
                   process-compose--states)))
    (vui-use-effect (any-transitional-p)
      (when any-transitional-p
        (let ((timer (run-with-timer process-compose--spinner-refresh-seconds
                                     process-compose--spinner-refresh-seconds
                                     (vui-with-async-context
                                      (process-compose--rerender)))))
          (lambda () (cancel-timer timer)))))
    (vui-table
     :header-face 'process-compose-table-header
     :columns (seq-filter #'process-compose--column-visible-p
                          process-compose--columns)
     :rows (mapcar #'process-compose--row
                   (process-compose--sorted-states)))))

;;; Commands

(defun process-compose--row-name-at-point ()
  "Return the process name carried by the current line, or nil."
  (let ((line-start (line-beginning-position)))
    (or (get-text-property line-start 'process-compose-name)
        (get-text-property
         (next-single-property-change
          line-start 'process-compose-name nil (line-end-position))
         'process-compose-name))))

(defun process-compose--state-at-point ()
  "Return the process state named on the current row, or nil."
  (when-let* ((name (process-compose--row-name-at-point)))
    (process-compose-state name)))

(defun process-compose--move-row (direction)
  "Move point to the next process row in DIRECTION, staying put at the edges."
  (let ((origin (point)))
    (while (and (zerop (forward-line direction))
                (not (process-compose--row-name-at-point))))
    (if (process-compose--row-name-at-point)
        (beginning-of-line)
      (goto-char origin))))

(defun process-compose-next-row ()
  "Move to the next process row."
  (interactive nil process-compose-mode)
  (process-compose--move-row 1))

(defun process-compose-previous-row ()
  "Move to the previous process row."
  (interactive nil process-compose-mode)
  (process-compose--move-row -1))

(defun process-compose--require-name-at-point ()
  "Return the process name at point or signal a `user-error'."
  (or (process-compose--row-name-at-point)
      (user-error "No process on this line")))

(defun process-compose--mode-line ()
  "Render the TUI's stats block as a mode line: processes, RAM, CPU."
  (let* ((total-count (length process-compose--states))
         (running-states
          (seq-filter (lambda (state) (gethash "is_running" state))
                      process-compose--states))
         (running-count (length running-states))
         (memory (apply #'+ (mapcar (lambda (state) (gethash "mem" state 0))
                                    running-states)))
         (cpu (apply #'+ (mapcar (lambda (state) (gethash "cpu" state 0))
                                 running-states)))
         (count-face (if running-states 'vui-success 'vui-muted)))
    (replace-regexp-in-string
     "%" "%%"
     (concat " " (process-compose--icon "nf-md-fire" 'nerd-icons-orange)
             " "
             (process-compose--icon "nf-md-play" count-face)
             " " (propertize (format "%d/%d" running-count total-count)
                             'face count-face)
             "  " (process-compose--icon "nf-md-memory" 'vui-muted)
             " " (process-compose--str-for-mem memory (and running-states t))
             "  " (process-compose--icon "nf-oct-cpu" 'vui-muted)
             " " (format "%.1f%%" cpu)))))

(defvar-local process-compose--selection-bar-cookie nil
  "Face-remap cookie for the current selection bar tint.")

(defun process-compose--update-selection-bar ()
  "Tint the selection bar with the selected row's status colour."
  (when hl-line-mode
    (when process-compose--selection-bar-cookie
      (face-remap-remove-relative process-compose--selection-bar-cookie))
    (setq process-compose--selection-bar-cookie
          (face-remap-add-relative
           'hl-line
           (if-let* ((state (process-compose--state-at-point))
                     (row-color (face-foreground
                                 (process-compose--status-face
                                  (process-compose--status-class state))
                                 nil t)))
               (list :background row-color
                     :foreground (face-background 'default nil t)
                     :extend t)
             '(:extend t))))))

(defun process-compose--rerender ()
  "Re-render synchronously and restore the selection bar."
  (vui-flush-sync)
  (when hl-line-mode
    (process-compose--update-selection-bar)
    (hl-line-highlight)))

(defun process-compose-refresh ()
  "Restart the state stream and re-render from a fresh snapshot."
  (interactive nil process-compose-mode)
  (process-compose--start-monitor)
  (process-compose--await-first-snapshot)
  (process-compose--rerender))

(defun process-compose--run-command (&rest args)
  "Run the client with ARGS against the session socket, reporting failures."
  (let ((output-buffer (generate-new-buffer " *process-compose-command*")))
    (make-process
     :name "process-compose-command"
     :buffer output-buffer
     :command (append (list process-compose-executable)
                      args
                      (list "--unix-socket" (process-compose--socket-path)))
     :connection-type 'pipe
     :noquery t
     :sentinel
     (lambda (command-process _event)
       (unless (process-live-p command-process)
         (unwind-protect
             (unless (zerop (process-exit-status command-process))
               (message "process-compose: %s"
                        (ansi-color-filter-apply
                         (string-trim
                          (with-current-buffer output-buffer
                            (buffer-string))))))
           (kill-buffer output-buffer)))))))

(defun process-compose-toggle-hidden-namespaces ()
  "Toggle visibility of `process-compose-hidden-namespaces' rows."
  (interactive nil process-compose-mode)
  (setq process-compose--show-hidden-namespaces
        (not process-compose--show-hidden-namespaces))
  (process-compose--rerender))

(defun process-compose-down ()
  "Stop every process, shut the daemon down, and release the session."
  (interactive nil process-compose-mode)
  (process-compose--run-command "down")
  (setq process-compose--project nil))

(defun process-compose-quit ()
  "Quit the dashboard, closing the log pane and its stream with it."
  (interactive nil process-compose-mode)
  (process-compose--close-log-window)
  (quit-window))

(defun process-compose-start-process (name)
  "Ask the daemon to start the process NAME."
  (process-compose--run-command "process" "start" name))

(defun process-compose-stop-process (name)
  "Ask the daemon to stop the process NAME."
  (process-compose--run-command "process" "stop" name))

(defun process-compose-restart-process (name)
  "Ask the daemon to restart the process NAME."
  (process-compose--run-command "process" "restart" name))

(defun process-compose-start-at-point ()
  "Start the process at point."
  (interactive nil process-compose-mode)
  (process-compose-start-process
   (process-compose--require-name-at-point)))

(defun process-compose-stop-at-point ()
  "Stop the process at point."
  (interactive nil process-compose-mode)
  (process-compose-stop-process
   (process-compose--require-name-at-point)))

(defun process-compose-restart-at-point ()
  "Restart the process at point."
  (interactive nil process-compose-mode)
  (process-compose-restart-process
   (process-compose--require-name-at-point)))

;;; Log pane

(defvar-local process-compose-log--stream nil
  "The `process logs' subprocess feeding this buffer.")

(defun process-compose-log--kill-stream ()
  "Stop the buffer's log stream; idempotent `kill-buffer-hook' entry."
  (when (process-live-p process-compose-log--stream)
    (delete-process process-compose-log--stream)))

(define-derived-mode process-compose-log-mode special-mode "process-compose-log-mode"
  "Major mode for a process's log pane."
  (font-lock-mode 1)
  (compilation-minor-mode 1))
(put 'process-compose-log-mode 'completion-predicate #'ignore)

(defun process-compose--log-insert (log-buffer chunk)
  "Append CHUNK to LOG-BUFFER through ansi rendering, keeping tails pinned."
  (when (buffer-live-p log-buffer)
    (with-current-buffer log-buffer
      (let ((windows-at-end
             (seq-filter (lambda (window)
                           (>= (window-point window) (point-max)))
                         (get-buffer-window-list log-buffer nil t)))
            (point-was-at-end-p (>= (point) (point-max)))
            (inhibit-read-only t))
        (save-excursion
          (goto-char (point-max))
          (insert (ansi-color-apply chunk)))
        (when point-was-at-end-p (goto-char (point-max)))
        (dolist (window windows-at-end)
          (set-window-point window (point-max)))))))

(defun process-compose--start-log-stream (name log-buffer)
  "Stream NAME's logs into LOG-BUFFER, following new output."
  (let ((stream
         (make-process
          :name (format "process-compose-log-%s" name)
          :command (list process-compose-executable "process" "logs" name
                         "-f" "-n" (number-to-string
                                    process-compose-log-tail-length)
                         "--unix-socket" (process-compose--socket-path))
          :connection-type 'pipe
          :noquery t
          :filter (lambda (_stream chunk)
                    (process-compose--log-insert log-buffer chunk))
          :sentinel #'ignore)))
    (with-current-buffer log-buffer
      (setq process-compose-log--stream stream)
      (add-hook 'kill-buffer-hook #'process-compose-log--kill-stream nil t))
    stream))

(defun process-compose-log-buffer-name (name)
  "Return the log buffer name for the process NAME."
  (format "*process-compose-log:%s*" name))

(defun process-compose-log-buffer (name)
  "Return the log buffer for the process NAME, streaming logs while shown.
A dead stream restarts from a clean buffer: the follow tail resends
history, so keeping old content would duplicate it."
  (let ((log-buffer
         (get-buffer-create (process-compose-log-buffer-name name))))
    (with-current-buffer log-buffer
      (unless (derived-mode-p 'process-compose-log-mode)
        (process-compose-log-mode))
      (unless (process-live-p process-compose-log--stream)
        (let ((inhibit-read-only t))
          (erase-buffer)
          (when-let* ((state (process-compose-state name))
                      ((equal (gethash "status" state) "Error"))
                      (excerpt (process-compose--daemon-log-excerpt name)))
            (insert (propertize "process never started - daemon error:\n"
                                'face 'vui-error))
            (dolist (line excerpt)
              (insert (ansi-color-filter-apply line) "\n"))
            (insert "\n")))
        (process-compose--start-log-stream name log-buffer)))
    log-buffer))

(defun process-compose--stop-log-stream (log-buffer)
  "Stop LOG-BUFFER's follow stream, keeping its content for reference."
  (when (buffer-live-p log-buffer)
    (with-current-buffer log-buffer
      (process-compose-log--kill-stream))))

(defun process-compose--log-window ()
  "Return the window currently showing a log pane, or nil."
  (seq-find (lambda (window)
              (with-current-buffer (window-buffer window)
                (derived-mode-p 'process-compose-log-mode)))
            (window-list)))

(defvar process-compose--log-pane-enabled-p t
  "Non-nil while the log pane follows the selection.
Toggled by `process-compose-logs-at-point'.")

(defun process-compose--display-log-window (log-buffer)
  "Show LOG-BUFFER as the log pane below the table, TUI style."
  (display-buffer-in-side-window
   log-buffer
   `((side . bottom) (slot . 0)
     (window-height . ,process-compose-log-window-height)
     (window-parameters . ((no-delete-other-windows . t))))))

(defun process-compose--show-log-for (name)
  "Open the log pane on the process NAME."
  (process-compose--display-log-window (process-compose-log-buffer name)))

(defun process-compose-restart-failed ()
  "Start every process whose last run failed."
  (interactive nil process-compose-mode)
  (let ((failed-names
         (mapcar (lambda (state) (gethash "name" state))
                 (seq-filter
                  (lambda (state)
                    (eq (process-compose--status-class state) 'failed))
                  process-compose--states))))
    (unless failed-names (user-error "No failed processes"))
    (dolist (name failed-names)
      (process-compose-start-process name))))

(defun process-compose-start-namespace (namespace)
  "Start every process in NAMESPACE."
  (interactive
   (list (completing-read
          "Namespace: "
          (delete-dups
           (mapcar (lambda (state) (gethash "namespace" state))
                   process-compose--states))
          nil t))
   process-compose-mode)
  (process-compose--run-command "namespace" "start" namespace))

(defun process-compose--close-log-window ()
  "Close the log pane and stop the stream it was showing."
  (when-let* ((log-window (process-compose--log-window)))
    (process-compose--stop-log-stream (window-buffer log-window))
    (delete-window log-window)))

(defun process-compose-logs-at-point ()
  "Toggle whether the log pane follows the selection.
Opening on a row that has produced no output keeps the pane closed
until the selection reaches a process with something to show."
  (interactive nil process-compose-mode)
  (if (process-compose--log-window)
      (progn
        (setq process-compose--log-pane-enabled-p nil)
        (process-compose--close-log-window))
    (setq process-compose--log-pane-enabled-p t)
    (process-compose--require-name-at-point)
    (unless (process-compose--follow-log-window)
      (message "No output yet; the pane opens when this process runs"))))

(defun process-compose-log-quit ()
  "Quit the log window and stop the pane following the selection."
  (interactive nil process-compose-log-mode)
  (setq process-compose--log-pane-enabled-p nil)
  (quit-window))

(keymap-set process-compose-log-mode-map "q" #'process-compose-log-quit)

(defun process-compose--react-to-selection ()
  "Selection moved: retint the bar and retarget the log pane."
  (process-compose--update-selection-bar)
  (process-compose--follow-log-window))

(defun process-compose--follow-log-window ()
  "Match the log pane to the selected row; non-nil when it is showing.
Rows with output get the pane (opened or retargeted); quiet rows close
it.  The buffer leaving the pane loses its follow stream, so cruising
the board does not accumulate one subprocess per visited row."
  (when-let* ((state (process-compose--state-at-point)))
    (let ((worthy (and process-compose--log-pane-enabled-p
                       (process-compose--log-worthy-p state)))
          (log-window (process-compose--log-window))
          (name (gethash "name" state)))
      (cond
       ((not worthy)
        (process-compose--close-log-window)
        nil)
       ((null log-window)
        (process-compose--show-log-for name)
        t)
       (t
        (let ((shown-buffer (window-buffer log-window)))
          (unless (equal (buffer-name shown-buffer)
                         (process-compose-log-buffer-name name))
            (set-window-buffer log-window (process-compose-log-buffer name))
            (process-compose--stop-log-stream shown-buffer)))
        t)))))

;;; Dashboard mode

(defvar process-compose-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'process-compose-start-at-point)
    (define-key map (kbd "n")   #'process-compose-next-row)
    (define-key map (kbd "p")   #'process-compose-previous-row)
    (define-key map (kbd "l")   #'process-compose-logs-at-point)
    (define-key map (kbd "x")   #'process-compose-stop-at-point)
    (define-key map (kbd "r")   #'process-compose-restart-at-point)
    (define-key map (kbd "g")   #'process-compose-refresh)
    (define-key map (kbd "q")   #'process-compose-quit)
    (define-key map (kbd "R")   #'process-compose-restart-failed)
    (define-key map (kbd "D")   #'process-compose-down)
    (define-key map (kbd "S")   #'process-compose-start-namespace)
    (define-key map (kbd "H")   #'process-compose-toggle-hidden-namespaces)
    map)
  "Keymap for `process-compose-mode' buffers, mirroring the TUI shortcuts.")

(define-derived-mode process-compose-mode vui-mode "process-compose-mode"
  "Major mode for the Process Compose dashboard."
  (setq-local global-mode-string
              (list '(:eval (process-compose--mode-line))
                    (default-value 'global-mode-string)))
  (hl-line-mode 1)
  (add-hook 'post-command-hook #'process-compose--react-to-selection nil t))
(put 'process-compose-mode 'completion-predicate #'ignore)

(with-eval-after-load 'evil
  (evil-define-key* '(normal motion) process-compose-mode-map
    (kbd "RET") #'process-compose-start-at-point
    "j"  #'process-compose-next-row
    "k"  #'process-compose-previous-row
    "l"  #'process-compose-logs-at-point
    "x"  #'process-compose-stop-at-point
    "r"  #'process-compose-restart-at-point
    "q"  #'process-compose-quit
    "R"  #'process-compose-restart-failed
    "D"  #'process-compose-down
    "S"  #'process-compose-start-namespace
    "H"  #'process-compose-toggle-hidden-namespaces
    "gr" #'process-compose-refresh))

(add-to-list 'nerd-icons-mode-icon-alist
             '(process-compose-mode nerd-icons-mdicon "nf-md-fire"
               :face nerd-icons-orange))

(defun process-compose--show-dashboard ()
  "Mount the dashboard, select the first row, and open its log pane."
  (with-current-buffer (get-buffer-create process-compose-buffer-name)
    (unless (derived-mode-p 'process-compose-mode) (process-compose-mode)))
  (vui-mount (vui-component 'process-compose-dashboard)
             process-compose-buffer-name)
  (with-current-buffer process-compose-buffer-name
    (vui-rerender-on-resize)
    (goto-char (point-min))
    (process-compose-next-row)
    (process-compose--follow-log-window)))

;;;###autoload
(defun process-compose ()
  "Open the Process Compose dashboard."
  (interactive)
  (process-compose-ensure)
  (process-compose--show-dashboard))

(defun process-compose--showcase-states ()
  "Return demonstration states, one per visual style."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "fixtures/showcase.json"
                       process-compose--package-directory))
    (append (json-parse-string (buffer-string) :false-object nil) nil)))

;;;###autoload
(defun process-compose-showcase ()
  "Open the dashboard on demonstration states instead of the daemon."
  (interactive)
  (when (process-live-p process-compose--monitor-process)
    (process-put process-compose--monitor-process 'process-compose-deliberate t)
    (kill-process process-compose--monitor-process))
  (setq process-compose--show-hidden-namespaces t)
  (setq process-compose--states (process-compose--showcase-states))
  (process-compose--show-dashboard))

(provide 'process-compose)

;;; process-compose.el ends here
