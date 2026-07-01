;;; ros2.el --- ROS2 support -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/ros2
;; Keywords: tools, robotics
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (websocket "1.15") (nerd-icons "0.1") (vui "0.1") (prodigy "1.0"))

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
(require 'prodigy)
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

(defcustom ros2-autostart-nodes nil
  "Nodes to start automatically when the studio opens.
Empty by default; start nodes yourself with `r' on a NODES row."
  :type '(repeat string)
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

(defcustom ros2-connect-retry-limit 20
  "How many times to retry the connection before giving up."
  :type 'integer
  :group 'ros2)

(defcustom ros2-status-refresh-interval 1.5
  "Seconds between refreshes of the node status."
  :type 'number
  :group 'ros2)

(defcustom ros2-node-ready-messages
  '(("bridge" . "Server listening on port"))
  "Alist mapping a node to a regexp that marks it ready when seen in its output.
A node with a ready regexp shows the launching spinner until the regexp
matches; a node without one is considered up once its process is live."
  :type '(alist :key-type string :value-type regexp)
  :group 'ros2)

(defcustom ros2-launch-grace 2.0
  "Seconds a node without a ready regexp spins before it is shown as up."
  :type 'number
  :group 'ros2)

(defvar-local ros2--connection nil
  "The `websocket' object for this buffer's connection, or nil.")

(defvar-local ros2--connected nil
  "Non-nil once the websocket handshake for this buffer has opened.")

(defvar-local ros2--server-info nil
  "The parsed `serverInfo' alist from the most recent connection, or nil.")

(defvar-local ros2--channels nil
  "Hash table mapping a channel id to its advertised channel alist.")

(defvar-local ros2--started-nodes nil
  "Nodes this studio autostarted, so quit can stop only what it started.")

(defvar-local ros2--retry-timer nil
  "Repeating timer retrying the bridge connection until it answers.")

(defvar-local ros2--retry-count 0
  "Number of bridge connection retries attempted so far.")

(defvar-local ros2--status-timer nil
  "Repeating timer that re-renders the studio to poll node liveness.")

(defvar-local ros2--started-at nil
  "Alist mapping a started node to the time it was last started.")

(defvar-local ros2--spinner-index 0
  "Frame counter for the launching spinner.")

(defvar-local ros2--spinner-timer nil
  "Fast timer animating the launching spinner, or nil when nothing launches.")

(defvar-local ros2--topic-filter ""
  "Active TOPICS filter: show only topics or schemas containing this string.")

(defun ros2--channel-rows ()
  "Return the advertised channel alists, sorted by topic."
  (let (rows)
    (when (hash-table-p ros2--channels)
      (maphash (lambda (_id channel) (push channel rows)) ros2--channels))
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

(defun ros2--topics-header ()
  "Return the TOPICS section heading, showing the active filter when set."
  (if (string-empty-p ros2--topic-filter)
      (propertize "  TOPICS" 'face 'shadow)
    (concat (propertize "  TOPICS   " 'face 'shadow)
            (propertize (format "⟨ %s ⟩" ros2--topic-filter) 'face 'ros2-filter))))

(defun ros2-filter-topics (filter)
  "Filter the TOPICS list to those matching FILTER.
Read FILTER in the minibuffer, seeded with the current one; empty clears it."
  (declare (modes ros2-mode))
  (interactive (list (read-string "Filter topics: " ros2--topic-filter)))
  (setq ros2--topic-filter (string-trim filter))
  (ros2--render))

(defun ros2--display-host ()
  "Return `ros2-url' with the `ws://' or `wss://' scheme stripped."
  (replace-regexp-in-string "\\`wss?://" "" ros2-url))


;;; Node lifecycle

(defun ros2--workspace ()
  "Return the directory the nodes are launched from."
  (or ros2-workspace default-directory))

(defun ros2--service-name (node)
  "Return the service name for NODE."
  (format "ros2:%s" node))

(defun ros2--node-log-buffer-name (node)
  "Return the log buffer name for NODE."
  (prodigy-buffer-name (list :name (ros2--service-name node))))

(defun ros2--ensure-service (node)
  "Return NODE's service, defining it on first use."
  (let ((name (ros2--service-name node)))
    (or (prodigy-find-service name)
        (progn
          (prodigy-define-service
            :name name
            :command ros2-pixi-executable
            :args (list "run" node)
            :cwd (ros2--workspace)
            :ready-message (alist-get node ros2-node-ready-messages nil nil #'equal)
            :stop-signal 'int
            :kill-process-buffer-on-stop 'unless-visible
            :tags '(ros2))
          (prodigy-find-service name)))))

(defun ros2--ensure-services ()
  "Define a service for every node in `ros2-nodes'."
  (dolist (node ros2-nodes) (ros2--ensure-service node)))

(defun ros2--node-ready-p (node service)
  "Non-nil when NODE's live SERVICE has reached its ready state.
Uses the ready regexp when one is set, else the launch grace period."
  (if (plist-get service :ready-message)
      (eq (plist-get service :status) 'ready)
    (let ((started (alist-get node ros2--started-at nil nil #'equal)))
      (or (null started)
          (> (float-time (time-subtract (current-time) started)) ros2-launch-grace)))))

(defun ros2--node-state (node)
  "Return NODE's supervisory state.
One of `stopped', `launching', `up', or `failed' -- derived from the service
process, since a crashed node keeps a dead process (`failed'), while a
user-stopped or never-run node has none (`stopped')."
  (let ((service (prodigy-find-service (ros2--service-name node))))
    (if (null service)
        'stopped
      (let ((process (plist-get service :process)))
        (cond
         ((null process) 'stopped)
         ((not (process-live-p process)) 'failed)
         ((ros2--node-ready-p node service) 'up)
         (t 'launching))))))

(defun ros2--node-running-p (node)
  "Non-nil when NODE's process is live (launching or up)."
  (memq (ros2--node-state node) '(launching up)))

(defun ros2--start-node (node)
  "Start NODE, show its log, and animate it until ready."
  (let ((service (ros2--ensure-service node)))
    (plist-put service :status nil)
    (setf (alist-get node ros2--started-at nil nil #'equal) (current-time))
    (prodigy-start-service service)
    (ros2--start-spinner)
    (display-buffer (get-buffer-create (prodigy-buffer-name service)))))

(defun ros2--stop-node (node)
  "Stop NODE."
  (when-let ((service (prodigy-find-service (ros2--service-name node))))
    (when (prodigy-service-started-p service)
      (prodigy-stop-service service))))

(defun ros2--node-at-point ()
  "Return the node named on the studio row at point, or nil."
  (get-text-property (point) 'ros2-node))

(defconst ros2--spinner-frames ["◐" "◓" "◑" "◒"]
  "Frames for the launching spinner: a filling circle that settles into `●'.")

(defun ros2--spinner-frame ()
  "Return the current launching-spinner glyph."
  (aref ros2--spinner-frames (mod ros2--spinner-index (length ros2--spinner-frames))))

(defun ros2--node-glyph (state)
  "Return the propertized status glyph for a node in STATE."
  (pcase state
    ('up        (propertize "●" 'face 'vui-success))
    ('launching (propertize (ros2--spinner-frame) 'face 'vui-warning))
    ('failed    (propertize "✕" 'face 'vui-error))
    (_          (propertize "○" 'face 'vui-muted))))

(defun ros2--process-exit-desc (process)
  "Describe how PROCESS ended, as `exit N' or `signal N'."
  (pcase (process-status process)
    ('exit   (format "exit %d" (process-exit-status process)))
    ('signal (format "signal %d" (process-exit-status process)))
    (status  (format "%s" status))))

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
  (when-let* ((service (prodigy-find-service (ros2--service-name node)))
              (process (plist-get service :process)))
    (let ((tail (ros2--node-log-tail node)))
      (concat (propertize (ros2--process-exit-desc process) 'face 'vui-error)
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
              (if ros2--connected
                  (nerd-icons-mdicon "nf-md-lan_connect" :face 'success)
                (nerd-icons-mdicon "nf-md-lan_disconnect" :face 'error))
              " "
              (propertize (ros2--display-host) 'face 'shadow)))
  (force-mode-line-update))

(defun ros2--topic-table ()
  "Return the topics as a table, filtered by `ros2--topic-filter'.
Shows a placeholder when nothing is advertised, or nothing matches the filter."
  (let ((rows (ros2--filter-channels (ros2--channel-rows) ros2--topic-filter)))
    (if rows
        (vui-table
         :header-face 'shadow
         :columns '((:header "TOPIC"    :width 34 :truncate t)
                    (:header "TYPE"     :width 30 :truncate t)
                    (:header "ENCODING"))
         :rows (mapcar
                (lambda (channel)
                  (list (or (alist-get 'topic channel) "")
                        (or (alist-get 'schemaName channel) "")
                        (or (alist-get 'encoding channel) "")))
                rows))
      (vui-text (propertize
                 (if (string-empty-p ros2--topic-filter)
                     "  (no channels advertised)"
                   (format "  (no topics match %S)" ros2--topic-filter))
                 'face 'shadow)))))

(vui-defcomponent ros2--studio ()
  "The studio: the NODES panel and the TOPICS list."
  :render
  (vui-vstack
   (vui-text (propertize "  NODES" 'face 'shadow))
   (mapcar (lambda (node) (vui-text (ros2--node-row node))) ros2-nodes)
   (vui-text "")
   (vui-text (ros2--topics-header))
   (ros2--topic-table)))

(defun ros2--render ()
  "Refresh the mode-line and redraw the studio."
  (ros2--set-mode-line)
  (vui-refresh))

(defun ros2--add-channels (channels)
  "Store each entry of CHANNELS, keyed by its id, in `ros2--channels'."
  (dolist (channel channels)
    (puthash (alist-get 'id channel) channel ros2--channels)))

(defun ros2--remove-channels (ids)
  "Drop the channels named in IDS from `ros2--channels'."
  (dolist (id ids)
    (remhash id ros2--channels)))

(defun ros2--handle-text (buffer text)
  "Apply an incoming message TEXT to BUFFER, then redraw."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (condition-case nil
          (let* ((message (json-parse-string text
                                             :object-type 'alist :array-type 'list
                                             :null-object nil :false-object nil))
                 (op (alist-get 'op message)))
            (pcase op
              ("serverInfo"  (setq ros2--server-info message))
              ("advertise"   (ros2--add-channels (alist-get 'channels message)))
              ("unadvertise" (ros2--remove-channels (alist-get 'channelIds message))))
            (ros2--render))
        (json-parse-error nil)))))

(defun ros2--on-message (buffer _websocket frame)
  "Handle an incoming FRAME for BUFFER (text frames only)."
  (when (eq (websocket-frame-opcode frame) 'text)
    (ros2--handle-text buffer (websocket-frame-payload frame))))

(defun ros2--disconnect ()
  "Close this buffer's connection if it is open."
  (when (and ros2--connection
             (websocket-openp ros2--connection))
    (websocket-close ros2--connection))
  (setq ros2--connection nil
        ros2--connected nil))

(defun ros2--connect ()
  "Open (or reopen) the connection for the current buffer."
  (ros2--disconnect)
  (setq ros2--channels (make-hash-table :test 'eql)
        ros2--server-info nil)
  (let ((buffer (current-buffer)))
    (condition-case nil
        (setq ros2--connection
              (websocket-open ros2-url
                              :protocols (list ros2-subprotocol)
                              :on-open (lambda (_ws)
                                         (when (buffer-live-p buffer)
                                           (with-current-buffer buffer
                                             (setq ros2--connected t)
                                             (ros2--render))))
                              :on-message (lambda (ws frame) (ros2--on-message buffer ws frame))
                              :on-close (lambda (_ws)
                                          (when (buffer-live-p buffer)
                                            (with-current-buffer buffer
                                              (setq ros2--connected nil)
                                              (ros2--render))))
                              :on-error (lambda (_ws _type _err)
                                          (when (buffer-live-p buffer)
                                            (with-current-buffer buffer
                                              (setq ros2--connected nil)
                                              (ros2--render))))))
      (error (setq ros2--connected nil))))
  (ros2--render))

(defun ros2-disconnect ()
  "Close the connection."
  (declare (modes ros2-mode))
  (interactive)
  (ros2--disconnect)
  (ros2--render))

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
    (unless ros2--connected (ros2--connect-with-retry)))
  (ros2--render))

(defun ros2-node-stop (node)
  "Stop NODE, defaulting to the studio row at point."
  (declare (modes ros2-mode))
  (interactive
   (list (or (ros2--node-at-point)
             (completing-read "Stop node: " ros2-nodes nil t))))
  (ros2--stop-node node)
  (ros2--render))

(defun ros2-node-log (node)
  "Show NODE's log, defaulting to the studio row at point."
  (declare (modes ros2-mode))
  (interactive
   (list (or (ros2--node-at-point)
             (completing-read "Log for node: " ros2-nodes nil t))))
  (display-buffer (get-buffer-create (ros2--node-log-buffer-name node))))

(defun ros2--show-teleop ()
  "Show the teleop panel in a side window."
  (display-buffer-in-side-window (ros2-teleop--buffer)
                                 '((side . right) (window-width . 26) (slot . 0) (dedicated . t))))

(defun ros2-toggle-teleop ()
  "Show or hide the teleop panel."
  (declare (modes ros2-mode))
  (interactive)
  (if-let ((window (get-buffer-window "*ros2:teleop*")))
      (delete-window window)
    (ros2--show-teleop)))

(defun ros2-quit ()
  "Close the studio."
  (declare (modes ros2-mode))
  (interactive)
  (when-let ((window (get-buffer-window "*ros2:teleop*")))
    (delete-window window))
  (quit-window))

;;; Orchestration

(defun ros2--start-autostart-nodes ()
  "Start the autostart nodes, recording what was started."
  (dolist (node ros2-autostart-nodes)
    (unless (ros2--node-running-p node)
      (ros2--start-node node)
      (cl-pushnew node ros2--started-nodes :test #'equal))))

(defun ros2--cancel-retry ()
  "Cancel the reconnect timer, if any."
  (when ros2--retry-timer
    (cancel-timer ros2--retry-timer)
    (setq ros2--retry-timer nil)))

(defun ros2--retry-tick (buffer)
  "Retry the connection for BUFFER until it connects or the limit is hit.
Skips a tick while a connection is already open, so one in progress is not
torn down."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (cond
       (ros2--connected (ros2--cancel-retry))
       ((>= ros2--retry-count ros2-connect-retry-limit) (ros2--cancel-retry))
       ((and ros2--connection (websocket-openp ros2--connection)) nil)
       (t (cl-incf ros2--retry-count) (ros2--connect))))))

(defun ros2--connect-with-retry ()
  "Connect, retrying on a timer until the bridge answers."
  (ros2--cancel-retry)
  (setq ros2--retry-count 0)
  (ros2--connect)
  (let ((buffer (current-buffer)))
    (setq ros2--retry-timer
          (run-at-time ros2-connect-retry-interval ros2-connect-retry-interval
                       #'ros2--retry-tick buffer))))

(defun ros2--cancel-status-timer ()
  "Cancel the studio's node-liveness poll timer, if any."
  (when ros2--status-timer
    (cancel-timer ros2--status-timer)
    (setq ros2--status-timer nil)))

(defun ros2--start-status-timer ()
  "Refresh the node status on a timer."
  (ros2--cancel-status-timer)
  (let ((buffer (current-buffer)))
    (setq ros2--status-timer
          (run-at-time ros2-status-refresh-interval ros2-status-refresh-interval
                       (lambda ()
                         (when (buffer-live-p buffer)
                           (with-current-buffer buffer (ros2--render))))))))

(defun ros2--any-launching-p ()
  "Non-nil when any node is currently launching."
  (seq-some (lambda (node) (eq (ros2--node-state node) 'launching)) ros2-nodes))

(defun ros2--stop-spinner ()
  "Stop the launching-spinner animation timer, if running."
  (when ros2--spinner-timer
    (cancel-timer ros2--spinner-timer)
    (setq ros2--spinner-timer nil)))

(defun ros2--spinner-tick (buffer)
  "Advance the spinner in BUFFER, stopping the timer once nothing is launching."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (unless (ros2--any-launching-p)
        (ros2--stop-spinner))
      (setq ros2--spinner-index (1+ ros2--spinner-index))
      (ros2--render))))

(defun ros2--start-spinner ()
  "Start animating the launching spinner unless it is already running."
  (unless ros2--spinner-timer
    (let ((buffer (current-buffer)))
      (setq ros2--spinner-timer
            (run-at-time 0 0.12 #'ros2--spinner-tick buffer)))))

(defun ros2--teardown ()
  "Tear down the studio: stop timers, close the connection, maybe stop nodes."
  (ros2--cancel-retry)
  (ros2--cancel-status-timer)
  (ros2--stop-spinner)
  (ros2--disconnect)
  (when ros2-stop-nodes-on-quit
    (dolist (node ros2--started-nodes) (ros2--stop-node node))))

(defvar ros2-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "RET") #'ros2-node-open)
    (define-key map "s"         #'ros2-node-stop)
    (define-key map "o"         #'ros2-node-log)
    (define-key map "t"         #'ros2-toggle-teleop)
    (define-key map "g"         #'ros2-reconnect)
    (define-key map "/"         #'ros2-filter-topics)
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
    "q"         #'ros2-quit))

(define-derived-mode ros2-mode vui-mode "ros2-mode"
  "Major mode for the *ros2* studio."
  (setq-local ros2--channels (make-hash-table :test 'eql))
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
  (let ((buffer (get-buffer-create "*ros2*")))
    (with-current-buffer buffer
      (unless (derived-mode-p 'ros2-mode)
        (ros2-mode)))
    (vui-mount (vui-component 'ros2--studio) "*ros2*")
    (with-current-buffer buffer
      (ros2--ensure-services)
      (ros2--start-autostart-nodes)
      (ros2--connect)
      (ros2--start-status-timer))
    (delete-other-windows (get-buffer-window buffer))
    (ros2--show-teleop)
    (select-window (get-buffer-window buffer))))

(when (fboundp 'set-popup-rule!)
  (eval '(set-popup-rule!
           (lambda (buffer-name &rest _)
             (and (boundp 'ros2-nodes)
                  (member buffer-name (mapcar #'ros2--node-log-buffer-name ros2-nodes))))
           :side 'bottom :size 0.3 :quit t :select nil :ttl nil)
        t))

(provide 'ros2)

;;; ros2.el ends here
