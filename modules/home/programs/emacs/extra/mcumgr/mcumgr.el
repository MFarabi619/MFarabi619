;;; mcumgr.el --- MCUmgr Toolkit integration  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/mcumgr
;; Keywords: lisp, tools
;; Version: 0.0.1
;; Package-Requires: ((emacs "30.1") (vui "1.3") (nerd-icons "0.1"))

;; This file is not part of GNU Emacs.

;;; Commentary:
;;
;; mcumgrctl ...
;;

;;; Code:

(require 'cl-lib)
(require 'nerd-icons)
(require 'seq)
(require 'vui)
(require 'vui-components)

(declare-function evil-make-overriding-map "evil-core" (keymap &optional state copy))
(declare-function evil-define-key* "evil-core" (state keymap key def &rest bindings))
(declare-function dirvish-subtree--expanded-p "dirvish-subtree" ())
(declare-function dirvish-subtree--insert "dirvish-subtree" ())
(declare-function dired-get-filename "dired" (&optional localp no-error))
(declare-function dired-insert-set-properties "dired" (beg end))
(declare-function dirvish--render-attrs "dirvish" (window &optional selected))
(defvar dirvish-hide-details)
(defvar dirvish--props)
(defvar dirvish--dir-data)

(define-error 'mcumgr-error           "MCUmgr error")
(define-error 'mcumgr-exec-error      "MCUmgr binary execution failed" 'mcumgr-error)
(define-error 'mcumgr-transport-error "MCUmgr transport failed"        'mcumgr-error)
(define-error 'mcumgr-parse-error     "MCUmgr output parse failed"     'mcumgr-error)

(defgroup mcumgr ()
  "MCUmgr Toolkit integration."
  :prefix "mcumgr-"
  :group 'lisp)

(defcustom mcumgr-executable nil
  "Path to the mcumgrctl executable.  If nil, search PATH for mcumgrctl."
  :type '(choice (const :tag "Auto-detect" nil) file)
  :group 'mcumgr)

(defcustom mcumgr-log-enabled t
  "When non-nil, every mcumgrctl invocation is logged to `*mcumgr-log*'."
  :type 'boolean
  :group 'mcumgr)

(defconst mcumgr-log-buffer-name "*mcumgr-log*")

(defun mcumgr--executable ()
  "Return the configured `mcumgrctl' binary, falling back to PATH lookup."
  (or mcumgr-executable
    (executable-find "mcumgrctl")
    "mcumgrctl"))

(define-derived-mode mcumgr-log-mode special-mode "mcumgr-log"
  "Major mode for the `*mcumgr-log*' log buffer."
  (setq-local truncate-lines nil))
(put 'mcumgr-log-mode 'completion-predicate #'ignore)

(defun mcumgr--log-buffer ()
  "Get-or-create the `*mcumgr-log*' buffer in `mcumgr-log-mode'."
  (let ((buffer (get-buffer-create mcumgr-log-buffer-name)))
    (with-current-buffer buffer
      (unless (derived-mode-p 'mcumgr-log-mode) (mcumgr-log-mode)))
    buffer))

(defun mcumgr--log (args exit-code stdout stderr elapsed-ms)
  "Log one entry for ARGS with EXIT-CODE, STDOUT, STDERR and ELAPSED-MS."
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
  "Display the `*mcumgr-log*' buffer."
  (interactive)
  (display-buffer (mcumgr--log-buffer)))

(defun mcumgr-log-clear ()
  "Empty the `*mcumgr-log*' log buffer."
  (interactive)
  (when-let* ((buffer (get-buffer mcumgr-log-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)))))
(put 'mcumgr-log-clear 'completion-predicate #'ignore)

(defun mcumgr--run (&rest args)
  "Run mcumgrctl ARGS synchronously through the queue; return stdout."
  (let* (done exit-code stdout stderr
          (on-exit (lambda (code out err)
                     (setq exit-code code stdout out stderr err done t))))
    (mcumgr-run-async args :on-exit on-exit)
    (with-timeout (mcumgr--run-timeout-seconds
                    (mcumgr--abandon-sync-request on-exit done args))
      (while (not done)
        (accept-process-output nil mcumgr--event-pump-interval-seconds)))
    (unless (zerop exit-code)
      (signal 'mcumgr-exec-error
        (list :exit-code exit-code
          :stdout    stdout
          :stderr    stderr
          :args      args)))
    stdout))

(defun mcumgr--abandon-sync-request (on-exit done args)
  "Dequeue or cancel the timed-out ON-EXIT request for ARGS unless DONE."
  (let ((queued (cl-find-if (lambda (request) (eq (nth 2 request) on-exit))
                  mcumgr--request-queue)))
    (if queued
      (setq mcumgr--request-queue (delq queued mcumgr--request-queue))
      (unless done
        (mcumgr-process-cancel mcumgr--active-process))))
  (signal 'mcumgr-exec-error
    (list :exit-code 'timeout
      :stdout ""
      :stderr (format "timed out after %ss" mcumgr--run-timeout-seconds)
      :args args)))

(defun mcumgr--run-json-as (object-type array-type &rest args)
  "Run mcumgrctl ARGS; parse stdout as JSON with OBJECT-TYPE and ARRAY-TYPE."
  (let ((output (apply #'mcumgr--run args)))
    (condition-case-unless-debug parse-failure
      (json-parse-string output
        :object-type object-type
        :array-type  array-type
        :false-object nil
        :null-object  nil)
      (json-parse-error
        (signal 'mcumgr-parse-error
          (list :error  parse-failure
            :output output
            :args   args))))))

(defun mcumgr--run-json (&rest args)
  "Run mcumgrctl ARGS; parse stdout as JSON plists."
  (apply #'mcumgr--run-json-as 'plist 'list args))

(defun mcumgr--make-line-filter (on-output)
  "Return a process filter that invokes ON-OUTPUT for each complete stdout line."
  (let (unconsumed-start)
    (lambda (process chunk)
      (when (buffer-live-p (process-buffer process))
        (with-current-buffer (process-buffer process)
          (unless unconsumed-start
            (setq unconsumed-start (copy-marker (point-min))))
          (goto-char (point-max))
          (insert chunk)
          (save-excursion
            (goto-char unconsumed-start)
            (while (search-forward "\n" nil t)
              (funcall on-output
                (buffer-substring-no-properties unconsumed-start
                  (1- (point))))
              (set-marker unconsumed-start (point)))))))))

(defun mcumgr--make-sentinel (on-exit args start-time)
  "Return a sentinel for ARGS calling ON-EXIT, timing from START-TIME."
  (lambda (process _event)
    (when (memq (process-status process) '(exit signal))
      (let* ((stdout-buffer (process-buffer process))
              (stderr-buffer (process-get process 'mcumgr-stderr-buffer))
              (stdout (if (buffer-live-p stdout-buffer)
                        (with-current-buffer stdout-buffer (buffer-string))
                        ""))
              (stderr (if (buffer-live-p stderr-buffer)
                        (with-current-buffer stderr-buffer (buffer-string))
                        ""))
              (exit-code (process-exit-status process))
              (elapsed-ms (round (* 1000 (- (float-time) start-time)))))
        (process-put process 'mcumgr-stdout stdout)
        (process-put process 'mcumgr-stderr stderr)
        (mcumgr--log args exit-code stdout stderr elapsed-ms)
        (unwind-protect
          (when on-exit (funcall on-exit exit-code stdout stderr))
          (let (kill-buffer-query-functions)
            (when (buffer-live-p stdout-buffer) (kill-buffer stdout-buffer))
            (when (buffer-live-p stderr-buffer) (kill-buffer stderr-buffer)))
          (when (eq mcumgr--active-process process)
            (setq mcumgr--active-process nil))
          (mcumgr--dispatch-next-request))))))

(defconst mcumgr--run-timeout-seconds 30
  "How long a synchronous request may wait in the queue.")

(defconst mcumgr--event-pump-interval-seconds 0.05
  "Interval between `accept-process-output' turns while waiting.")

(defconst mcumgr--sentinel-grace-seconds 1.0
  "How long to pump for a sentinel after its process dies.")

(defvar mcumgr--request-queue nil
  "FIFO of pending mcumgrctl requests, each (ARGS ON-OUTPUT ON-EXIT).")

(defvar mcumgr--active-process nil
  "The currently running mcumgrctl process, or nil.")

(defun mcumgr--dispatch-next-request ()
  "Spawn the next queued request unless one is running."
  (when (and (not (process-live-p mcumgr--active-process))
          mcumgr--request-queue)
    (pcase-let ((`(,args ,on-output ,on-exit) (pop mcumgr--request-queue)))
      (condition-case spawn-failure
        (setq mcumgr--active-process
          (mcumgr--spawn-request args on-output on-exit))
        (error
          (mcumgr--log args 'spawn-failed ""
            (error-message-string spawn-failure) 0)
          (when on-exit
            (funcall on-exit 127 "" (error-message-string spawn-failure)))
          (mcumgr--dispatch-next-request))))))

(cl-defun mcumgr-run-async (args &key on-output on-exit)
  "Queue mcumgrctl ARGS; ON-OUTPUT gets each line, ON-EXIT the result."
  (setq mcumgr--request-queue
    (append mcumgr--request-queue (list (list args on-output on-exit))))
  (mcumgr--dispatch-next-request))

(defun mcumgr--spawn-request (args on-output on-exit)
  "Spawn mcumgrctl with ARGS now; wire ON-OUTPUT and ON-EXIT."
  (let* ((stdout-buffer (generate-new-buffer " *mcumgr-async-stdout*"))
          (stderr-buffer (generate-new-buffer " *mcumgr-async-stderr*"))
          (start-time (float-time))
          (process
            (make-process
              :name     "mcumgr"
              :command  (cons (mcumgr--executable) args)
              :buffer   stdout-buffer
              :stderr   stderr-buffer
              :noquery  t
              :filter   (when on-output (mcumgr--make-line-filter on-output))
              :sentinel (mcumgr--make-sentinel on-exit args start-time))))
    (process-put process 'mcumgr-stderr-buffer stderr-buffer)
    process))

(defun mcumgr-process-cancel (process)
  "Cancel live PROCESS, triggering its sentinel; return non-nil when it was."
  (when (process-live-p process)
    (delete-process process)
    t))

(defun mcumgr-process-wait (process &optional timeout)
  "Block until PROCESS exits or TIMEOUT seconds; return stdout."
  (unless (processp process)
    (signal 'mcumgr-exec-error
      (list :exit-code 'queued
        :stdout ""
        :stderr "request is still queued; nothing to wait on"
        :args nil)))
  (let ((deadline (and timeout (+ (float-time) timeout))))
    (while (and (process-live-p process)
             (or (null deadline) (< (float-time) deadline)))
      (accept-process-output process mcumgr--event-pump-interval-seconds)))
  (let ((timed-out (process-live-p process)))
    (when timed-out (delete-process process))
    (let ((sentinel-deadline (+ (float-time) mcumgr--sentinel-grace-seconds)))
      (while (and (null (process-get process 'mcumgr-stdout))
               (< (float-time) sentinel-deadline))
        (accept-process-output nil mcumgr--event-pump-interval-seconds)))
    (let ((exit-code (process-exit-status process))
           (stdout    (or (process-get process 'mcumgr-stdout) ""))
           (stderr    (or (process-get process 'mcumgr-stderr) "")))
      (when (or timed-out (not (and exit-code (zerop exit-code))))
        (signal 'mcumgr-exec-error
          (list :exit-code (if timed-out -1 (or exit-code -1))
            :stdout    stdout
            :stderr    (if timed-out "Process timed out\n" stderr)
            :args      (cdr (process-command process)))))
      stdout)))

(defcustom mcumgr-udp-address "10.0.0.172"
  "UDP address preferred when selecting a device; nil auto-selects USB serial."
  :type '(choice (const :tag "Auto-select USB serial" nil) string)
  :group 'mcumgr)

(defun mcumgr--transport-args (transport)
  "Translate TRANSPORT to backend flags."
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

(defun mcumgr-os-echo (transport text)
  "Echo TEXT off the device matched by TRANSPORT; return the response."
  (string-trim-right
    (apply #'mcumgr--run
      (append (mcumgr--transport-args transport)
        (list "os" "echo" text)))))

(defun mcumgr-ping (transport)
  "Return non-nil when the device at TRANSPORT responds."
  (condition-case nil
    (string-match-p "alive and responsive"
      (apply #'mcumgr--run (mcumgr--transport-args transport)))
    (mcumgr-exec-error nil)))

;;; Image group

(defun mcumgr-image-get-state (transport)
  "Return `image get-state' for TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "image" "get-state" "--json"))))

(defun mcumgr-image-slot-info (transport)
  "Return `image slot-info' for TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "image" "slot-info" "--json"))))

;;; OS group

(defun mcumgr-os-task-statistics (transport)
  "Return `os task-statistics' for TRANSPORT as a hash-table."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (list "os" "task-statistics" "--json"))))

(defun mcumgr-os-mcumgr-parameters (transport)
  "Return MCUmgr library parameters for the device matched by TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "os" "mcumgr-parameters" "--json"))))

(defun mcumgr-os-application-info (transport)
  "Return `os application-info' for TRANSPORT as a hash-table."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (list "os" "application-info" "--json"))))

(defun mcumgr-os-bootloader-info (transport)
  "Return `os bootloader-info' for TRANSPORT as a hash-table."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (list "os" "bootloader-info" "--json"))))

;;; Stats group

(defun mcumgr-stats-list-groups (transport)
  "Return the available stat-group names for the device matched by TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "stats" "list-groups" "--json"))))

(defun mcumgr-stats-get (transport &optional group)
  "Return `stats get' for TRANSPORT, limited to GROUP when non-nil."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (if group
        (list "stats" "get" group "--json")
        (list "stats" "get" "--json")))))

;;; FS group

(defun mcumgr-fs-status (transport path)
  "Return `fs status' for PATH on TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "fs" "status" path "--json"))))

(defun mcumgr-fs-checksum (transport path &optional algorithm offset length)
  "Return `fs checksum' of PATH on TRANSPORT with ALGORITHM, OFFSET and LENGTH."
  (apply #'mcumgr--run-json-as 'hash-table 'list
    (append (mcumgr--transport-args transport)
      (list "fs" "checksum" path)
      (when algorithm (list algorithm))
      (when offset (list "--offset" (number-to-string offset)))
      (when length (list "--length" (number-to-string length)))
      (list "--json"))))

(defun mcumgr-fs-download (transport device-path local-path)
  "Download DEVICE-PATH on TRANSPORT to LOCAL-PATH; return LOCAL-PATH."
  (apply #'mcumgr--run
    (append (mcumgr--transport-args transport)
      (list "fs" "download" device-path local-path)))
  local-path)

;;; Firmware group (host-side)

(defun mcumgr-firmware-image-info (file)
  "Return `firmware get-image-info' for the local FILE."
  (mcumgr--run-json "firmware" "get-image-info" "mcuboot" file "--json"))

;;; Enum group

(defun mcumgr-enum-list-groups (transport)
  "Return the supported MCUmgr group IDs for the device matched by TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "enum" "list-groups" "--json"))))

(defun mcumgr-enum-show-group-details (transport)
  "Return `enum show-group-details' for TRANSPORT."
  (apply #'mcumgr--run-json
    (append (mcumgr--transport-args transport)
      (list "enum" "show-group-details" "--json"))))

;;; Panels shared state

(defvar mcumgr-transport nil
  "Transport plist of the selected device, or nil.")

(defcustom mcumgr-refresh-interval 2.0
  "Seconds between task-statistics polls in the threads panel."
  :type 'number
  :group 'mcumgr)

(defcustom mcumgr-files-open nil
  "When non-nil, `mcumgr' opens the device file tree in a side window."
  :type 'boolean
  :group 'mcumgr)

(defcustom mcumgr-files-window-width 45
  "Width of the device file tree side window."
  :type 'natnum
  :group 'mcumgr)

(defcustom mcumgr-files-hide-details t
  "When non-nil, hide ownership and permission details in the files cell."
  :type 'boolean
  :group 'mcumgr)

(defcustom mcumgr-files-expand-tree t
  "When non-nil, expand the whole device tree on open (needs dirvish)."
  :type 'boolean
  :group 'mcumgr)

(defcustom mcumgr-firmware-image-file nil
  "Local MCUboot image compared against the device slots in IMAGES."
  :type '(choice (const :tag "No build comparison" nil) file)
  :group 'mcumgr)

(defun mcumgr--transport-label (transport)
  "Return the address/port string of TRANSPORT for display."
  (or (plist-get transport :udp)
    (plist-get transport :serial)
    (plist-get transport :usb-serial)))

(defcustom mcumgr-device-list-hide-tty-ports t
  "When non-nil, hide /dev/tty.* duplicates from the device list."
  :type 'boolean
  :group 'mcumgr)

(defun mcumgr--device-excluded-p (device)
  "Non-nil if DEVICE should be hidden from the device list."
  (and mcumgr-device-list-hide-tty-ports
    (string-prefix-p "/dev/tty." (plist-get device :port_name))))

(defun mcumgr--device-list-entries ()
  "Return `(PORT . [SERIAL VID:PID PORT MANUFACTURER PRODUCT])' per device."
  (mapcar
    (lambda (device)
      (let* ((port  (plist-get device :port_name))
              (info  (plist-get device :port_info))
              (vid   (plist-get info :vid))
              (pid   (plist-get info :pid)))
        (list port
          (vector (or (plist-get info :serial_number) "")
            (if (and vid pid) (format "%04X:%04X" vid pid)
              (or (plist-get device :identifier) ""))
            port
            (or (plist-get info :manufacturer) "")
            (or (plist-get info :product) "")))))
    (seq-remove #'mcumgr--device-excluded-p (mcumgr-usb-serial-devices))))

(defun mcumgr--auto-select-transport ()
  "Select a device when none is; return the transport, UDP preferred."
  (when (null mcumgr-transport)
    (if mcumgr-udp-address
      (setq mcumgr-transport (list :udp mcumgr-udp-address))
      (ignore-errors
        (let ((entries (mcumgr--device-list-entries)))
          (when (length= entries 1)
            (setq mcumgr-transport (list :serial (caar entries))))))))
  mcumgr-transport)

(defun mcumgr--device-args (&rest subcommand)
  "Return the full mcumgrctl args for SUBCOMMAND against `mcumgr-transport'."
  (append (mcumgr--transport-args mcumgr-transport)
    subcommand
    (list "--json")))

(defun mcumgr--fetch-async (args parse-spec callback)
  "Run ARGS async, parsing per PARSE-SPEC; CALLBACK gets (RESULT ERROR-LINE)."
  (mcumgr-run-async args
    :on-exit
    (lambda (exit-code stdout stderr)
      (let (result error-line)
        (if (zerop exit-code)
          (pcase parse-spec
            ('text (setq result stdout))
            (`(json ,object-type ,array-type)
              (condition-case nil
                (setq result (json-parse-string stdout
                               :object-type object-type
                               :array-type array-type
                               :false-object nil
                               :null-object nil))
                (json-parse-error (setq error-line "unparseable output")))))
          (setq error-line
            (car (split-string
                   (string-trim (if (string-empty-p stderr)
                                  "no response"
                                  stderr))
                   "\n"))))
        (funcall callback result error-line)))))

(defun mcumgr--fetch-chain (steps callback)
  "Run fetch STEPS in order; CALLBACK gets (RESULTS ERROR-LINE)."
  (let (results)
    (cl-labels
      ((run-step (remaining)
         (if (null remaining)
           (funcall callback (nreverse results) nil)
           (pcase-let ((`(,step . ,rest) remaining))
             (mcumgr--fetch-async
               (plist-get step :args)
               (plist-get step :parse)
               (lambda (result error-line)
                 (if (and error-line (not (plist-get step :optional)))
                   (funcall callback nil error-line)
                   (push result results)
                   (run-step rest))))))))
      (run-step steps))))

(defun mcumgr--parse-fs-listing (text)
  "Parse `fs ls' TEXT into (:name :size :directory-p) plists, dropping torn tails."
  (let* ((complete (string-match-p "[\n\r]\\s-*\\'" text))
          (lines (split-string text "[\r\n]+" t))
          (lines (if complete lines (butlast lines)))
          entries)
    (dolist (line lines (nreverse entries))
      (when (string-match "\\`\\s-*\\([0-9]+\\) \\(.+\\)\\'" line)
        (let* ((name (match-string 2 line))
                (directory-p (string-suffix-p "/" name)))
          (push (list :name (if directory-p (substring name 0 -1) name)
                  :size (string-to-number (match-string 1 line))
                  :directory-p directory-p)
            entries))))))

(defun mcumgr--shell-args (transport &rest subcommand)
  "Return the mcumgrctl args running the device shell SUBCOMMAND on TRANSPORT."
  (append (mcumgr--transport-args transport)
    (cons "shell" subcommand)))

(defun mcumgr--parse-kernel-heap (text)
  "Parse the device shell's `kernel heap' TEXT into a stats plist."
  (let (stats)
    (dolist (line (split-string text "[\r\n]+" t) stats)
      (when (string-match
              "\\`\\(free\\|allocated\\|max\\. allocated\\):\\s-+\\([0-9]+\\)" line)
        (setq stats
          (plist-put stats
            (pcase (match-string 1 line)
              ("free" :free)
              ("allocated" :allocated)
              ("max. allocated" :max-allocated))
            (string-to-number (match-string 2 line))))))))

(defun mcumgr--parse-kernel-uptime (text)
  "Parse the device shell's `kernel uptime' TEXT into milliseconds."
  (when (string-match "Uptime:\\s-+\\([0-9]+\\)\\s-*ms" text)
    (string-to-number (match-string 1 text))))

(defun mcumgr--format-uptime (uptime-ms)
  "Format UPTIME-MS as days, hours, and minutes."
  (let* ((minutes (/ uptime-ms 60000))
          (days (/ minutes 1440))
          (hours (mod (/ minutes 60) 24))
          (remaining (mod minutes 60)))
    (string-join
      (delq nil (list (when (> days 0) (format "%dd" days))
                  (when (or (> days 0) (> hours 0)) (format "%dh" hours))
                  (format "%dm" remaining)))
      " ")))

(defun mcumgr--parse-driver-list (text)
  "Parse `device list' TEXT into (:name :state :labels) plists."
  (let (entries)
    (dolist (line (split-string text "[\r\n]+" t) (nreverse entries))
      (cond
        ((string-match "\\`- \\(.+\\) (\\([A-Z_]+\\))\\'" line)
          (push (list :name (match-string 1 line)
                  :state (match-string 2 line)
                  :labels nil)
            entries))
        ((and entries
           (string-match "\\`\\s-+DT node labels:\\s-+\\(.+\\)\\'" line))
          (setf (plist-get (car entries) :labels) (match-string 1 line)))))))

(defun mcumgr--tramp-file-name (path)
  "Return the /mcumgr: file name for PATH on `mcumgr-transport'."
  (format "/mcumgr:%s:%s"
    (if-let* ((label (mcumgr--transport-label mcumgr-transport)))
      (file-name-nondirectory label)
      "")
    path))

(defconst mcumgr--thread-state-flags
  '((1 . "dummy") (2 . "pending") (4 . "sleeping") (8 . "dead")
     (16 . "suspended") (32 . "aborting") (64 . "suspending") (128 . "queued"))
  "Zephyr `thread_state' bits, from include/zephyr/kernel_structs.h.")

(defun mcumgr--thread-state-name (state)
  "Decode the Zephyr thread STATE bitfield into a display string."
  (if (zerop state)
    "running"
    (mapconcat #'cdr
      (seq-filter (lambda (flag) (/= 0 (logand state (car flag))))
        mcumgr--thread-state-flags)
      "+")))

(defun mcumgr--idle-thread-p (name)
  "Non-nil when NAME is Zephyr's idle thread (or a per-core idle on SMP)."
  (string-match-p "\\`idle ?[0-9]*\\'" name))

(defun mcumgr--thread-rows (tasks &optional previous-tasks)
  "Shape TASKS into [NAME TID PRIO STATE CPU%] rows, deltas vs PREVIOUS-TASKS."
  (let ((total 0) (previous-total 0) rows)
    (maphash (lambda (_name stats)
               (cl-incf total (or (gethash "runtime" stats) 0)))
      tasks)
    (when previous-tasks
      (maphash (lambda (_name stats)
                 (cl-incf previous-total (or (gethash "runtime" stats) 0)))
        previous-tasks))
    (let ((delta-total (- total previous-total)))
      (maphash
        (lambda (name stats)
          (let* ((runtime (or (gethash "runtime" stats) 0))
                  (previous-runtime
                    (if-let* ((previous-stats
                                (and previous-tasks
                                  (gethash name previous-tasks))))
                      (or (gethash "runtime" previous-stats) 0)
                      0))
                  (share (if (zerop delta-total) 0.0
                           (/ (* 100.0 (- runtime previous-runtime)) delta-total))))
            (unless (mcumgr--idle-thread-p name)
              (push (list share runtime
                      (vector name
                        (number-to-string (gethash "tid" stats))
                        (number-to-string (gethash "prio" stats))
                        (mcumgr--thread-state-name (gethash "state" stats))
                        (format "%.1f" share)))
                rows))))
        tasks)
      (mapcar #'caddr (sort rows :lessp #'value< :reverse t)))))

(defun mcumgr--image-state-flags (state)
  "Return STATE's truthy image flags as a display string."
  (mapconcat (lambda (key) (substring (symbol-name key) 1))
    (seq-filter (lambda (key) (plist-get state key))
      '(:active :confirmed :pending :bootable :permanent))
    " "))

(defconst mcumgr--short-hash-length 8
  "Displayed prefix length for image hashes.")

(defconst mcumgr--grid-widths [18 18 22 26]
  "Column widths shared by every dashboard table.")

(defun mcumgr--image-rows (slot-info states)
  "Shape SLOT-INFO and STATES into [SLOT VERSION SIZE STATE HASH] rows."
  (mapcan
    (lambda (image-entry)
      (let ((image-id (plist-get image-entry :image)))
        (mapcar
          (lambda (slot-entry)
            (let* ((slot-id (plist-get slot-entry :slot))
                    (state   (seq-find
                               (lambda (entry)
                                 (and (eql (plist-get entry :image) image-id)
                                   (eql (plist-get entry :slot)  slot-id)))
                               states))
                    (hash    (plist-get state :hash))
                    (icon    (if (plist-get state :active)
                               (nerd-icons-mdicon "nf-md-play_circle")
                               (nerd-icons-mdicon "nf-md-tray_arrow_down")))
                    (label   (if (zerop image-id)
                               (number-to-string slot-id)
                               (format "%d/%d" image-id slot-id))))
              (vector (concat icon " " label)
                (or (plist-get state :version) "—")
                (file-size-human-readable (or (plist-get slot-entry :size) 0))
                (mcumgr--image-state-flags state)
                (if hash (substring hash 0 mcumgr--short-hash-length) ""))))
          (plist-get image-entry :slots))))
    slot-info))

(defconst mcumgr--bootloader-modes
  ["single-slot" "swap-scratch" "upgrade-only" "swap-move" "direct-xip"
    "direct-xip-revert" "ram-load" "firmware-loader" "single-slot-ram-load"
    "swap-offset"]
  "MCUboot mode names by enum index, from bootutil/boot_status.h.")

(defun mcumgr--bootloader-mode-name (mode)
  "Return the MCUboot MODE's name, or a raw mode=N fallback."
  (if (and (integerp mode) (<= 0 mode)
        (< mode (length mcumgr--bootloader-modes)))
    (aref mcumgr--bootloader-modes mode)
    (format "mode=%s" mode)))

(defun mcumgr--identity-lines (info bootloader parameters)
  "Shape INFO, BOOTLOADER and PARAMETERS into (ICON FACE LABEL VALUE) lines."
  (seq-filter
    (lambda (line) (nth 3 line))
    (list
      (list "nf-md-cpu_64_bit" 'nerd-icons-cyan "arch"
        (gethash "Machine" info))
      (list "nf-md-label" 'nerd-icons-blue "node"
        (gethash "Node name" info))
      (list "nf-md-tune" 'nerd-icons-purple "smp"
        (when parameters
          (format "%d × %dB"
            (plist-get parameters :buf_count)
            (plist-get parameters :buf_size))))
      (list "nf-md-rocket_launch" 'nerd-icons-orange "bootloader"
        (when bootloader
          (concat (gethash "Name" bootloader) " "
            (mcumgr--bootloader-mode-name
              (gethash "Mode" bootloader))
            (when (gethash "Downgrade Prevention" bootloader)
              " downgrade-protected"))))
      (list "nf-md-developer_board" 'nerd-icons-green "platform"
        (gethash "Hardware platform" info))
      (list "nf-md-atom" 'nerd-icons-lblue "kernel"
        (when (gethash "Kernel name" info)
          (string-join
            (delq nil (list (gethash "Kernel name" info)
                        (gethash "Kernel release" info)))
            " "))))))

(defun mcumgr--system-lines (heap-text uptime-text)
  "Shape kernel HEAP-TEXT and UPTIME-TEXT into card lines."
  (let* ((parsed (and heap-text (mcumgr--parse-kernel-heap heap-text)))
          (heap (and (plist-get parsed :free)
                  (plist-get parsed :allocated)
                  (plist-get parsed :max-allocated)
                  parsed))
          (uptime (and uptime-text (mcumgr--parse-kernel-uptime uptime-text))))
    (seq-filter
      (lambda (line) (nth 3 line))
      (list
        (list "nf-md-timer_outline" 'nerd-icons-green "uptime"
          (when uptime (mcumgr--format-uptime uptime)))
        (list "nf-md-heart_pulse" 'nerd-icons-pink "heap"
          (when heap
            (format "%s used · %s free · peak %s"
              (file-size-human-readable (plist-get heap :allocated))
              (file-size-human-readable (plist-get heap :free))
              (file-size-human-readable
                (plist-get heap :max-allocated)))))))))

(defconst mcumgr--identity-label-order
  '("uptime" "arch" "node" "smp" "bootloader" "heap" "platform" "kernel")
  "Card line order, short values first.")

(defconst mcumgr--identity-label-width
  (apply #'max (mapcar #'length mcumgr--identity-label-order))
  "Label column width: the longest identity label.")

(defun mcumgr--identity-item (line)
  "Return the vnode for one identity LINE, labels padded to align values."
  (pcase-let ((`(,icon ,face ,label ,value) line))
    (vui-hstack
      (vui-text (nerd-icons-mdicon icon :face face))
      (vui-text (format (format "%%-%ds" mcumgr--identity-label-width) label)
        :face face)
      (vui-text value))))

(defun mcumgr--identity-block (details)
  "Return the identity section vnode for the DETAILS lines."
  (vui-vstack
    :indent 1
    (mapcar #'mcumgr--identity-item details)))

(defun mcumgr--thread-load (rows)
  "Return the total CPU load: the sum of the CPU% shares in ROWS."
  (apply #'+ (mapcar (lambda (row) (string-to-number (aref row 4))) rows)))

(defun mcumgr--build-row (build-info file-size states)
  "Shape BUILD-INFO with FILE-SIZE against STATES into an IMAGES row."
  (let* ((hash (plist-get build-info :hash))
          (slot (seq-find (lambda (state) (equal (plist-get state :hash) hash))
                  states)))
    (vector (concat (nerd-icons-mdicon "nf-md-package_variant") " bin")
      (or (plist-get build-info :version) "—")
      (file-size-human-readable (or file-size 0))
      (if slot
        (format "matches slot %d" (plist-get slot :slot))
        "not flashed")
      (substring hash 0 mcumgr--short-hash-length))))

(defconst mcumgr--thread-state-glyphs
  '(("running"   "●" success)
     ("queued"    "◐" warning)
     ("pending"   "○" vui-muted)
     ("sleeping"  "○" vui-muted)
     ("suspended" "◌" warning)
     ("aborting"  "✕" error)
     ("dead"      "✕" error))
  "Status glyph and face per Zephyr thread state name.")

(defun mcumgr--thread-state-cell (state &optional face)
  "Return the STATE cell vnode; FACE overrides the state's own."
  (pcase-let ((`(,glyph ,state-face)
                (or (cdr (assoc (car (split-string state "\\+"))
                           mcumgr--thread-state-glyphs))
                  '("○" vui-muted))))
    (vui-text (concat glyph " " state) :face (or face state-face))))

(defconst mcumgr--cpu-share-hot-threshold 20.0
  "CPU% share rendered with the error face.")

(defconst mcumgr--cpu-share-warm-threshold 5.0
  "CPU% share rendered with the warning face.")

(defun mcumgr--cpu-share-face (share)
  "Return the face expressing the magnitude of a CPU% SHARE."
  (cond ((>= share mcumgr--cpu-share-hot-threshold)  'error)
    ((>= share mcumgr--cpu-share-warm-threshold) 'warning)
    ((>  share 0.0)  'success)
    (t 'vui-muted)))

(defun mcumgr--faced-cells (cells faces)
  "Return vui-text vnodes pairing CELLS with FACES."
  (seq-mapn (lambda (cell face) (vui-text cell :face face)) cells faces))

(defun mcumgr--thread-runnable-p (state)
  "Non-nil when the STATE name means the thread is running or ready."
  (member state '("running" "queued")))

(defun mcumgr--thread-row-cells (cells)
  "Build the THREADS table cell vnodes for the CELLS row vector."
  (pcase-let* ((`[,name ,tid ,prio ,state ,share] cells)
                (name-face (if (mcumgr--thread-runnable-p state)
                             'success
                             'vui-muted)))
    (list (vui-text name :face name-face)
      (vui-muted tid)
      (vui-muted prio)
      (mcumgr--thread-state-cell state)
      (vui-text share :face (mcumgr--cpu-share-face
                              (string-to-number share))))))

(defun mcumgr--thread-columns (load)
  "THREADS column specs with LOAD inline in the CPU header."
  `((:header "NAME"  :width ,(aref mcumgr--grid-widths 0) :grow t)
     (:header "TID"   :width ,(aref mcumgr--grid-widths 1) :grow t)
     (:header "PRIO"  :width ,(aref mcumgr--grid-widths 2) :grow t)
     (:header "STATE" :width ,(aref mcumgr--grid-widths 3) :grow t)
     (:header ,(format "CPU%% · %.1f%%" load) :width 12 :grow t)))

(defconst mcumgr--image-columns
  `((:header "SLOT"    :width ,(aref mcumgr--grid-widths 0) :grow t)
     (:header "VERSION" :width ,(aref mcumgr--grid-widths 1) :grow t)
     (:header "SIZE"    :width ,(aref mcumgr--grid-widths 2) :grow t)
     (:header "STATE"   :width ,(aref mcumgr--grid-widths 3) :grow t)
     (:header "HASH"    :width ,mcumgr--short-hash-length :grow t))
  "Column specs for the IMAGES table, on the shared section grid.")

(defconst mcumgr--image-cell-faces
  '(font-lock-constant-face vui-strong warning success font-lock-comment-face)
  "Cell face per IMAGES column.")

(defun mcumgr--panel-heading (icon-name text &optional note)
  "Return a heading vnode: ICON-NAME's icon beside TEXT with muted NOTE."
  (vui-hstack
    (vui-text (nerd-icons-mdicon icon-name :face 'nerd-icons-cyan))
    (vui-heading-2 text)
    (when note (vui-muted note))))

(defun mcumgr--files-expand-all ()
  "Expand every directory subtree in the current Dired buffer."
  (goto-char (point-min))
  (while (not (eobp))
    (when-let* ((file (dired-get-filename nil t)))
      (when (and (not (member (file-name-nondirectory file) '("." "..")))
              (file-directory-p file)
              (not (dirvish-subtree--expanded-p)))
        (dirvish-subtree--insert)))
    (forward-line 1)))

(defun mcumgr--dired-setup ()
  "Apply the files customs to /mcumgr: Dired buffers."
  (when (string-prefix-p "/mcumgr:" default-directory)
    (when (boundp 'dirvish--props)
      (setf (alist-get :sudo dirvish--props) 1)
      (when (hash-table-p (bound-and-true-p dirvish--dir-data))
        (clrhash dirvish--dir-data)))
    (when (and mcumgr-files-expand-tree
            (fboundp 'dirvish-subtree--insert))
      (mcumgr--files-expand-all))
    (when mcumgr-files-hide-details
      (setq-local dirvish-hide-details t)
      (with-silent-modifications
        (dired-insert-set-properties (point-min) (point-max)))
      (dired-hide-details-mode 1))))

(add-hook 'dired-after-readin-hook #'mcumgr--dired-setup)

(vui-defcomponent mcumgr--threads-panel ()
  :state ((rows nil) (error-line nil))
  :render
  (let ((previous-sample (vui-use-ref nil))
         (poll-in-flight  (vui-use-ref nil)))
    (vui-use-effect ()
      (let* ((poll (vui-with-async-context
                     (when (and mcumgr-transport
                             (not (car poll-in-flight))
                             (null mcumgr--request-queue))
                       (setcar poll-in-flight t)
                       (condition-case nil
                         (mcumgr--fetch-async
                           (mcumgr--device-args "os" "task-statistics")
                           '(json hash-table list)
                           (vui-async-callback (tasks error-line)
                             (setcar poll-in-flight nil)
                             (if error-line
                               (vui-set-state :error-line error-line)
                               (let ((previous
                                       (and (equal (car-safe
                                                     (car previous-sample))
                                              mcumgr-transport)
                                         (cdr (car previous-sample)))))
                                 (vui-batch
                                   (vui-set-state :error-line nil)
                                   (vui-set-state :rows (mcumgr--thread-rows
                                                          tasks previous)))
                                 (setcar previous-sample
                                   (cons mcumgr-transport tasks))))))
                         (error (setcar poll-in-flight nil))))))
              (timer (run-with-timer 0 mcumgr-refresh-interval poll)))
        (lambda () (cancel-timer timer))))
    (let* ((identity (vui-use-async (list 'identity mcumgr-transport)
                       (lambda (resolve reject)
                         (when mcumgr-transport
                           (mcumgr--fetch-chain
                             (list (list :args (mcumgr--device-args
                                                 "os" "application-info")
                                     :parse '(json hash-table list))
                               (list :args (mcumgr--device-args
                                             "os" "bootloader-info")
                                 :parse '(json hash-table list)
                                 :optional t)
                               (list :args (mcumgr--device-args
                                             "os" "mcumgr-parameters")
                                 :parse '(json plist list)
                                 :optional t))
                             (lambda (results error-line)
                               (if error-line
                                 (funcall reject error-line)
                                 (pcase-let ((`(,info ,bootloader ,parameters)
                                               results))
                                   (funcall resolve
                                     (mcumgr--identity-lines
                                       info bootloader parameters))))))))))
            (system (vui-use-async (list 'system mcumgr-transport)
                      (lambda (resolve _reject)
                        (when mcumgr-transport
                          (mcumgr--fetch-chain
                            (list (list :args (mcumgr--shell-args
                                                mcumgr-transport "kernel" "heap")
                                    :parse 'text
                                    :optional t)
                              (list :args (mcumgr--shell-args
                                            mcumgr-transport "kernel" "uptime")
                                :parse 'text
                                :optional t))
                            (lambda (results _error-line)
                              (funcall resolve (mcumgr--system-lines
                                                 (car results)
                                                 (cadr results)))))))))
            (details (sort (append (plist-get identity :data)
                             (plist-get system :data))
                       :key (lambda (line)
                              (or (seq-position mcumgr--identity-label-order
                                    (nth 2 line))
                                  (length mcumgr--identity-label-order))))))
      (vui-vstack
        (mcumgr--panel-heading "nf-md-cpu_64_bit"
          (format "THREADS (%d)" (length rows)))
        (cond
          (error-line (vui-error (format "unreachable: %s" error-line)))
          ((null rows) (vui-muted "polling…"))
          (t (vui-vstack
               :indent 1
               (vui-table
                 :columns (mcumgr--thread-columns (mcumgr--thread-load rows))
                 :header-face 'vui-muted
                 :rows (mapcar #'mcumgr--thread-row-cells rows)))))
        (when-let* ((identity-error-line (plist-get identity :error)))
          (vui-error (format " unreachable: %s" identity-error-line)))
        (when details (vui-newline))
        (when details (mcumgr--identity-block details))))))

(vui-defcomponent mcumgr--images-panel ()
  :render
  (let* ((result (vui-use-async (list 'images mcumgr-transport
                                  mcumgr-firmware-image-file)
                   (lambda (resolve reject)
                     (when mcumgr-transport
                       (let ((file (and mcumgr-firmware-image-file
                                     (file-exists-p mcumgr-firmware-image-file)
                                     mcumgr-firmware-image-file)))
                         (mcumgr--fetch-chain
                           (append
                             (list (list :args (mcumgr--device-args
                                                 "image" "slot-info")
                                     :parse '(json plist list))
                               (list :args (mcumgr--device-args
                                             "image" "get-state")
                                 :parse '(json plist list)))
                             (when file
                               (list (list :args (list "firmware" "get-image-info"
                                                   "mcuboot" file "--json")
                                       :parse '(json plist list)
                                       :optional t))))
                           (lambda (results error-line)
                             (if error-line
                               (funcall reject error-line)
                               (pcase-let ((`(,slot-info ,states ,build-info)
                                             results))
                                 (funcall
                                   resolve
                                   (list :slots (mcumgr--image-rows
                                                  slot-info states)
                                     :build (when build-info
                                              (mcumgr--build-row
                                                build-info
                                                (file-attribute-size
                                                  (file-attributes file))
                                                states)))))))))))))
          (data    (plist-get result :data))
          (slots   (plist-get data :slots))
          (build   (plist-get data :build))
          (error-line (plist-get result :error)))
    (vui-vstack
      (mcumgr--panel-heading "nf-md-memory"
        (format "IMAGES (%d)" (length slots)))
      (cond
        (error-line (vui-error (format "unreachable: %s" error-line)))
        ((eq (plist-get result :status) 'pending) (vui-muted "fetching…"))
        (t (vui-vstack
             :indent 1
             (vui-table
               :columns mcumgr--image-columns
               :header-face 'vui-muted
               :rows (mapcar (lambda (cells)
                               (mcumgr--faced-cells cells mcumgr--image-cell-faces))
                       (append slots (when build (list build)))))))))))

(defun mcumgr--pio-device-locations (json-text)
  "Parse pio device list JSON-TEXT into (PORT . LOCATION) pairs."
  (delq nil
    (mapcar (lambda (device)
              (let ((hwid (plist-get device :hwid)))
                (when (and hwid (string-match "LOCATION=\\([^ ]+\\)" hwid))
                  (cons (plist-get device :port)
                    (match-string 1 hwid)))))
      (json-parse-string json-text
        :object-type 'plist
        :array-type 'list
        :false-object nil
        :null-object nil))))

(defun mcumgr--fetch-pio-locations (callback)
  "Fetch USB locations via pio; CALLBACK gets a (PORT . LOCATION) alist."
  (if-let* ((pio (executable-find "pio")))
    (let ((stdout (generate-new-buffer " *mcumgr-pio*"))
           (stderr (generate-new-buffer " *mcumgr-pio-stderr*")))
      (make-process
        :name "mcumgr-pio-locations"
        :buffer stdout
        :stderr stderr
        :command (list pio "device" "list" "--json-output")
        :noquery t
        :sentinel
        (lambda (process _event)
          (when (memq (process-status process) '(exit signal))
            (let ((output (with-current-buffer stdout (buffer-string)))
                   (kill-buffer-query-functions nil))
              (kill-buffer stdout)
              (when (buffer-live-p stderr) (kill-buffer stderr))
              (funcall callback
                (when (zerop (process-exit-status process))
                  (ignore-errors
                    (mcumgr--pio-device-locations output)))))))))
    (funcall callback nil)))

(defconst mcumgr--device-columns
  `((:header "VID:PID"     :width ,(aref mcumgr--grid-widths 0) :grow t)
     (:header "SERIAL"      :width ,(aref mcumgr--grid-widths 1) :grow t)
     (:header "PORT"        :width ,(aref mcumgr--grid-widths 2) :grow t)
     (:header "LOCATION"    :width ,(aref mcumgr--grid-widths 3) :grow t)
     (:header "DESCRIPTION" :width 20 :grow t))
  "Column specs for the DEVICES table, on the shared section grid.")

(defun mcumgr--device-row-cells (entry locations)
  "Return DEVICES cells for ENTRY with LOCATIONS from pio."
  (pcase-let ((`(,_port [,serial ,vid-pid ,port ,_manufacturer ,product])
                entry))
    (list
      (vui-text vid-pid :face 'font-lock-constant-face)
      (vui-text serial :face 'success)
      (vui-text port :face 'warning)
      (vui-text (or (cdr (assoc port locations)) "")
        :face 'nerd-icons-blue)
      (vui-muted product))))

(vui-defcomponent mcumgr--devices-panel ()
  :state ((devices (ignore-errors (mcumgr--device-list-entries))))
  :render
  (let ((locations (plist-get
                     (vui-use-async 'pio-locations
                       (lambda (resolve _reject)
                         (mcumgr--fetch-pio-locations resolve)))
                     :data)))
    (vui-vstack
      (mcumgr--panel-heading "nf-md-chip" (format "DEVICES (%d)" (length devices)))
      (if (null devices)
        (vui-muted " no serial devices detected")
        (vui-vstack
          :indent 1
          (vui-table
            :columns mcumgr--device-columns
            :header-face 'vui-muted
            :rows (mapcar (lambda (entry)
                            (mcumgr--device-row-cells entry locations))
                    devices)))))))

;;; Layout

(defconst mcumgr--driver-columns
  `((:header "NAME"      :width ,(aref mcumgr--grid-widths 0) :grow t)
     (:header "STATE"     :width ,(aref mcumgr--grid-widths 1) :grow t)
     (:header "DT LABELS" :width ,(aref mcumgr--grid-widths 2) :grow t))
  "Column specs for the DRIVERS table, on the shared section grid.")

(defun mcumgr--driver-row-cells (driver)
  "Return the faced DRIVERS table cells for the DRIVER entry."
  (list
    (vui-text (plist-get driver :name))
    (vui-text (plist-get driver :state)
      :face (if (equal (plist-get driver :state) "READY")
              'success
              'warning))
    (vui-muted (or (plist-get driver :labels) ""))))

(vui-defcomponent mcumgr--drivers-panel ()
  :render
  (let* ((result (vui-use-async (list 'drivers mcumgr-transport)
                   (lambda (resolve reject)
                     (when mcumgr-transport
                       (mcumgr--fetch-async
                         (mcumgr--shell-args mcumgr-transport "device" "list")
                         'text
                         (lambda (text error-line)
                           (if error-line
                             (funcall reject error-line)
                             (funcall resolve
                               (mcumgr--parse-driver-list text)))))))))
          (drivers (plist-get result :data))
          (error-line (plist-get result :error)))
    (vui-vstack
      (mcumgr--panel-heading "nf-md-expansion_card"
        (format "DRIVERS (%d)" (length drivers)))
      (cond
        (error-line (vui-error (format "unreachable: %s" error-line)))
        ((eq (plist-get result :status) 'pending) (vui-muted "fetching…"))
        (t (vui-vstack
             :indent 1
             (vui-table
               :columns mcumgr--driver-columns
               :header-face 'vui-muted
               :rows (mapcar #'mcumgr--driver-row-cells drivers))))))))

(defconst mcumgr-buffer-name "*mcumgr*")

(vui-defcomponent mcumgr--dashboard ()
  "The devices, images, and threads sections stacked in one buffer."
  :render
  (vui-vstack
    :spacing 1
    (vui-component 'mcumgr--devices-panel)
    (vui-component 'mcumgr--images-panel)
    (vui-component 'mcumgr--drivers-panel)
    (vui-component 'mcumgr--threads-panel)))

(defun mcumgr-quit ()
  "Kill the MCUmgr buffer and device Dired buffers; close their windows."
  (interactive)
  (dolist (window (window-list nil 'no-minibuffer))
    (when (window-parameter window 'mcumgr-files-window)
      (condition-case err
        (delete-window window)
        (error (message "%s" (error-message-string err))))))
  (cl-loop for buffer in (buffer-list)
    for name = (buffer-name buffer)
    when (and (buffer-live-p buffer)
           (or (equal name mcumgr-log-buffer-name)
             (buffer-match-p '(derived-mode . mcumgr-mode) buffer)
             (string-prefix-p
               "/mcumgr:"
               (or (buffer-local-value 'default-directory buffer)
                 ""))))
    do (condition-case err
         (let ((window (get-buffer-window buffer t)))
           (unless (equal name mcumgr-log-buffer-name)
             (let (kill-buffer-query-functions)
               (kill-buffer buffer)))
           (when (and (window-live-p window)
                   (window-deletable-p window))
             (delete-window window)))
         (error (message "%s" (error-message-string err))))))

(defun mcumgr--command-in-context-p (_symbol buffer)
  "Non-nil when BUFFER belongs to the mcumgr UI."
  (or (buffer-match-p '(derived-mode . mcumgr-mode) buffer)
    (buffer-match-p '(derived-mode . mcumgr-log-mode) buffer)
    (string-prefix-p "/mcumgr:"
      (or (buffer-local-value 'default-directory buffer) ""))))

(dolist (command '(mcumgr-quit mcumgr-log-show))
  (put command 'completion-predicate #'mcumgr--command-in-context-p))

(defvar-keymap mcumgr-mode-map
  :parent vui-mode-map
  "q" #'mcumgr-quit)

(define-derived-mode mcumgr-mode vui-mode "mcumgr"
  "Major mode for the MCUmgr buffer.

\\{mcumgr-mode-map}"
  (setq-local truncate-lines t)
  (when (fboundp 'evil-make-overriding-map)
    (evil-make-overriding-map mcumgr-mode-map 'normal))
  (when (fboundp 'evil-define-key*)
    (evil-define-key* '(normal motion) mcumgr-mode-map
      "q" #'mcumgr-quit)))
(put 'mcumgr-mode 'completion-predicate #'ignore)

(add-to-list 'nerd-icons-mode-icon-alist
  '(mcumgr-mode nerd-icons-mdicon "nf-md-chip"
     :face nerd-icons-cyan))

;;;###autoload
(defun mcumgr ()
  "Open the MCUmgr buffer."
  (interactive)
  (mcumgr--auto-select-transport)
  (with-current-buffer (get-buffer-create mcumgr-buffer-name)
    (unless (derived-mode-p 'mcumgr-mode)
      (mcumgr-mode)))
  (vui-mount (vui-component 'mcumgr--dashboard) mcumgr-buffer-name)
  (switch-to-buffer mcumgr-buffer-name)
  (when (and mcumgr-files-open mcumgr-transport)
    (let ((window (display-buffer
                    (dired-noselect (mcumgr--tramp-file-name "/"))
                    `(display-buffer-in-side-window
                       (side . right)
                       (window-width . ,mcumgr-files-window-width)
                       (window-parameters . ((mcumgr-files-window . t)))))))
      (when (and window (fboundp 'dirvish--render-attrs))
        (dirvish--render-attrs window)))))

(provide 'mcumgr)

(with-eval-after-load 'tramp
  (require 'mcumgr-tramp))

;;; mcumgr.el ends here
