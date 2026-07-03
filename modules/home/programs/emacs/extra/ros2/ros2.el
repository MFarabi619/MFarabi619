;;; ros2.el --- ROS2 support -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/ros2
;; Keywords: tools, robotics
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (websocket "1.15") (nerd-icons "0.1") (vui "0.1") (process-compose "0.0.1"))

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
(require 'websocket)
(require 'nerd-icons)
(require 'subr-x)
(require 'vui)
(require 'vui-components)
(require 'process-compose)
(require 'ros2-cdr)
(require 'ros2-teleop)

(defgroup ros2 ()
  "ROS2 support."
  :prefix "ros2-"
  :group 'tools)

(defcustom ros2-url "ws://localhost:8765"
  "URL of the ROS2 bridge to connect to."
  :type 'string
  :group 'ros2)

(defcustom ros2-subprotocol "foxglove.sdk.v1"
  "WebSocket subprotocol offered to the bridge.
`foxglove_bridge' 3.x requires \"foxglove.sdk.v1\"; older versions used
\"foxglove.websocket.v1\".  Exactly one is offered -- the `websocket'
library rejects the handshake unless the server echoes every offered
subprotocol, so multiple cannot be listed."
  :type 'string
  :group 'ros2)

(defcustom ros2-nodes '("bridge" "simulator")
  "Nodes the studio can start, stop, and monitor."
  :type '(repeat string)
  :group 'ros2)

(defcustom ros2-autostart-nodes '("simulator")
  "Nodes to start automatically when the studio opens.
The simulator's launch brings up the bridge too, so the studio connects on its
own.  Set to nil to start nothing and attach to an already-running bridge."
  :type '(repeat string)
  :group 'ros2)

(defcustom ros2-topics-width 44
  "Width, in columns, of the TOPICS side window."
  :type 'integer
  :group 'ros2)

(defcustom ros2-teleop-width 26
  "Width, in columns, of the teleop side window."
  :type 'integer
  :group 'ros2)

(defcustom ros2-window-arrangement 'studio
  "How `ros2' places its panels.
`studio' owns the frame in the Lichtblick 3-column layout: topics dock left,
teleop docks right, and the other panels (parameters, log) fill the centre.
nil places nothing itself, leaving every panel to `display-buffer-alist'.

Each panel is displayed with its category (`ros2-topics', `ros2-parameters',
`ros2-teleop', `ros2-log') in the `display-buffer' action alist, so any panel's
placement can be overridden per-category via `display-buffer-alist' or Doom
`set-popup-rule!' -- the same way `dape' is customised."
  :type '(choice (const :tag "Lichtblick 3-column (own the frame)" studio)
                 (const :tag "Leave placement to display-buffer-alist" nil))
  :group 'ros2)

(defcustom ros2-workspace nil
  "Directory the nodes are launched from.
When nil, it is discovered from `default-directory'."
  :type '(choice (const :tag "Discover from default-directory" nil) directory)
  :group 'ros2)

(defcustom ros2-pixi-executable "pixi"
  "The pixi executable used to launch nodes."
  :type 'string
  :group 'ros2)

(defcustom ros2-stop-nodes-on-quit nil
  "When non-nil, quitting the studio stops the nodes it started.
Off by default: closing the UI should not take the robot down with it."
  :type 'boolean
  :group 'ros2)

(defcustom ros2-connect-retry-interval 1.0
  "Seconds between connection attempts while the bridge comes up."
  :type 'number
  :group 'ros2)

(defcustom ros2-connect-retry-limit 60
  "How many times to retry the connection before giving up.
High enough to cover the simulator's build-and-launch when it is autostarted."
  :type 'integer
  :group 'ros2)

(defcustom ros2-node-ready-messages
  '(("bridge" . "Server listening on port"))
  "Alist mapping a node to a regexp that marks it ready when seen in its output.
A node with a ready regexp shows the launching glyph until the regexp
matches; a node without one is considered up once its process is live."
  :type '(alist :key-type string :value-type regexp)
  :group 'ros2)

(defcustom ros2-launch-grace 2.0
  "Seconds a node without a ready regexp shows as launching before it is up."
  :type 'number
  :group 'ros2)

(cl-defstruct ros2--session
  "All state for one connection to a ROS2 bridge, shared by every panel."
  connection connected server-info
  (channels (make-hash-table :test 'eql))
  parameters started-nodes started-at
  retry-timer (retry-count 0) publish-channels
  subscriptions messages)

(defvar ros2--session nil
  "The current `ros2--session', or nil when the studio is closed.")

(defun ros2--channels ()
  "Return the current session's channel hash table, or nil."
  (and ros2--session (ros2--session-channels ros2--session)))

(defun ros2--parameters ()
  "Return the current session's parameters, or nil."
  (and ros2--session (ros2--session-parameters ros2--session)))

(defun ros2--server-info ()
  "Return the current session's `serverInfo' alist, or nil."
  (and ros2--session (ros2--session-server-info ros2--session)))

(defun ros2--connected-p ()
  "Return non-nil when the current session's bridge connection is open."
  (and ros2--session (ros2--session-connected ros2--session)))

(defun ros2--started-at ()
  "Return the current session's node start-time alist, or nil."
  (and ros2--session (ros2--session-started-at ros2--session)))


;;; Publishing (client-side CDR encode + Foxglove client channels)

(defun ros2--float64-le (value)
  "Return VALUE as an 8-byte little-endian IEEE-754 double, a unibyte string."
  (let ((sign 0) (exp 0) (frac 0))
    (unless (zerop value)
      (setq sign (if (< value 0.0) 1 0))
      (pcase-let ((`(,significand . ,exponent) (frexp (abs value))))
        (setq exp (+ (1- exponent) 1023)
              frac (round (* (- (* 2.0 significand) 1.0) (expt 2 52))))))
    (unibyte-string
     (logand frac #xff)
     (logand (ash frac -8) #xff)
     (logand (ash frac -16) #xff)
     (logand (ash frac -24) #xff)
     (logand (ash frac -32) #xff)
     (logand (ash frac -40) #xff)
     (logior (ash (logand exp #xf) 4) (logand (ash frac -48) #xf))
     (logior (ash sign 7) (logand (ash exp -4) #x7f)))))

(defun ros2--uint32-le (value)
  "Return VALUE as a 4-byte little-endian integer, a unibyte string."
  (unibyte-string (logand value #xff)
                  (logand (ash value -8) #xff)
                  (logand (ash value -16) #xff)
                  (logand (ash value -24) #xff)))

(defun ros2--encode-twist (linear angular)
  "Return the CDR bytes for a geometry_msgs/msg/Twist, a unibyte string.
LINEAR and ANGULAR are each an (X Y Z) list of numbers."
  (apply #'concat
         (unibyte-string #x00 #x01 #x00 #x00)
         (mapcar (lambda (v) (ros2--float64-le (float v)))
                 (append linear angular))))

(defun ros2--publish-channel (topic schema)
  "Return the client channel id for TOPIC, advertising it once with SCHEMA."
  (when (and ros2--session (ros2--connected-p))
    (or (alist-get topic (ros2--session-publish-channels ros2--session) nil nil #'equal)
        (let ((id (1+ (length (ros2--session-publish-channels ros2--session)))))
          (websocket-send-text
           (ros2--session-connection ros2--session)
           (json-encode
            `((op . "advertise")
              (channels . ,(vector `((id . ,id) (topic . ,topic)
                                     (encoding . "cdr") (schemaName . ,schema)))))))
          (setf (alist-get topic (ros2--session-publish-channels ros2--session)
                           nil nil #'equal)
                id)
          id))))

(defun ros2--publish-message (channel-id payload)
  "Send PAYLOAD (a unibyte string) as a client message on CHANNEL-ID."
  (when (and ros2--session (ros2--connected-p))
    (websocket-send
     (ros2--session-connection ros2--session)
     (make-websocket-frame
      :opcode 'binary
      :payload (concat (unibyte-string #x01) (ros2--uint32-le channel-id) payload)
      :completep t))))

(defun ros2--publish-twist (linear-x angular-z)
  "Publish a Twist to `ros2-teleop-topic' with LINEAR-X and ANGULAR-Z (SI units)."
  (when-let ((channel (ros2--publish-channel ros2-teleop-topic
                                             "geometry_msgs/msg/Twist")))
    (ros2--publish-message
     channel
     (ros2--encode-twist (list linear-x 0.0 0.0) (list 0.0 0.0 angular-z)))))

(defvar-local ros2--topic-filter ""
  "Active TOPICS filter: show only topics or schemas containing this string.")

(defun ros2--channel-rows ()
  "Return the advertised channel alists, sorted by topic."
  (let ((channels (ros2--channels))
        rows)
    (when (hash-table-p channels)
      (maphash (lambda (_id channel) (push channel rows)) channels))
    (sort rows (lambda (a b)
                 (string< (or (alist-get 'topic a) "")
                          (or (alist-get 'topic b) ""))))))

(defface ros2-filter '((t :inherit warning))
  "Face for the active TOPICS filter indicator."
  :group 'ros2)

(defun ros2--filter-channels (channels filter)
  "Return the CHANNELS selected by FILTER.
FILTER is matched case-insensitively against each channel's topic and schema
name; an empty FILTER returns CHANNELS unchanged."
  (if (string-empty-p filter)
      channels
    (let ((needle (downcase filter)))
      (seq-filter
       (lambda (channel)
         (or (string-search needle (downcase (or (alist-get 'topic channel) "")))
             (string-search needle (downcase (or (alist-get 'schemaName channel) "")))))
       channels))))

(defun ros2--filter-indicator (filter)
  "Return an inline indicator for a non-empty FILTER, or nil when it is empty."
  (unless (string-empty-p filter)
    (propertize (format "  ⟨ %s ⟩" filter) 'face 'ros2-filter)))

(defface ros2-tab-active '((t :inherit mode-line-emphasis :weight bold))
  "Face for the active center-panel tab."
  :group 'ros2)

(defface ros2-tab-inactive '((t :inherit shadow))
  "Face for an inactive center-panel tab."
  :group 'ros2)

(defconst ros2--center-panels
  '(("Parameters" . ros2-parameters)
    ("Messages" . ros2-messages)
    ("Log" . ros2-log))
  "Center-group panels and the commands that show them, in tab order.")

(defun ros2--panel-tabs (active)
  "Return the center-group tab bar, highlighting the ACTIVE command's tab.
Each tab is mouse-clickable and runs its command to show that panel."
  (mapconcat
   (lambda (panel)
     (let ((command (cdr panel)))
       (propertize (format " %s " (car panel))
                   'face (if (eq command active) 'ros2-tab-active 'ros2-tab-inactive)
                   'mouse-face 'highlight
                   'help-echo (format "Show the %s panel" (car panel))
                   'keymap (let ((map (make-sparse-keymap)))
                             (define-key map [header-line mouse-1]
                                         (lambda () (interactive) (funcall command)))
                             map))))
   ros2--center-panels
   (propertize "│" 'face 'shadow)))

(defun ros2--adjacent-panel (current step)
  "Return the center-panel command STEP positions from CURRENT, wrapping around."
  (let* ((commands (mapcar #'cdr ros2--center-panels))
         (index (or (cl-position current commands) 0)))
    (nth (mod (+ index step) (length commands)) commands)))

(defun ros2--current-panel-command ()
  "Return the command for the current center panel, or nil."
  (pcase major-mode
    ('ros2-parameters-mode 'ros2-parameters)
    ('ros2-messages-mode 'ros2-messages)
    ('ros2-log-mode 'ros2-log)))

(defun ros2-next-panel ()
  "Show the next center panel, cycling through the tab order."
  (declare (modes ros2-parameters-mode ros2-messages-mode ros2-log-mode))
  (interactive)
  (funcall (ros2--adjacent-panel (ros2--current-panel-command) 1)))

(defun ros2-previous-panel ()
  "Show the previous center panel."
  (declare (modes ros2-parameters-mode ros2-messages-mode ros2-log-mode))
  (interactive)
  (funcall (ros2--adjacent-panel (ros2--current-panel-command) -1)))

(defun ros2-filter-topics (filter)
  "Filter the TOPICS list to those matching FILTER.
Read FILTER in the minibuffer, seeded with the current one; empty clears it."
  (declare (modes ros2-mode))
  (interactive (list (read-string "Filter topics: " ros2--topic-filter)))
  (setq ros2--topic-filter (string-trim filter))
  (ros2--schedule-update))

(defun ros2--display-host ()
  "Return `ros2-url' with the `ws://' or `wss://' scheme stripped."
  (replace-regexp-in-string "\\`wss?://" "" ros2-url))

(defun ros2--display-buffer (buffer category)
  "Display BUFFER, tagged with CATEGORY, per `ros2-window-arrangement'.
CATEGORY (e.g. `ros2-topics') rides in the `display-buffer' action alist so
`display-buffer-alist' and Doom `set-popup-rule!' can override placement."
  (pcase-let
      ((`(,fns . ,alist)
        (if (eq ros2-window-arrangement 'studio)
            (pcase category
              ('ros2-topics
               `((display-buffer-in-side-window)
                 (side . left) (window-width . ,ros2-topics-width)
                 (slot . 0) (dedicated . t)))
              ('ros2-teleop
               `((display-buffer-in-side-window)
                 (side . right) (window-width . ,ros2-teleop-width)
                 (slot . 0) (dedicated . t)))
              (_ '((display-buffer-same-window))))
          '(nil))))
    (display-buffer buffer
                    `((display-buffer-reuse-window . ,fns)
                      (category . ,category)
                      ,@alist))))


;;; Node lifecycle

(defun ros2--workspace ()
  "Return the node launch directory when `ros2-workspace' overrides it.
Nil means the daemon default: the monorepo root, where pixi.toml lives."
  (when ros2-workspace (expand-file-name ros2-workspace)))

(defun ros2--service-name (node)
  "Return the service name for NODE."
  (format "ros2:%s" node))

(defun ros2--node-log-buffer-name (node)
  "Return the log buffer name for NODE."
  (process-compose-log-buffer-name (ros2--service-name node)))

(defun ros2--declare-node (node)
  "Declare NODE as a Process Compose process; the daemon supervises it."
  (process-compose-declare
   (list :name (ros2--service-name node)
         :namespace "ros2"
         :display-name node
         :command (format "%s run %s" ros2-pixi-executable node)
         :disabled t
         :config
         (append
          '((shutdown . ((signal . 2))))
          (when-let* ((workspace (ros2--workspace)))
            `((working_dir . ,workspace)))
          (when-let* ((ready (alist-get node ros2-node-ready-messages
                                        nil nil #'equal)))
            `((ready_log_line . ,ready)))))))

(defun ros2--ensure-services ()
  "Declare every node in `ros2-nodes' and bring the daemon up to date."
  (dolist (node ros2-nodes) (ros2--declare-node node))
  (add-hook 'process-compose-after-update-hook #'ros2--schedule-update)
  (process-compose-ensure)
  (process-compose-reconcile))

(defun ros2--node-ready-p (node state)
  "Non-nil when NODE's live STATE has reached its ready state.
Uses the ready log line when one is set, else the launch grace period."
  (if (alist-get node ros2-node-ready-messages nil nil #'equal)
      (equal (gethash "is_ready" state) "Ready")
    (let ((started (alist-get node (ros2--started-at) nil nil #'equal)))
      (or (null started)
          (> (float-time (time-subtract (current-time) started)) ros2-launch-grace)))))

(defun ros2--node-state (node)
  "Return NODE's supervisory state.
One of `stopped', `launching', `up', or `failed' -- derived from the
daemon's state stream: a crash is a non-success exit (`failed'), while a
user-stopped (exit -1), cleanly-exited, or never-run node is `stopped'."
  (let ((state (process-compose-state (ros2--service-name node))))
    (if (null state)
        'stopped
      (pcase (gethash "status" state)
        ((or "Running" "Launching" "Launched")
         (if (ros2--node-ready-p node state) 'up 'launching))
        ("Restarting" 'launching)
        ("Completed" (if (memql (gethash "exit_code" state 0) '(-1 0))
                         'stopped
                       'failed))
        ("Error" 'failed)
        (_ 'stopped)))))

(defun ros2--node-running-p (node)
  "Non-nil when NODE's process is live (launching or up)."
  (memq (ros2--node-state node) '(launching up)))

(defun ros2--start-node (node)
  "Start NODE and begin collecting its log.
The log buffer starts its follow stream immediately so the aggregated
log panel sees output; displaying it is the caller's choice."
  (setf (alist-get node (ros2--session-started-at ros2--session) nil nil #'equal)
        (current-time))
  (process-compose-start-process (ros2--service-name node))
  (process-compose-log-buffer (ros2--service-name node)))

(defun ros2--stop-node (node)
  "Stop NODE."
  (when (ros2--node-running-p node)
    (process-compose-stop-process (ros2--service-name node))))

(defun ros2--node-at-point ()
  "Return the node named on the studio row at point, or nil."
  (get-text-property (point) 'ros2-node))

(defun ros2--node-glyph (state)
  "Return the propertized status glyph for a node in STATE."
  (pcase state
    ('up        (propertize "●" 'face 'vui-success))
    ('launching (propertize "◐" 'face 'vui-warning))
    ('failed    (propertize "✕" 'face 'vui-error))
    (_          (propertize "○" 'face 'vui-muted))))

(defun ros2--node-log-tail (node)
  "Return the last non-blank line of NODE's log buffer, or nil."
  (when-let ((buffer (get-buffer (ros2--node-log-buffer-name node))))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (point-max))
        (skip-chars-backward "\n\t ")
        (let ((end (point)))
          (beginning-of-line)
          (let ((line (string-trim (buffer-substring-no-properties (point) end))))
            (unless (string-empty-p line) line)))))))

(defun ros2--node-failure-detail (node)
  "Return the propertized failure detail (exit code and log tail) for NODE."
  (when-let* ((state (process-compose-state (ros2--service-name node))))
    (let ((tail (ros2--node-log-tail node)))
      (concat (propertize (format "exit %d" (gethash "exit_code" state 0))
                          'face 'vui-error)
              (when tail
                (concat "   " (propertize (truncate-string-to-width tail 52 nil nil "…")
                                          'face 'vui-muted)))))))

(defun ros2--node-row (node)
  "Return the NODES-panel line for NODE, tagged for row-at-point lookup."
  (let* ((state (ros2--node-state node))
         (glyph (ros2--node-glyph state))
         (name  (propertize (format "%-10s" node)
                            'face (if (eq state 'stopped) 'vui-muted 'default))))
    (propertize
     (concat "   " glyph "  " name
             (when (eq state 'failed) (ros2--node-failure-detail node)))
     'ros2-node node)))

(defun ros2--set-mode-line ()
  "Show the connection status in the mode-line.
Uses `mode-line-process', not `mode-name', so ibuffer's Mode column stays clean."
  (setq mode-line-process
        (list " "
              (if (ros2--connected-p)
                  (nerd-icons-mdicon "nf-md-lan_connect" :face 'success)
                (nerd-icons-mdicon "nf-md-lan_disconnect" :face 'error))
              " "
              (propertize (ros2--display-host) 'face 'shadow)))
  (force-mode-line-update))

(defface ros2-topic '((t :weight bold))
  "Face for a topic name in the TOPICS list."
  :group 'ros2)

(defface ros2-divider '((t :inherit shadow))
  "Face for the faint rule between topic cards."
  :group 'ros2)

(defun ros2--topic-card-lines (channel)
  "Return CHANNEL as a card: bold topic name, dimmed schema, and a faint rule.
Name and schema share the left edge; a horizontal rule separates cards."
  (list
   (vui-text (concat "  " (propertize (or (alist-get 'topic channel) "")
                                      'face 'ros2-topic)))
   (vui-text (concat "  " (propertize (or (alist-get 'schemaName channel) "")
                                      'face 'shadow)))
   (vui-text (propertize (make-string (max 1 (- ros2-topics-width 2)) ?─)
                         'face 'ros2-divider))))

(defun ros2--topic-list ()
  "Return the advertised topics as cards, filtered by `ros2--topic-filter'.
Each card is a bold topic name over its dimmed schema.  Shows a placeholder
when nothing is advertised, or nothing matches the filter."
  (let ((rows (ros2--filter-channels (ros2--channel-rows) ros2--topic-filter)))
    (if rows
        (vui-vstack (mapcan #'ros2--topic-card-lines rows))
      (vui-text (propertize
                 (if (string-empty-p ros2--topic-filter)
                     "  (no channels advertised)"
                   (format "  (no topics match %S)" ros2--topic-filter))
                 'face 'shadow)))))


;;; Parameters

(defface ros2-param-number '((t :inherit font-lock-constant-face))
  "Face for a numeric parameter value."
  :group 'ros2)

(defface ros2-param-string '((t :inherit font-lock-string-face))
  "Face for a string parameter value."
  :group 'ros2)

(defface ros2-param-bool '((t :inherit font-lock-keyword-face))
  "Face for a boolean parameter value."
  :group 'ros2)

(defun ros2--format-parameter-value (value)
  "Return parameter VALUE as a display string, coloured by its type."
  (cond
   ((eq value t)      (propertize "true"  'face 'ros2-param-bool))
   ((eq value :false) (propertize "false" 'face 'ros2-param-bool))
   ((numberp value)   (propertize (number-to-string value) 'face 'ros2-param-number))
   ((stringp value)   (propertize (format "%S" value) 'face 'ros2-param-string))
   (t                 (format "%S" value))))

(defun ros2--parameter-rows ()
  "Return the session parameters as name/value alists, sorted by name."
  (sort (copy-sequence (ros2--parameters))
        (lambda (a b) (string< (or (alist-get 'name a) "")
                               (or (alist-get 'name b) "")))))

(defun ros2--parameter-table ()
  "Return the parameters as a coloured name/value table, or a placeholder."
  (let ((rows (ros2--parameter-rows)))
    (if rows
        (vui-table
         :header-face 'shadow
         :columns '((:header "PARAMETER" :width 58 :truncate t)
                    (:header "VALUE" :width 40 :truncate t))
         :rows (mapcar
                (lambda (param)
                  (list (or (alist-get 'name param) "")
                        (ros2--format-parameter-value (alist-get 'value param))))
                rows))
      (vui-text (propertize "  (no parameters)" 'face 'shadow)))))

(vui-defcomponent ros2--parameters-view ()
  "The parameters panel: a name/value table."
  :render
  (ros2--parameter-table))

(defvar ros2-parameters-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "p"              #'ros2-parameters)
    (define-key map "l"              #'ros2-log)
    (define-key map (kbd "TAB")      #'ros2-next-panel)
    (define-key map (kbd "<backtab>") #'ros2-previous-panel)
    map)
  "Keymap for `ros2-parameters-mode', switching center panels.")

(define-derived-mode ros2-parameters-mode vui-mode "ros2-parameters"
  "Major mode for the *ros2-parameters* panel."
  (setq-local global-mode-string nil
              header-line-format '(:eval (ros2--panel-tabs 'ros2-parameters))))
(put 'ros2-parameters-mode 'completion-predicate #'ignore)

(with-eval-after-load 'evil
  (evil-define-key* 'normal ros2-parameters-mode-map
    "p"               #'ros2-parameters
    "l"               #'ros2-log
    (kbd "TAB")       #'ros2-next-panel
    (kbd "<backtab>") #'ros2-previous-panel))

(with-eval-after-load 'nerd-icons
  (add-to-list 'nerd-icons-mode-icon-alist
               '(ros2-parameters-mode nerd-icons-devicon "nf-dev-ros" :face nerd-icons-blue)))

(defun ros2--set-parameters (parameters)
  "Store PARAMETERS on the session."
  (setf (ros2--session-parameters ros2--session) parameters))

(defun ros2--request-parameters (&optional connection)
  "Ask the bridge for all parameters over CONNECTION or the current one."
  (let ((connection (or connection
                        (and ros2--session (ros2--session-connection ros2--session)))))
    (when (and connection (websocket-openp connection))
      (websocket-send-text
       connection
       "{\"op\":\"getParameters\",\"parameterNames\":[],\"id\":\"ros2\"}"))))

(defun ros2--parameters-buffer ()
  "Return the *ros2-parameters* buffer, mounted and ready.
Mounts without stealing the selected window, so the caller controls layout."
  (let ((buffer (get-buffer-create "*ros2-parameters*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'ros2-parameters-mode) (ros2-parameters-mode)))
    (save-window-excursion
      (vui-mount (vui-component 'ros2--parameters-view) "*ros2-parameters*"))
    buffer))

(defun ros2-parameters ()
  "Open the parameters panel and refresh it from the bridge."
  (declare (modes ros2-mode))
  (interactive)
  (ros2--request-parameters)
  (ros2--display-buffer (ros2--parameters-buffer) 'ros2-parameters))


;;; Messages (live topic values as a tree)

(defface ros2-message-key '((t :inherit font-lock-variable-name-face))
  "Face for a message field name."
  :group 'ros2)

(defun ros2--message-alist-p (value)
  "Non-nil if VALUE is a decoded message: an alist keyed by string field names."
  (and (consp value) (consp (car value)) (stringp (caar value))))

(defun ros2--format-message (decoded &optional indent)
  "Return DECODED message as a propertized indented tree, at depth INDENT."
  (let ((indent (or indent 0)) (out ""))
    (dolist (field decoded out)
      (setq out (concat out (ros2--format-message-node
                             (car field) (cdr field) indent))))))

(defun ros2--format-message-node (name value indent)
  "Format field NAME holding VALUE at depth INDENT as one or more tree lines."
  (let ((pad (make-string (* 2 indent) ?\s))
        (key (propertize name 'face 'ros2-message-key)))
    (cond
     ((ros2--message-alist-p value)
      (concat pad key "\n" (ros2--format-message value (1+ indent))))
     ((and (listp value) value)
      (concat pad key (propertize (format " [%d]" (length value)) 'face 'shadow) "\n"
              (ros2--format-message-array value (1+ indent))))
     ((null value)
      (concat pad key (propertize " []" 'face 'shadow) "\n"))
     (t (concat pad key "  " (ros2--format-parameter-value value) "\n")))))

(defun ros2--format-message-array (items indent)
  "Format array ITEMS at depth INDENT, one indexed line or subtree each."
  (let ((pad (make-string (* 2 indent) ?\s)) (index 0) (out ""))
    (dolist (item items out)
      (let ((tag (propertize (format "[%d]" index) 'face 'shadow)))
        (setq out (concat out
                          (if (ros2--message-alist-p item)
                              (concat pad tag "\n" (ros2--format-message item (1+ indent)))
                            (concat pad tag "  "
                                    (ros2--format-parameter-value item) "\n")))
              index (1+ index))))))

(defvar-local ros2--message-topic nil
  "The topic whose latest message the *ros2-messages* panel displays.")

(defun ros2--message-body ()
  "Return the selected topic's latest message as a tree, or a placeholder."
  (if-let ((topic ros2--message-topic))
      (let ((decoded (and ros2--session
                          (alist-get topic (ros2--session-messages ros2--session)
                                     nil nil #'equal)))
            (channel (ros2--channel-for-topic topic)))
        (vui-vstack
         (vui-text (concat "  " (propertize topic 'face 'ros2-message-key) "   "
                           (propertize (or (alist-get 'schemaName channel) "")
                                       'face 'shadow)))
         (vui-text "")
         (if decoded
             (vui-text (string-trim-right (ros2--format-message decoded)))
           (vui-text (propertize "  (waiting for a message…)" 'face 'shadow)))))
    (vui-text (propertize "  Press / to pick a topic" 'face 'shadow))))

(vui-defcomponent ros2--messages-view ()
  "The messages panel: the selected topic's latest value as a tree."
  :render
  (ros2--message-body))

(defun ros2-messages-select (topic)
  "Subscribe to TOPIC and show its live messages in the *ros2-messages* panel."
  (declare (modes ros2-messages-mode))
  (interactive (list (completing-read "Topic: " (ros2--topic-names) nil t)))
  (when (and ros2--message-topic (not (equal ros2--message-topic topic)))
    (ros2--unsubscribe ros2--message-topic))
  (setq ros2--message-topic topic)
  (ros2--subscribe topic)
  (vui-refresh))

(defvar ros2-messages-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "/"              #'ros2-messages-select)
    (define-key map "p"              #'ros2-parameters)
    (define-key map "l"              #'ros2-log)
    (define-key map (kbd "TAB")      #'ros2-next-panel)
    (define-key map (kbd "<backtab>") #'ros2-previous-panel)
    map)
  "Keymap for `ros2-messages-mode', switching center panels and picking a topic.")

(define-derived-mode ros2-messages-mode vui-mode "ros2-messages"
  "Major mode for the *ros2-messages* panel."
  (setq-local global-mode-string nil
              header-line-format '(:eval (ros2--panel-tabs 'ros2-messages))))
(put 'ros2-messages-mode 'completion-predicate #'ignore)

(with-eval-after-load 'evil
  (evil-define-key* 'normal ros2-messages-mode-map
    "/"               #'ros2-messages-select
    "p"               #'ros2-parameters
    "l"               #'ros2-log
    (kbd "TAB")       #'ros2-next-panel
    (kbd "<backtab>") #'ros2-previous-panel))

(with-eval-after-load 'nerd-icons
  (add-to-list 'nerd-icons-mode-icon-alist
               '(ros2-messages-mode nerd-icons-devicon "nf-dev-ros" :face nerd-icons-blue)))

(defun ros2--messages-buffer ()
  "Return the *ros2-messages* buffer, mounted and ready."
  (let ((buffer (get-buffer-create "*ros2-messages*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'ros2-messages-mode) (ros2-messages-mode)))
    (save-window-excursion
      (vui-mount (vui-component 'ros2--messages-view) "*ros2-messages*"))
    buffer))

(defun ros2-messages ()
  "Open the messages panel."
  (declare (modes ros2-mode))
  (interactive)
  (ros2--display-buffer (ros2--messages-buffer) 'ros2-messages))


;;; Log

(defcustom ros2-log-min-level 'info
  "Lowest log level shown in the log panel.
Entries below this level are hidden; unstructured lines are always shown."
  :type '(choice (const debug) (const info) (const warn) (const error) (const fatal))
  :group 'ros2)

(defcustom ros2-log-max-lines 500
  "Most recent process-output lines the log panel parses and shows."
  :type 'integer
  :group 'ros2)

(defface ros2-log-warn '((t :inherit warning))
  "Face for a WARN log level."
  :group 'ros2)

(defface ros2-log-error '((t :inherit error))
  "Face for an ERROR or FATAL log level."
  :group 'ros2)

(defface ros2-log-debug '((t :inherit shadow))
  "Face for a DEBUG log level."
  :group 'ros2)

(defface ros2-log-node '((t :inherit font-lock-function-name-face))
  "Face for the node name in a log line."
  :group 'ros2)

(defvar-local ros2--log-filter ""
  "Active log filter: show only lines whose message or node contains this.")

(defconst ros2--log-levels '((debug . 10) (info . 20) (warn . 30) (error . 40) (fatal . 50))
  "Ordering of ROS2 log levels, lowest severity first.")

(defun ros2--log-level-value (level)
  "Return the numeric severity of LEVEL, or 0 when LEVEL is unknown."
  (or (alist-get level ros2--log-levels) 0))

(defun ros2--strip-ansi (string)
  "Return STRING with ANSI escape sequences removed."
  (replace-regexp-in-string "\033\\[[0-9;?]*[A-Za-z]" "" string))

(defun ros2--parse-log-line (line)
  "Parse a raw LINE into a plist (:level :stamp :node :message).
LEVEL is a symbol (`info', `warn', ...) or nil for an unstructured line, whose
whole text becomes :message.  A leading launch-process prefix is stripped."
  (let ((stripped (replace-regexp-in-string "\\`\\[[^]]*-[0-9]+\\] " "" line)))
    (if (string-match
         "\\`\\[\\(DEBUG\\|INFO\\|WARN\\|ERROR\\|FATAL\\)\\] \\[\\([0-9.]+\\)\\] \\[\\([^]]*\\)\\]: \\(.*\\)\\'"
         stripped)
        (list :level (intern (downcase (match-string 1 stripped)))
              :stamp (match-string 2 stripped)
              :node (match-string 3 stripped)
              :message (match-string 4 stripped))
      (list :level nil :node nil :message line))))

(defun ros2--filter-log-entries (entries min-level search)
  "Return the subset of ENTRIES selected by MIN-LEVEL and SEARCH.
Entries below MIN-LEVEL are dropped, but unstructured entries (no level) always
pass; SEARCH is matched case-insensitively against message and node, and an
empty SEARCH matches everything."
  (let ((min-value (ros2--log-level-value min-level))
        (needle (unless (string-empty-p search) (downcase search))))
    (seq-filter
     (lambda (entry)
       (let ((level (plist-get entry :level)))
         (and (or (null level) (>= (ros2--log-level-value level) min-value))
              (or (null needle)
                  (string-search needle (downcase (or (plist-get entry :message) "")))
                  (string-search needle (downcase (or (plist-get entry :node) "")))))))
     entries)))

(defun ros2--format-log-entry (entry)
  "Return ENTRY as a single coloured log line."
  (let ((level (plist-get entry :level))
        (node (plist-get entry :node))
        (message (or (plist-get entry :message) "")))
    (if (null level)
        (propertize (concat "  " message) 'face 'shadow)
      (concat "  "
              (propertize (format "%-5s" (upcase (symbol-name level)))
                          'face (pcase level
                                  ('warn 'ros2-log-warn)
                                  ((or 'error 'fatal) 'ros2-log-error)
                                  ('debug 'ros2-log-debug)
                                  (_ 'default)))
              " "
              (propertize (or node "") 'face 'ros2-log-node)
              (propertize ": " 'face 'shadow)
              message))))

(defun ros2--log-entries ()
  "Collect, parse, and filter the recent log lines from the node buffers."
  (let (raw)
    (dolist (node ros2-nodes)
      (when-let ((buffer (get-buffer (ros2--node-log-buffer-name node))))
        (with-current-buffer buffer
          (setq raw (append raw (split-string (ros2--strip-ansi (buffer-string)) "\n" t))))))
    (ros2--filter-log-entries
     (mapcar #'ros2--parse-log-line (last raw ros2-log-max-lines))
     ros2-log-min-level ros2--log-filter)))

(defun ros2--log-body ()
  "Return the filtered log entries as stacked lines, or a placeholder."
  (let ((entries (ros2--log-entries)))
    (if entries
        (vui-vstack
         (mapcar (lambda (entry) (vui-text (ros2--format-log-entry entry))) entries))
      (vui-text (propertize "  (no log output)" 'face 'shadow)))))

(vui-defcomponent ros2--log-view ()
  "The log panel: node output, parsed and coloured."
  :render
  (if-let ((indicator (ros2--filter-indicator ros2--log-filter)))
      (vui-vstack (vui-text indicator) (ros2--log-body))
    (ros2--log-body)))

(defun ros2-log-filter (filter)
  "Filter the log panel to lines matching FILTER.
Read FILTER in the minibuffer, seeded with the current one; empty clears it."
  (declare (modes ros2-log-mode))
  (interactive (list (read-string "Filter log: " ros2--log-filter)))
  (setq ros2--log-filter (string-trim filter))
  (vui-refresh))

(defvar ros2-log-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map "/"              #'ros2-log-filter)
    (define-key map "p"              #'ros2-parameters)
    (define-key map "l"              #'ros2-log)
    (define-key map (kbd "TAB")      #'ros2-next-panel)
    (define-key map (kbd "<backtab>") #'ros2-previous-panel)
    map)
  "Keymap for `ros2-log-mode'.")

(define-derived-mode ros2-log-mode vui-mode "ros2-log"
  "Major mode for the *ros2-log* panel."
  (setq-local global-mode-string nil
              header-line-format '(:eval (ros2--panel-tabs 'ros2-log))))
(put 'ros2-log-mode 'completion-predicate #'ignore)

(with-eval-after-load 'evil
  (evil-define-key* 'normal ros2-log-mode-map
    "/"               #'ros2-log-filter
    "p"               #'ros2-parameters
    "l"               #'ros2-log
    (kbd "TAB")       #'ros2-next-panel
    (kbd "<backtab>") #'ros2-previous-panel))

(with-eval-after-load 'nerd-icons
  (add-to-list 'nerd-icons-mode-icon-alist
               '(ros2-log-mode nerd-icons-devicon "nf-dev-ros" :face nerd-icons-blue)))

(defun ros2--log-buffer ()
  "Return the *ros2-log* buffer, mounted and ready.
Mounts without stealing the selected window, so the caller controls layout."
  (let ((buffer (get-buffer-create "*ros2-log*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'ros2-log-mode) (ros2-log-mode)))
    (save-window-excursion
      (vui-mount (vui-component 'ros2--log-view) "*ros2-log*"))
    buffer))

(defun ros2-log ()
  "Open the log panel, tailing the running nodes' output."
  (declare (modes ros2-mode))
  (interactive)
  (ros2--display-buffer (ros2--log-buffer) 'ros2-log))

(vui-defcomponent ros2--studio ()
  "The studio: the TOPICS list."
  :render
  (if-let ((indicator (ros2--filter-indicator ros2--topic-filter)))
      (vui-vstack (vui-text indicator) (ros2--topic-list))
    (ros2--topic-list)))

(defcustom ros2-update-debounce 0.1
  "Seconds to coalesce studio refreshes triggered by bridge or node events."
  :type 'number
  :group 'ros2)

(defvar ros2--update-timer nil
  "One-shot timer coalescing pending studio refreshes, or nil.")

(defun ros2--update ()
  "Redraw every visible studio panel and the mode-line.
Only visible panels are re-rendered; switching to a hidden one re-mounts it."
  (setq ros2--update-timer nil)
  (dolist (name '("*ros2-topics*" "*ros2-parameters*" "*ros2-messages*" "*ros2-log*"))
    (when-let ((buffer (get-buffer name)))
      (when (get-buffer-window buffer)
        (with-current-buffer buffer (vui-refresh)))))
  (when-let ((hub (get-buffer "*ros2-topics*")))
    (with-current-buffer hub (ros2--set-mode-line))))

(defun ros2--schedule-update ()
  "Request a debounced studio refresh, coalescing rapid events into one."
  (when (timerp ros2--update-timer) (cancel-timer ros2--update-timer))
  (setq ros2--update-timer (run-at-time ros2-update-debounce nil #'ros2--update)))

(defun ros2--add-channels (channels)
  "Store each entry of CHANNELS on the session, keyed by its id."
  (let ((table (ros2--session-channels ros2--session)))
    (dolist (channel channels)
      (puthash (alist-get 'id channel) channel table))))

(defun ros2--remove-channels (ids)
  "Drop the channels named in IDS from the session."
  (let ((table (ros2--session-channels ros2--session)))
    (dolist (id ids)
      (remhash id table))))

;;; Subscriptions (live message data)

(defun ros2--uint32-decode (bytes offset)
  "Read a little-endian `uint32' from BYTES starting at OFFSET."
  (logior (aref bytes offset)
          (ash (aref bytes (+ offset 1)) 8)
          (ash (aref bytes (+ offset 2)) 16)
          (ash (aref bytes (+ offset 3)) 24)))

(defun ros2--channel-for-topic (topic)
  "Return the advertised channel alist for TOPIC, or nil."
  (when ros2--session
    (catch 'found
      (maphash (lambda (_id channel)
                 (when (equal (alist-get 'topic channel) topic)
                   (throw 'found channel)))
               (ros2--session-channels ros2--session))
      nil)))

(defun ros2--topic-names ()
  "Return the advertised topic names, sorted."
  (when ros2--session
    (let (names)
      (maphash (lambda (_id channel) (push (alist-get 'topic channel) names))
               (ros2--session-channels ros2--session))
      (sort names #'string<))))

(defun ros2--subscribe (topic)
  "Subscribe to TOPIC through the bridge; return its subscription id or nil."
  (when-let ((channel (and (ros2--connected-p) (ros2--channel-for-topic topic))))
    (or (alist-get topic (ros2--session-subscriptions ros2--session) nil nil #'equal)
        (let ((sub-id (1+ (length (ros2--session-subscriptions ros2--session)))))
          (websocket-send-text
           (ros2--session-connection ros2--session)
           (json-encode
            `((op . "subscribe")
              (subscriptions
               . ,(vector `((id . ,sub-id)
                            (channelId . ,(alist-get 'id channel))))))))
          (setf (alist-get topic (ros2--session-subscriptions ros2--session) nil nil #'equal)
                sub-id)
          sub-id))))

(defun ros2--unsubscribe (topic)
  "Stop the subscription to TOPIC and forget its last message."
  (when-let ((sub-id (and ros2--session
                          (alist-get topic (ros2--session-subscriptions ros2--session)
                                     nil nil #'equal))))
    (when (ros2--connected-p)
      (websocket-send-text
       (ros2--session-connection ros2--session)
       (json-encode `((op . "unsubscribe") (subscriptionIds . ,(vector sub-id))))))
    (setf (alist-get topic (ros2--session-subscriptions ros2--session) nil 'remove #'equal) nil)
    (setf (alist-get topic (ros2--session-messages ros2--session) nil 'remove #'equal) nil)))

(defun ros2--on-binary (payload)
  "Decode a binary MessageData PAYLOAD, storing the latest message for its topic.
The frame is a 1-byte opcode, a `uint32' subscription id, a `uint64' timestamp,
then the CDR message."
  (when (and (> (length payload) 13) (= (aref payload 0) 1) ros2--session)
    (when-let* ((topic (ros2--topic-for-sub (ros2--uint32-decode payload 1)))
                (channel (ros2--channel-for-topic topic))
                (schema (alist-get 'schema channel)))
      (condition-case _err
          (progn
            (setf (alist-get topic (ros2--session-messages ros2--session) nil nil #'equal)
                  (ros2-cdr-decode schema (substring payload 13)))
            (ros2--schedule-update))
        (error nil)))))

(defun ros2--topic-for-sub (sub-id)
  "Return the topic subscribed under SUB-ID, or nil."
  (when ros2--session
    (car (rassoc sub-id (ros2--session-subscriptions ros2--session)))))

(defun ros2--handle-text (text)
  "Apply an incoming message TEXT to the session, then redraw."
  (condition-case nil
      (let* ((message (json-parse-string text
                                         :object-type 'alist :array-type 'list
                                         :null-object nil :false-object :false))
             (op (alist-get 'op message)))
        (pcase op
          ("serverInfo"      (setf (ros2--session-server-info ros2--session) message))
          ("advertise"       (ros2--add-channels (alist-get 'channels message)))
          ("unadvertise"     (ros2--remove-channels (alist-get 'channelIds message)))
          ("parameterValues" (ros2--set-parameters (alist-get 'parameters message))))
        (ros2--schedule-update))
    (json-parse-error nil)))

(defun ros2--on-message (_websocket frame)
  "Route an incoming text or binary FRAME to the right handler."
  (pcase (websocket-frame-opcode frame)
    ('text (ros2--handle-text (websocket-frame-payload frame)))
    ('binary (ros2--on-binary (websocket-frame-payload frame)))))

(defun ros2--disconnect ()
  "Close the session's connection if it is open."
  (when ros2--session
    (let ((connection (ros2--session-connection ros2--session)))
      (when (and connection (websocket-openp connection))
        (websocket-close connection)))
    (setf (ros2--session-connection ros2--session) nil
          (ros2--session-connected ros2--session) nil)))

(defun ros2--connect ()
  "Open (or reopen) the session's connection to the bridge.
Callbacks capture their session and act only while it is still current, so a
stale connection cannot corrupt a newer session."
  (ros2--disconnect)
  (let ((session ros2--session))
    (setf (ros2--session-channels session) (make-hash-table :test 'eql)
          (ros2--session-server-info session) nil)
    (condition-case nil
        (setf (ros2--session-connection session)
              (websocket-open
               ros2-url
               :protocols (list ros2-subprotocol)
               :on-open (lambda (ws)
                          (when (eq session ros2--session)
                            (setf (ros2--session-connected session) t)
                            (ros2--request-parameters ws)
                            (ros2--schedule-update)))
               :on-message (lambda (ws frame)
                             (when (eq session ros2--session)
                               (ros2--on-message ws frame)))
               :on-close (lambda (_ws)
                           (when (eq session ros2--session)
                             (setf (ros2--session-connected session) nil)
                             (ros2--schedule-update)))
               :on-error (lambda (_ws _type _err)
                           (when (eq session ros2--session)
                             (setf (ros2--session-connected session) nil)
                             (ros2--schedule-update)))))
      (error (setf (ros2--session-connected session) nil))))
  (ros2--schedule-update))

(defun ros2-disconnect ()
  "Close the connection."
  (declare (modes ros2-mode))
  (interactive)
  (ros2--disconnect)
  (ros2--schedule-update))

(defun ros2-reconnect ()
  "Reconnect to the bridge."
  (declare (modes ros2-mode))
  (interactive)
  (ros2--connect-with-retry))

;;; Commands

(defun ros2-node-open (node)
  "Open NODE's log if it is running, otherwise start it.
Defaults to the studio row at point.  Stopping is a separate key, `s'."
  (declare (modes ros2-mode))
  (interactive
   (list (or (ros2--node-at-point)
             (completing-read "Node: " ros2-nodes nil t))))
  (if (ros2--node-running-p node)
      (display-buffer (get-buffer-create (ros2--node-log-buffer-name node)))
    (ros2--start-node node)
    (display-buffer (get-buffer-create (ros2--node-log-buffer-name node)))
    (unless (ros2--connected-p) (ros2--connect-with-retry)))
  (ros2--schedule-update))

(defun ros2-node-stop (node)
  "Stop NODE, defaulting to the studio row at point."
  (declare (modes ros2-mode))
  (interactive
   (list (or (ros2--node-at-point)
             (completing-read "Stop node: " ros2-nodes nil t))))
  (ros2--stop-node node)
  (ros2--schedule-update))

(defun ros2-node-log (node)
  "Show NODE's log, defaulting to the studio row at point."
  (declare (modes ros2-mode))
  (interactive
   (list (or (ros2--node-at-point)
             (completing-read "Log for node: " ros2-nodes nil t))))
  (display-buffer (get-buffer-create (ros2--node-log-buffer-name node))))

(defun ros2--show-teleop ()
  "Show the teleop panel in its window."
  (ros2--display-buffer (ros2-teleop--buffer) 'ros2-teleop))

(defun ros2-toggle-teleop ()
  "Show or hide the teleop panel."
  (declare (modes ros2-mode))
  (interactive)
  (if-let ((window (get-buffer-window "*ros2-teleop*")))
      (delete-window window)
    (ros2--show-teleop)))

(defun ros2-quit ()
  "Close the studio."
  (declare (modes ros2-mode))
  (interactive)
  (when-let ((window (get-buffer-window "*ros2-teleop*")))
    (delete-window window))
  (quit-window))

;;; Orchestration

(defun ros2--start-autostart-nodes ()
  "Start the autostart nodes, recording what was started on the session."
  (dolist (node ros2-autostart-nodes)
    (unless (ros2--node-running-p node)
      (ros2--start-node node)
      (cl-pushnew node (ros2--session-started-nodes ros2--session) :test #'equal))))

(defun ros2--cancel-retry ()
  "Cancel the session's reconnect timer, if any."
  (when-let ((timer (and ros2--session (ros2--session-retry-timer ros2--session))))
    (cancel-timer timer)
    (setf (ros2--session-retry-timer ros2--session) nil)))

(defun ros2--retry-tick ()
  "Retry the session's connection until it connects or the limit is hit.
Skips a tick while a connection is already open, so one in progress is not
torn down."
  (when ros2--session
    (cond
     ((ros2--session-connected ros2--session) (ros2--cancel-retry))
     ((>= (ros2--session-retry-count ros2--session) ros2-connect-retry-limit)
      (ros2--cancel-retry))
     ((let ((connection (ros2--session-connection ros2--session)))
        (and connection (websocket-openp connection)))
      nil)
     (t (cl-incf (ros2--session-retry-count ros2--session))
        (ros2--connect)))))

(defun ros2--connect-with-retry ()
  "Connect, retrying on a timer until the bridge answers."
  (ros2--cancel-retry)
  (setf (ros2--session-retry-count ros2--session) 0)
  (ros2--connect)
  (setf (ros2--session-retry-timer ros2--session)
        (run-at-time ros2-connect-retry-interval ros2-connect-retry-interval
                     #'ros2--retry-tick)))

(defun ros2--teardown ()
  "Tear down the studio: stop timers, close the connection, maybe stop nodes."
  (ros2--cancel-retry)
  (ros2--disconnect)
  (when (and ros2-stop-nodes-on-quit ros2--session)
    (dolist (node (ros2--session-started-nodes ros2--session)) (ros2--stop-node node)))
  (setq ros2--session nil))

(defvar ros2-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'ros2-node-open)
    (define-key map "s"         #'ros2-node-stop)
    (define-key map "o"         #'ros2-node-log)
    (define-key map "t"         #'ros2-toggle-teleop)
    (define-key map "g"         #'ros2-reconnect)
    (define-key map "/"         #'ros2-filter-topics)
    (define-key map "p"         #'ros2-parameters)
    (define-key map "l"         #'ros2-log)
    (define-key map "q"         #'ros2-quit)
    map)
  "Keymap for `ros2-mode'.
RET opens a node (start it, or show its log if running); `s' stops it.
`/' filters the TOPICS list.
The teleop drive keys and SPC live only in the teleop window, not here.")

(declare-function evil-define-key* "evil-core")
(with-eval-after-load 'evil
  (evil-define-key* 'normal ros2-mode-map
    (kbd "RET") #'ros2-node-open
    "s"         #'ros2-node-stop
    "o"         #'ros2-node-log
    "t"         #'ros2-toggle-teleop
    "g"         #'ros2-reconnect
    "/"         #'ros2-filter-topics
    "p"         #'ros2-parameters
    "l"         #'ros2-log
    "q"         #'ros2-quit))

(define-derived-mode ros2-mode vui-mode "ros2-mode"
  "Major mode for the *ros2-topics* studio."
  (setq-local global-mode-string nil)
  (add-hook 'kill-buffer-hook #'ros2--teardown nil t))
(put 'ros2-mode 'completion-predicate #'ignore)

(with-eval-after-load 'nerd-icons
  (add-to-list 'nerd-icons-mode-icon-alist
               '(ros2-mode nerd-icons-devicon "nf-dev-ros" :face nerd-icons-blue)))

(defun ros2 (&optional url)
  "Open the ROS2 studio.
With a prefix argument, prompt for the bridge URL."
  (interactive
   (list (when current-prefix-arg
           (read-string "Bridge URL: " ros2-url))))
  (when url (setq ros2-url url))
  (when ros2--session
    (ros2--cancel-retry)
    (ros2--disconnect))
  (setq ros2--session (make-ros2--session))
  (let ((buffer (get-buffer-create "*ros2-topics*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'ros2-mode)
        (ros2-mode)))
    (save-window-excursion
      (vui-mount (vui-component 'ros2--studio) "*ros2-topics*"))
    (with-current-buffer buffer
      (ros2--ensure-services)
      (ros2--start-autostart-nodes)
      (ros2--connect-with-retry))
    ;; Place the panels; `ros2-window-arrangement' (and `display-buffer-alist') decide where.
    (when (eq ros2-window-arrangement 'studio)
      (let ((ignore-window-parameters t)) (delete-other-windows)))
    (ros2--display-buffer (ros2--parameters-buffer) 'ros2-parameters)
    (ros2--display-buffer buffer 'ros2-topics)
    (ros2--display-buffer (ros2-teleop--buffer) 'ros2-teleop)
    (when-let ((window (get-buffer-window buffer)))
      (select-window window))))

(when (fboundp 'set-popup-rule!)
  (eval '(set-popup-rule!
           (lambda (buffer-name &rest _)
             (and (boundp 'ros2-nodes)
                  (member buffer-name (mapcar #'ros2--node-log-buffer-name ros2-nodes))))
           :side 'bottom :size 0.3 :quit t :select nil :ttl nil)
        t))

(provide 'ros2)

;;; ros2.el ends here
