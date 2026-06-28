;;; mcumgr.el --- MCUmgr Toolkit integration for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; Keywords: lisp, tools

;; This file is not part of GNU Emacs.

;;; Commentary:
;; WIP

;;; Code:

(require 'json)

(define-error 'mcumgr-error           "MCUmgr error")
(define-error 'mcumgr-exec-error      "MCUmgr binary execution failed" 'mcumgr-error)
(define-error 'mcumgr-transport-error "MCUmgr transport failed"        'mcumgr-error)
(define-error 'mcumgr-parse-error     "MCUmgr output parse failed"     'mcumgr-error)

(defgroup mcumgr ()
  "MCUmgr Toolkit integration."
  :prefix "mcumgr-"
  :group 'lisp)

(defcustom mcumgr-executable nil
  "Path to the mcumgrctl executable. If nil, search PATH for mcumgrctl."
  :type '(choice (const :tag "Auto-detect" nil) file)
  :group 'mcumgr)

(defcustom mcumgr-log-enabled t
  "When non-nil, every mcumgrctl invocation is logged to `*mcumgr*'."
  :type 'boolean
  :group 'mcumgr)

(defconst mcumgr-log-buffer-name "*mcumgr*")

(defun mcumgr--executable ()
  "Return the configured `mcumgrctl' binary, falling back to PATH lookup."
  (or mcumgr-executable
    (executable-find "mcumgrctl")
    "mcumgrctl"))

(define-derived-mode mcumgr-log-mode special-mode "mcumgr-log"
  "Major mode for the `*mcumgr*' log buffer."
  (setq-local truncate-lines nil))

(defun mcumgr--log-buffer ()
  "Get-or-create the `*mcumgr*' log buffer in `mcumgr-log-mode'."
  (let ((buf (get-buffer-create mcumgr-log-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'mcumgr-log-mode) (mcumgr-log-mode)))
    buf))

(defun mcumgr--log (args exit-code stdout stderr elapsed-ms)
  "Append one timestamped entry for an invocation to the log buffer."
  (when mcumgr-log-enabled
    (with-current-buffer (mcumgr--log-buffer)
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (propertize (format-time-string "[%H:%M:%S.%3N] ") 'face 'shadow)
          (mcumgr--executable) " "
          (mapconcat #'shell-quote-argument args " ") "\n  "
          (propertize (format "exit=%s" exit-code)
            'face (if (and (integerp exit-code) (zerop exit-code))
                    'success 'error))
          (propertize (format " elapsed=%dms" elapsed-ms) 'face 'shadow) "\n")
        (dolist (stream (list (cons "stdout" stdout) (cons "stderr" stderr)))
          (unless (string-empty-p (cdr stream))
            (insert (propertize (format "  %s:\n" (car stream))
                      'face 'font-lock-keyword-face))
            (dolist (line (split-string (string-trim-right (cdr stream)) "\n"))
              (insert "    " line "\n"))))
        (insert "\n")))))

(defun mcumgr-log-show ()
  "Display the `*mcumgr*' log buffer."
  (interactive)
  (display-buffer (mcumgr--log-buffer)))

(defun mcumgr-log-clear ()
  "Empty the `*mcumgr*' log buffer."
  (interactive)
  (when-let ((buf (get-buffer mcumgr-log-buffer-name)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)))))

(defun mcumgr--call (executable args)
  "Run EXECUTABLE with ARGS. Return (EXIT-CODE STDOUT STDERR)."
  (let ((stderr-file (make-temp-file "mcumgr-stderr-"))
         (start (float-time)))
    (unwind-protect
      (with-temp-buffer
        (let* ((exit-code (apply #'call-process executable nil
                            (list (current-buffer) stderr-file)
                            nil args))
                (stdout    (buffer-string))
                (stderr    (with-temp-buffer
                             (insert-file-contents stderr-file)
                             (buffer-string)))
                (elapsed   (round (* 1000 (- (float-time) start)))))
          (mcumgr--log args exit-code stdout stderr elapsed)
          (list exit-code stdout stderr)))
      (delete-file stderr-file))))

(defun mcumgr--run (&rest args)
  "Run mcumgrctl with ARGS; return stdout.
Signal `mcumgr-exec-error' on non-zero exit."
  (pcase-let ((`(,exit-code ,stdout ,stderr)
                (mcumgr--call (mcumgr--executable) args)))
    (unless (zerop exit-code)
      (signal 'mcumgr-exec-error
        (list :exit-code exit-code
          :stdout    stdout
          :stderr    stderr
          :args      args)))
    stdout))

(defun mcumgr--run-json-as (object-type array-type &rest args)
  "Run mcumgrctl with ARGS; parse stdout as JSON with OBJECT-TYPE and ARRAY-TYPE.
Signal `mcumgr-parse-error' on bad JSON."
  (let ((output (apply #'mcumgr--run args)))
    (condition-case err
      (json-parse-string output
        :object-type object-type
        :array-type  array-type
        :false-object nil
        :null-object  nil)
      (error
        (signal 'mcumgr-parse-error
          (list :error  err
            :output output
            :args   args))))))

(defun mcumgr--run-json (&rest args)
  "Run mcumgrctl with ARGS; parse stdout as JSON (objects → plists, arrays → lists).
Signal `mcumgr-parse-error' on bad JSON."
  (apply #'mcumgr--run-json-as 'plist 'list args))

(defun mcumgr--make-line-filter (on-output)
  "Return a process filter that calls ON-OUTPUT for each complete stdout line."
  (let (tail)
    (lambda (proc chunk)
      (when (buffer-live-p (process-buffer proc))
        (with-current-buffer (process-buffer proc)
          (unless tail (setq tail (copy-marker (point-min))))
          (goto-char (point-max))
          (insert chunk)
          (save-excursion
            (goto-char tail)
            (while (search-forward "\n" nil t)
              (funcall on-output
                (buffer-substring-no-properties tail (1- (point))))
              (set-marker tail (point)))))))))

(defun mcumgr--make-sentinel (on-exit args start-time)
  "Return a process sentinel that logs, stashes stdout/stderr, and calls ON-EXIT."
  (lambda (proc _event)
    (when (memq (process-status proc) '(exit signal))
      (let* ((stdout-buf (process-buffer proc))
              (stderr-buf (process-get proc 'mcumgr-stderr-buffer))
              (stdout (if (buffer-live-p stdout-buf)
                        (with-current-buffer stdout-buf (buffer-string))
                        ""))
              (stderr (if (buffer-live-p stderr-buf)
                        (with-current-buffer stderr-buf (buffer-string))
                        ""))
              (exit-code (process-exit-status proc))
              (elapsed   (round (* 1000 (- (float-time) start-time)))))
        (process-put proc 'mcumgr-stdout stdout)
        (process-put proc 'mcumgr-stderr stderr)
        (mcumgr--log args exit-code stdout stderr elapsed)
        (unwind-protect
          (when on-exit (funcall on-exit exit-code stdout stderr))
          (let (kill-buffer-query-functions)
            (when (buffer-live-p stdout-buf) (kill-buffer stdout-buf))
            (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))))))))

(defun mcumgr-run-async (args &rest plist)
  "Run mcumgrctl with ARGS asynchronously. Return the spawned process.
PLIST keys:
  :on-output FN  (FN LINE)                       per stdout line
  :on-exit   FN  (FN EXIT-CODE STDOUT STDERR)    on termination
Cancel with `mcumgr-task-cancel' or `delete-process'."
  (let* ((on-output  (plist-get plist :on-output))
          (on-exit    (plist-get plist :on-exit))
          (stdout-buf (generate-new-buffer " *mcumgr-async-stdout*"))
          (stderr-buf (generate-new-buffer " *mcumgr-async-stderr*"))
          (start-time (float-time))
          (process
            (make-process
              :name     "mcumgr"
              :command  (cons (mcumgr--executable) args)
              :buffer   stdout-buf
              :stderr   stderr-buf
              :noquery  nil
              :filter   (when on-output (mcumgr--make-line-filter on-output))
              :sentinel (mcumgr--make-sentinel on-exit args start-time))))
    (process-put process 'mcumgr-stderr-buffer stderr-buf)
    process))

(defun mcumgr-task-cancel (process)
  "Cancel PROCESS. Triggers its sentinel for cleanup."
  (when (process-live-p process)
    (delete-process process))
  t)

(defun mcumgr-task-wait (process &optional timeout)
  "Block until PROCESS exits; return stdout.
Signal `mcumgr-exec-error' on non-zero exit or TIMEOUT (seconds)."
  (let ((deadline (and timeout (+ (float-time) timeout))))
    (while (and (process-live-p process)
             (or (null deadline) (< (float-time) deadline)))
      (accept-process-output process 0.05)))
  (let ((timed-out (process-live-p process)))
    (when timed-out (delete-process process))
    (let ((exit-code (process-exit-status process))
           (stdout    (or (process-get process 'mcumgr-stdout) ""))
           (stderr    (or (process-get process 'mcumgr-stderr) "")))
      (when (or timed-out (not (and exit-code (zerop exit-code))))
        (signal 'mcumgr-exec-error
          (list :exit-code (if timed-out -1 (or exit-code -1))
            :stdout    stdout
            :stderr    (if timed-out "Task timed out\n" stderr)
            :args      (cdr (process-command process)))))
      stdout)))

(defun mcumgr--transport-args (transport)
  "Translate a TRANSPORT plist to mcumgrctl backend flags.
TRANSPORT must have exactly one of `:udp', `:serial', or `:usb-serial'.
UDP is preferred; `:usb-serial' is enumeration-only because connecting
via identifier is broken upstream."
  (cond
    ((plist-get transport :udp)        (list "--udp"        (plist-get transport :udp)))
    ((plist-get transport :serial)     (list "--serial"     (plist-get transport :serial)))
    ((plist-get transport :usb-serial) (list "--usb-serial" (plist-get transport :usb-serial)))
    (t (error "Invalid mcumgr transport: %S" transport))))

;;; Enumeration

(defun mcumgr-usb-serial-devices ()
  "Enumerate USB-serial devices known to mcumgrctl (parsed JSON)."
  (mcumgr--run-json "--usb-serial" "--json"))

(defun mcumgr-serial-ports ()
  "Enumerate serial ports known to mcumgrctl (parsed JSON list of strings)."
  (mcumgr--run-json "--serial" "--json"))

;;; Connectivity

(defun mcumgr-ping (transport)
  "Return non-nil when the device matched by TRANSPORT responds.
Returns nil on any `mcumgr-exec-error' (unreachable, timeout, etc.)."
  (condition-case nil
    (string-match-p "alive and responsive"
      (apply #'mcumgr--run (mcumgr--transport-args transport)))
    (mcumgr-exec-error nil)))

;;; Image group

(defun mcumgr-image-get-state (transport)
  "Return slot state for the device matched by TRANSPORT.
Wraps `mcumgr image get-state'."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "image" "get-state" "--json"))))

(defun mcumgr-image-slot-info (transport)
  "Return image slot info for the device matched by TRANSPORT.
Wraps `mcumgr image slot-info'."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "image" "slot-info" "--json"))))

;;; OS group

(defun mcumgr-os-task-statistics (transport)
  "Return task statistics for the device matched by TRANSPORT as a hash-table.
Keys are task names; values are hash-tables with :prio, :tid, :state, :runtime."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (list "os" "task-statistics" "--json"))))

(defun mcumgr-os-mcumgr-parameters (transport)
  "Return MCUmgr library parameters for the device matched by TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "os" "mcumgr-parameters" "--json"))))

(defun mcumgr-os-application-info (transport)
  "Return application info (uname-like) for the device matched by TRANSPORT.
Keys include \"Kernel name\", \"Kernel release\", \"Node name\", etc."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (list "os" "application-info" "--json"))))

(defun mcumgr-os-bootloader-info (transport)
  "Return bootloader info for the device matched by TRANSPORT.
Keys include \"Name\", \"Mode\", \"Downgrade Prevention\"."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (list "os" "bootloader-info" "--json"))))

;;; Stats group

(defun mcumgr-stats-list-groups (transport)
  "Return the list of available stat group names for the device matched by TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "stats" "list-groups" "--json"))))

(defun mcumgr-stats-get (transport &optional group)
  "Return statistics from the device matched by TRANSPORT.
When GROUP is non-nil, query only that stat group; otherwise query all."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (if group
        (list "stats" "get" group "--json")
        (list "stats" "get" "--json")))))

;;; FS group

(defun mcumgr-fs-status (transport path)
  "Return file status for PATH on the device matched by TRANSPORT.
Result is a plist with :length (byte count)."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "fs" "status" path "--json"))))

(defun mcumgr-fs-checksum (transport path &optional algo offset length)
  "Return the checksum of PATH on the device matched by TRANSPORT.
ALGO defaults to the device's preferred algorithm (usually crc32).
OFFSET and LENGTH restrict the byte range; both default to full file.
Result is a hash-table with keys \"checksum\", \"type\", \"data length\",
\"data offset\"."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (list "fs" "checksum" path)
      (when algo   (list algo))
      (when offset (list "--offset" (number-to-string offset)))
      (when length (list "--length" (number-to-string length)))
      (list "--json"))))

;;; Enum group

(defun mcumgr-enum-list-groups (transport)
  "Return the list of supported MCUmgr group IDs for the device matched by TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "enum" "list-groups" "--json"))))

(defun mcumgr-enum-show-group-details (transport)
  "Return details for all supported MCUmgr groups at TRANSPORT.
Each entry is a plist with :group (id), :name, and :handlers."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "enum" "show-group-details" "--json"))))

(provide 'mcumgr)

;;; mcumgr.el ends here
