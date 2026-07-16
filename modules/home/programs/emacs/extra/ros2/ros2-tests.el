;;; ros2-tests.el --- Buttercup tests for ros2.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'ros2)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(buttercup-define-matcher :to-render-substrings (rendered substrings)
  "Match a rendered string when every entry in SUBSTRINGS appears in it."
  (let ((text (funcall rendered))
         (subs (funcall substrings)))
    (let ((missing (seq-remove (lambda (s) (string-match-p (regexp-quote s) text)) subs)))
      (if (null missing)
        (cons t  (format "Expected rendered string NOT to contain all of %S" subs))
        (cons nil (format "Expected rendered string to contain %S, missing %S" subs missing))))))

(buttercup-define-matcher :to-list-topics (rows expected-topics)
  "Match `ros2--channel-rows' output by the topic of each row, in order."
  (let ((actual   (mapcar (lambda (channel) (alist-get 'topic channel)) (funcall rows)))
         (expected (funcall expected-topics)))
    (if (equal actual expected)
      (cons t  (format "Expected rows NOT to list topics %S" expected))
      (cons nil (format "Expected rows to list topics %S, got %S" expected actual)))))

(defconst ros2-tests--fixtures-dir
  (expand-file-name "fixtures/"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding the `ros2-<op>.json' Foxglove control-frame fixtures.")

(defun ros2-tests--fixture (name)
  "Return the contents of `fixtures/NAME' as a string.
Safe to call from inside spec bodies; the directory is resolved at load time."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name ros2-tests--fixtures-dir))
    (buffer-string)))

(defun ros2-tests--hex (bytes)
  "Return unibyte string BYTES as a lowercase hex string."
  (mapconcat (lambda (b) (format "%02x" b)) bytes ""))

(defun ros2-tests--bytes (name)
  "Read fixtures/NAME (a hex string) into a unibyte byte string."
  (let* ((hex (string-trim (ros2-tests--fixture name)))
         (count (/ (length hex) 2)))
    (apply #'unibyte-string
           (cl-loop for i below count
                    collect (string-to-number (substring hex (* 2 i) (+ 2 (* 2 i))) 16)))))

(defun ros2-tests--schema (topic)
  "Return the ros2msg schema the advertise fixture carries for TOPIC."
  (let* ((data (json-parse-string (ros2-tests--fixture "ros2-advertise.json")
                                  :object-type 'alist :array-type 'list))
         (channel (seq-find (lambda (c) (equal (alist-get 'topic c) topic))
                            (alist-get 'channels data))))
    (alist-get 'schema channel)))

(defconst ros2-tests--fixture-manifest
  '("ros2-server-info.json"
     "ros2-advertise.json"
     "ros2-unadvertise.json")
  "Captured Foxglove WebSocket control frames driving the spec suite.
These are representative frames; recapture them from a live bridge when
the protocol shape needs re-verifying.")

(defmacro ros2-tests--with-dashboard (&rest body)
  "Run BODY with a fresh `ros2--session' in a `ros2-mode' buffer."
  (declare (indent 0))
  `(let ((ros2--session (make-ros2--session)))
     (with-temp-buffer
       (ros2-mode)
       ,@body)))

(describe "every captured fixture"
  (dolist (name ros2-tests--fixture-manifest)
    (it (format "%s parses as non-empty JSON" name)
      (let ((content (ros2-tests--fixture name)))
        (expect (length content) :to-be-greater-than 0)
        (expect (json-parse-string content) :not :to-throw)))))

(describe "ros2--add-channels / ros2--remove-channels"
  (it "stores a channel keyed by its id and drops it again"
    (ros2-tests--with-dashboard
      (ros2--add-channels '(((id . 7) (topic . "/clock"))))
      (expect (alist-get 'topic (gethash 7 (ros2--channels))) :to-equal "/clock")
      (ros2--remove-channels '(7))
      (expect (gethash 7 (ros2--channels)) :not :to-be-truthy))))

(describe "ros2--handle-text"
  (describe "serverInfo"
    (it "captures the server capabilities and supported encodings"
      (ros2-tests--with-dashboard
        (ros2--handle-text
          (ros2-tests--fixture "ros2-server-info.json"))
        (expect (member "cdr" (alist-get 'supportedEncodings (ros2--server-info))) :to-be-truthy)
        (expect (member "services" (alist-get 'capabilities (ros2--server-info))) :to-be-truthy))))

  (describe "advertise"
    (it "stores every advertised channel keyed by id"
      (ros2-tests--with-dashboard
        (ros2--handle-text
          (ros2-tests--fixture "ros2-advertise.json"))
        (expect (hash-table-count (ros2--channels)) :to-equal 11)
        (expect (alist-get 'topic (gethash 7 (ros2--channels))) :to-equal "/odom")))

    (it "lists channels sorted by topic"
      (ros2-tests--with-dashboard
        (ros2--handle-text
          (ros2-tests--fixture "ros2-advertise.json"))
        (expect (ros2--channel-rows)
          :to-list-topics '("/battery" "/camera/camera_info" "/camera/image_raw"
                            "/cmd_vel" "/gps/fix" "/joint_states" "/odom"
                            "/parameter_events" "/rosout" "/tf" "/tf_static")))))

  (describe "unadvertise"
    (it "drops the named channels"
      (ros2-tests--with-dashboard
        (ros2--handle-text
          (ros2-tests--fixture "ros2-advertise.json"))
        (ros2--handle-text
          (ros2-tests--fixture "ros2-unadvertise.json"))
        (expect (hash-table-count (ros2--channels)) :to-equal 10)
        (expect (mapcar (lambda (c) (alist-get 'topic c)) (ros2--channel-rows))
          :not :to-contain "/odom"))))

  (describe "malformed input"
    (it "ignores a non-JSON frame without signaling"
      (ros2-tests--with-dashboard
        (expect (ros2--handle-text "not json {[")
          :not :to-throw)))

    (it "ignores an unrecognized op without touching state"
      (ros2-tests--with-dashboard
        (ros2--handle-text "{\"op\":\"someUnknownOp\"}")
        (expect (hash-table-count (ros2--channels)) :to-equal 0)
        (expect (ros2--server-info) :not :to-be-truthy)))))

(describe "ros2--float64-le"
  (it "encodes doubles as little-endian IEEE-754"
    (expect (ros2-tests--hex (ros2--float64-le 1.0)) :to-equal "000000000000f03f")
    (expect (ros2-tests--hex (ros2--float64-le 2.0)) :to-equal "0000000000000040")
    (expect (ros2-tests--hex (ros2--float64-le 0.0)) :to-equal "0000000000000000")))

(describe "ros2--uint32-le"
  (it "encodes integers as little-endian"
    (expect (ros2-tests--hex (ros2--uint32-le 1)) :to-equal "01000000")
    (expect (ros2-tests--hex (ros2--uint32-le 258)) :to-equal "02010000")))

(describe "ros2--encode-twist"
  (it "matches ROS2's own CDR bytes for a known Twist"
    (expect (ros2-tests--hex (ros2--encode-twist '(1.0 2.0 3.0) '(4.0 5.0 6.0)))
      :to-equal (concat "00010000"
                        "000000000000f03f" "0000000000000040" "0000000000000840"
                        "0000000000001040" "0000000000001440" "0000000000001840"))))

(describe "ros2--bridge-url"
  (it "assembles scheme, host, and port into a URL"
    (let ((ros2-bridge-scheme "ws")
           (ros2-bridge-host "127.0.0.1")
           (ros2-bridge-port 8765))
      (expect (ros2--bridge-url) :to-equal "ws://127.0.0.1:8765")))

  (it "honours a wss scheme and a custom host and port"
    (let ((ros2-bridge-scheme "wss")
           (ros2-bridge-host "example.com")
           (ros2-bridge-port 9090))
      (expect (ros2--bridge-url) :to-equal "wss://example.com:9090")))

  (it "defaults to the local foxglove bridge"
    (expect (ros2--bridge-url) :to-equal "ws://127.0.0.1:8765")))

(describe "ros2--display-host"
  (it "joins the configured host and port"
    (let ((ros2-bridge-host "localhost") (ros2-bridge-port 8765))
      (expect (ros2--display-host) :to-equal "localhost:8765")))

  (it "reflects a custom host and port"
    (let ((ros2-bridge-host "rpi5-16-2") (ros2-bridge-port 9090))
      (expect (ros2--display-host) :to-equal "rpi5-16-2:9090"))))

(describe "ros2--set-mode-line"
  :var (icon-names)
  (before-each
    (setq icon-names nil)
    (spy-on 'nerd-icons-mdicon
      :and-call-fake (lambda (name &rest _) (push name icon-names) "")))

  (it "shows the connected glyph and the host and port when connected"
    (ros2-tests--with-dashboard
      (let ((ros2-bridge-host "localhost") (ros2-bridge-port 8765))
        (setf (ros2--session-connected ros2--session) t)
        (ros2--set-mode-line)
        (let ((joined (apply #'concat (seq-filter #'stringp (flatten-list mode-line-process)))))
          (expect joined :to-match "localhost:8765")
          (expect icon-names :to-contain "nf-md-lan_connect")))))

  (it "shows the disconnected glyph when not connected"
    (ros2-tests--with-dashboard
      (setf (ros2--session-connected ros2--session) nil)
      (ros2--set-mode-line)
      (expect icon-names :to-contain "nf-md-lan_disconnect")))

  (it "leaves `mode-name' untouched so ibuffer's Mode column stays `ros2-mode'"
    (ros2-tests--with-dashboard
      (setf (ros2--session-connected ros2--session) t)
      (ros2--set-mode-line)
      (expect mode-name :to-equal "ros2-mode"))))

(describe "ros2--topic-list"
  (it "renders each topic as a bold name over its dimmed schema"
    (ros2-tests--with-dashboard
      (ros2--handle-text
        (ros2-tests--fixture "ros2-advertise.json"))
      (let ((vnode (ros2--topic-list)))
        (with-temp-buffer
          (vui-render vnode)
          (expect (buffer-string) :to-render-substrings
            '("/odom" "nav_msgs/msg/Odometry" "─"))
          (goto-char (point-min))
          (search-forward "/odom")
          (expect (get-text-property (match-beginning 0) 'face) :to-equal 'ros2-topic))))))

(describe "ros2--filter-channels"
  (let ((channels '(((topic . "/odom")    (schemaName . "nav_msgs/msg/Odometry"))
                    ((topic . "/battery") (schemaName . "sensor_msgs/msg/BatteryState"))
                    ((topic . "/cmd_vel") (schemaName . "geometry_msgs/msg/Twist")))))
    (it "returns every channel when the filter is empty"
      (expect (ros2--filter-channels channels "") :to-equal channels))
    (it "keeps only channels whose topic contains the filter"
      (expect (mapcar (lambda (channel) (alist-get 'topic channel))
                (ros2--filter-channels channels "batt"))
        :to-equal '("/battery")))
    (it "matches against the schema name too"
      (expect (mapcar (lambda (channel) (alist-get 'topic channel))
                (ros2--filter-channels channels "Twist"))
        :to-equal '("/cmd_vel")))
    (it "is case-insensitive"
      (expect (mapcar (lambda (channel) (alist-get 'topic channel))
                (ros2--filter-channels channels "ODOM"))
        :to-equal '("/odom")))
    (it "returns nothing when no channel matches"
      (expect (ros2--filter-channels channels "zzz") :to-equal nil))))

(describe "ros2--topic-list filtering"
  (it "renders only the topics matching ros2--topic-filter"
    (ros2-tests--with-dashboard
      (ros2--handle-text
        (ros2-tests--fixture "ros2-advertise.json"))
      (setq ros2--topic-filter "gps")
      (let ((vnode (ros2--topic-list)))
        (with-temp-buffer
          (vui-render vnode)
          (expect (buffer-string) :to-render-substrings '("/gps/fix" "NavSatFix"))
          (expect (buffer-string) :not :to-render-substrings '("/odom"))))))

  (it "falls back to a filter-aware placeholder when nothing matches"
    (ros2-tests--with-dashboard
      (ros2--handle-text
        (ros2-tests--fixture "ros2-advertise.json"))
      (setq ros2--topic-filter "nomatch")
      (let ((vnode (ros2--topic-list)))
        (with-temp-buffer
          (vui-render vnode)
          (expect (buffer-string) :to-render-substrings '("no topics match")))))))

(describe "ros2--filter-indicator"
  (it "is nil when the filter is empty"
    (expect (ros2--filter-indicator "") :to-be nil))
  (it "shows the active filter"
    (expect (ros2--filter-indicator "gps") :to-render-substrings '("gps"))))

(describe "ros2--panel-tabs"
  (it "labels the center panels and highlights the active one"
    (let ((bar (ros2--panel-tabs 'ros2-log)))
      (expect bar :to-render-substrings '("Parameters" "Messages" "Log"))
      (expect (text-property-any 0 (length bar) 'face 'ros2-tab-active bar) :to-be-truthy))))

(describe "ros2--adjacent-panel"
  (it "cycles forward through the center panels, wrapping"
    (expect (ros2--adjacent-panel 'ros2-parameters 1) :to-equal 'ros2-messages)
    (expect (ros2--adjacent-panel 'ros2-messages 1) :to-equal 'ros2-log)
    (expect (ros2--adjacent-panel 'ros2-log 1) :to-equal 'ros2-parameters))
  (it "cycles backward, wrapping"
    (expect (ros2--adjacent-panel 'ros2-parameters -1) :to-equal 'ros2-log))
  (it "starts from the first panel for an unknown command"
    (expect (ros2--adjacent-panel nil 1) :to-equal 'ros2-messages)))

(describe "ros2--message-alist-p"
  (it "recognises a decoded message but not an array of scalars or messages"
    (expect (ros2--message-alist-p '(("a" . 1) ("b" . 2))) :to-be-truthy)
    (expect (ros2--message-alist-p '(1 2 3)) :to-be nil)
    (expect (ros2--message-alist-p '((("a" . 1)) (("a" . 2)))) :to-be nil)))

(describe "ros2--format-message"
  (it "renders scalars, a nested message, and an array as an indented tree"
    (let ((tree (ros2--format-message
                 '(("latitude" . 45.4215)
                   ("status" . (("status" . 0) ("service" . 1)))
                   ("cov" . (1.0 2.0 3.0))
                   ("present" . t)))))
      (expect tree :to-match "latitude")
      (expect tree :to-match "45.4215")
      (expect tree :to-match "service")
      (expect tree :to-match "\\[3\\]")
      (expect tree :to-match "true"))))

(describe "ros2--on-binary"
  (it "strips the frame wrapper, decodes the CDR, and stores it for the topic"
    (let ((ros2--session (make-ros2--session)))
      (setf (ros2--session-connected ros2--session) t)
      (puthash 5 `((id . 5) (topic . "/gps/fix")
                   (schemaName . "sensor_msgs/msg/NavSatFix")
                   (schema . ,(ros2-tests--schema "/gps/fix")))
               (ros2--session-channels ros2--session))
      (setf (alist-get "/gps/fix" (ros2--session-subscriptions ros2--session) nil nil #'equal)
            101)
      (ros2--on-binary (ros2-tests--bytes "ros2-navsatfix.frame.hex"))
      (let ((msg (alist-get "/gps/fix" (ros2--session-messages ros2--session)
                            nil nil #'equal)))
        (expect (alist-get "latitude" msg nil nil #'equal) :to-be-close-to 45.4215 4)))))

(describe "center-panel tab navigation"
  (it "binds TAB and backtab in both center panel maps"
    (expect (lookup-key ros2-parameters-mode-map (kbd "TAB")) :to-equal #'ros2-next-panel)
    (expect (lookup-key ros2-parameters-mode-map (kbd "<backtab>")) :to-equal #'ros2-previous-panel)
    (expect (lookup-key ros2-log-mode-map (kbd "TAB")) :to-equal #'ros2-next-panel)
    (expect (lookup-key ros2-log-mode-map (kbd "<backtab>")) :to-equal #'ros2-previous-panel)))

(describe "ros2-filter-topics"
  (it "sets the filter, trimming surrounding whitespace"
    (ros2-tests--with-dashboard
      (ros2-filter-topics "  gps ")
      (expect ros2--topic-filter :to-equal "gps")))

  (it "clears the filter on empty input"
    (ros2-tests--with-dashboard
      (setq ros2--topic-filter "gps")
      (ros2-filter-topics "")
      (expect ros2--topic-filter :to-equal ""))))

(describe "ros2--format-parameter-value"
  (it "renders booleans as true/false"
    (expect (substring-no-properties (ros2--format-parameter-value t)) :to-equal "true")
    (expect (substring-no-properties (ros2--format-parameter-value :false)) :to-equal "false"))
  (it "renders numbers unquoted"
    (expect (substring-no-properties (ros2--format-parameter-value 20.0)) :to-equal "20.0")
    (expect (substring-no-properties (ros2--format-parameter-value 5)) :to-equal "5"))
  (it "renders strings quoted"
    (expect (substring-no-properties (ros2--format-parameter-value "keep_last"))
      :to-equal "\"keep_last\""))
  (it "colours a number with the number face"
    (expect (get-text-property 0 'face (ros2--format-parameter-value 5))
      :to-equal 'ros2-param-number)))

(describe "ros2--handle-text parameterValues"
  (it "stores the reported parameters"
    (ros2-tests--with-dashboard
      (ros2--handle-text
        (ros2-tests--fixture "ros2-parameter-values.json"))
      (expect (length (ros2--parameters)) :to-be-greater-than 10)
      (let ((freq (seq-find (lambda (p) (equal (alist-get 'name p)
                                          "/robot_state_publisher.publish_frequency"))
                    (ros2--parameters))))
        (expect (alist-get 'value freq) :to-equal 20.0)))))

(describe "ros2--parameter-rows"
  (it "sorts parameters by name"
    (ros2-tests--with-dashboard
      (setf (ros2--session-parameters ros2--session)
            '(((name . "/b.z") (value . 1))
              ((name . "/a.y") (value . 2))))
      (expect (mapcar (lambda (p) (alist-get 'name p)) (ros2--parameter-rows))
        :to-equal '("/a.y" "/b.z")))))

(describe "ros2--parameter-table"
  (it "renders each parameter name and its coloured value"
    (ros2-tests--with-dashboard
      (ros2--handle-text
        (ros2-tests--fixture "ros2-parameter-values.json"))
      (let ((vnode (ros2--parameter-table)))
        (with-temp-buffer
          (vui-render vnode)
          (expect (buffer-string) :to-render-substrings
            '("/robot_state_publisher.publish_frequency" "20.0" "\"keep_last\"")))))))

(describe "ros2--parse-log-line"
  (it "parses a structured rclcpp line into level, node, and message"
    (let ((entry (ros2--parse-log-line
                  "[INFO] [1700000000.000000000] [talker]: Publishing: 'Hello World: 1'")))
      (expect (plist-get entry :level) :to-equal 'info)
      (expect (plist-get entry :node) :to-equal "talker")
      (expect (plist-get entry :message) :to-equal "Publishing: 'Hello World: 1'")))
  (it "strips the launch process prefix"
    (let ((entry (ros2--parse-log-line
                  "[foxglove_bridge-3] [INFO] [1.0] [foxglove_bridge]: Server listening on port 8765")))
      (expect (plist-get entry :level) :to-equal 'info)
      (expect (plist-get entry :node) :to-equal "foxglove_bridge")))
  (it "recognises WARN and ERROR levels"
    (expect (plist-get (ros2--parse-log-line "[WARN] [1.0] [n]: x") :level) :to-equal 'warn)
    (expect (plist-get (ros2--parse-log-line "[ERROR] [1.0] [n]: x") :level) :to-equal 'error))
  (it "keeps an unstructured line as a level-less message"
    (let ((entry (ros2--parse-log-line "[ros2run]: Received signal:  Interrupt: 2")))
      (expect (plist-get entry :level) :to-be nil)
      (expect (plist-get entry :message)
        :to-equal "[ros2run]: Received signal:  Interrupt: 2"))))

(describe "ros2--log-level-value"
  (it "orders debug < info < warn < error"
    (expect (< (ros2--log-level-value 'debug) (ros2--log-level-value 'info)) :to-be-truthy)
    (expect (< (ros2--log-level-value 'info) (ros2--log-level-value 'warn)) :to-be-truthy)
    (expect (< (ros2--log-level-value 'warn) (ros2--log-level-value 'error)) :to-be-truthy)))

(describe "ros2--filter-log-entries"
  (let ((entries '((:level info :node "n" :message "hello")
                   (:level warn :node "n" :message "careful")
                   (:level error :node "n" :message "boom")
                   (:level nil :node nil :message "raw noise"))))
    (it "drops entries below the minimum level but keeps unstructured lines"
      (expect (mapcar (lambda (e) (plist-get e :message))
                (ros2--filter-log-entries entries 'warn ""))
        :to-equal '("careful" "boom" "raw noise")))
    (it "keeps only entries matching the search string"
      (expect (mapcar (lambda (e) (plist-get e :message))
                (ros2--filter-log-entries entries 'debug "boom"))
        :to-equal '("boom")))))

(describe "ros2--format-log-entry"
  (it "colours a warning with the warn face"
    (let ((line (ros2--format-log-entry '(:level warn :node "talker" :message "x"))))
      (expect line :to-render-substrings '("WARN" "talker" "x"))
      (expect (text-property-any 0 (length line) 'face 'ros2-log-warn line) :to-be-truthy)))
  (it "renders an unstructured line dimmed"
    (expect (ros2--format-log-entry '(:level nil :node nil :message "raw"))
      :to-render-substrings '("raw"))))

(describe "log pipeline against the fixture"
  (it "parses every fixture line and an error filter keeps errors plus noise"
    (let* ((lines (split-string (ros2-tests--fixture "ros2-log-sample.txt") "\n" t))
           (entries (mapcar #'ros2--parse-log-line lines)))
      (expect (length entries) :to-equal 6)
      (expect (mapcar (lambda (e) (plist-get e :level))
                (ros2--filter-log-entries entries 'error ""))
        :to-equal '(error nil)))))

(describe "ros2--workspace"
  (it "is nil by default, deferring to the daemon's monorepo-root cwd"
    (let ((ros2-workspace nil))
      (expect (ros2--workspace) :to-be nil)))
  (it "expands an explicit override so the daemon can stat it"
    (let ((ros2-workspace "~/elsewhere/"))
      (expect (ros2--workspace)
              :to-equal (expand-file-name "~/elsewhere/")))))

(describe "node lifecycle helpers"
  (it "names each node's process-compose log buffer"
    (expect (ros2--node-log-buffer-name "bridge")
      :to-equal "*process-compose-log:ros2:bridge*"))

  (it "reports an undefined/unstarted node as stopped, and not running"
    (expect (ros2--node-state "no-such-node-running") :to-equal 'stopped)
    (expect (ros2--node-running-p "no-such-node-running") :not :to-be-truthy))

  (it "maps each state to a distinct, color-coded glyph"
    (expect (substring-no-properties (ros2--node-glyph 'stopped)) :to-equal "○")
    (expect (substring-no-properties (ros2--node-glyph 'up)) :to-equal "●")
    (expect (substring-no-properties (ros2--node-glyph 'failed)) :to-equal "✕")
    (expect (get-text-property 0 'face (ros2--node-glyph 'up)) :to-equal 'vui-success)
    (expect (get-text-property 0 'face (ros2--node-glyph 'failed)) :to-equal 'vui-error))

  (it "tags a node row with its name and shows no redundant status word"
    (let ((row (substring-no-properties (ros2--node-row "bridge"))))
      (expect (get-text-property 0 'ros2-node (ros2--node-row "bridge")) :to-equal "bridge")
      (expect row :to-match "bridge")
      (expect row :not :to-match "running")
      (expect row :not :to-match "stopped"))))

(describe "ros2-mode-map (the studio window)"
  (it "binds the node lifecycle and studio keys"
    (expect (lookup-key ros2-mode-map (kbd "RET")) :to-equal #'ros2-node-open)
    (expect (lookup-key ros2-mode-map "s") :to-equal #'ros2-node-stop)
    (expect (lookup-key ros2-mode-map "o") :to-equal #'ros2-node-log)
    (expect (lookup-key ros2-mode-map "t") :to-equal #'ros2-toggle-teleop)
    (expect (lookup-key ros2-mode-map "g") :to-equal #'ros2-reconnect)
    (expect (lookup-key ros2-mode-map "/") :to-equal #'ros2-filter-topics)
    (expect (lookup-key ros2-mode-map "p") :to-equal #'ros2-parameters)
    (expect (lookup-key ros2-mode-map "l") :to-equal #'ros2-log))

  (it "keeps the teleop drive keys and SPC OUT of the studio map"
    (let ((own (copy-keymap ros2-mode-map)))
      (set-keymap-parent own nil)
      (expect (lookup-key own (kbd "SPC")) :not :to-be-truthy)
      (expect (lookup-key own "i") :not :to-be-truthy))))

(describe "M-x visibility"
  (it "exposes `ros2' as a global command"
    (expect (commandp 'ros2) :to-be-truthy)
    (expect (command-modes 'ros2) :not :to-be-truthy))

  (it "scopes `ros2-disconnect' to ros2-mode buffers"
    (expect (command-modes 'ros2-disconnect) :to-equal '(ros2-mode)))

  (it "scopes `ros2-reconnect' to ros2-mode buffers"
    (expect (command-modes 'ros2-reconnect) :to-equal '(ros2-mode)))

  (it "scopes the node lifecycle commands to ros2-mode buffers"
    (expect (command-modes 'ros2-node-open) :to-equal '(ros2-mode))
    (expect (command-modes 'ros2-node-stop) :to-equal '(ros2-mode))
    (expect (command-modes 'ros2-node-log) :to-equal '(ros2-mode))
    (expect (command-modes 'ros2-toggle-teleop) :to-equal '(ros2-mode))
    (expect (command-modes 'ros2-filter-topics) :to-equal '(ros2-mode))
    (expect (command-modes 'ros2-parameters) :to-equal '(ros2-mode))
    (expect (command-modes 'ros2-log) :to-equal '(ros2-mode)))

  (it "hides `ros2-mode' from M-x entirely"
    (expect (get 'ros2-mode 'completion-predicate) :to-equal #'ignore)))

(describe "ros2-tasks"
  (before-each (spy-on 'ros2--in-workspace-p :and-return-value t))

  (it "offers topic list under the ros2 namespace, tooled as ros2"
    (let ((task (car (ros2-tasks))))
      (expect (plist-get task :name) :to-equal "topic list")
      (expect (plist-get task :namespace) :to-equal "ros2")
      (expect (plist-get task :icon) :to-equal (nerd-icons-mdicon "nf-md-rss"))
      (expect (plist-get task :tool) :to-equal "ros2")
      (expect (plist-get task :command)
        :to-equal "cargo run -rp robot --bin ros2 -- topic list"))))

(describe "ros2--compile-multi-tasks"
  (it "feeds every robot task through microvisor-task"
    (spy-on 'ros2--in-workspace-p :and-return-value t)
    (cl-letf (((symbol-function 'microvisor-task)
                (lambda (task) (plist-get task :name))))
      (expect (ros2--compile-multi-tasks) :to-equal '("topic list")))))

;;; ros2-tests.el ends here
