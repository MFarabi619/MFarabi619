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

(defconst ros2-tests--fixture-manifest
  '("ros2-server-info.json"
     "ros2-advertise.json"
     "ros2-unadvertise.json")
  "Captured Foxglove WebSocket control frames driving the spec suite.
These are representative frames; recapture them from a live bridge when
the protocol shape needs re-verifying.")

(defmacro ros2-tests--with-dashboard (&rest body)
  "Run BODY in a fresh `ros2-mode' buffer (no live connection)."
  (declare (indent 0))
  `(with-temp-buffer
     (ros2-mode)
     ,@body))

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
      (expect (alist-get 'topic (gethash 7 ros2--channels)) :to-equal "/clock")
      (ros2--remove-channels '(7))
      (expect (gethash 7 ros2--channels) :not :to-be-truthy))))

(describe "ros2--handle-text"
  (describe "serverInfo"
    (it "captures the server capabilities and supported encodings"
      (ros2-tests--with-dashboard
        (ros2--handle-text (current-buffer)
          (ros2-tests--fixture "ros2-server-info.json"))
        (expect (member "cdr" (alist-get 'supportedEncodings ros2--server-info)) :to-be-truthy)
        (expect (member "services" (alist-get 'capabilities ros2--server-info)) :to-be-truthy))))

  (describe "advertise"
    (it "stores every advertised channel keyed by id"
      (ros2-tests--with-dashboard
        (ros2--handle-text (current-buffer)
          (ros2-tests--fixture "ros2-advertise.json"))
        (expect (hash-table-count ros2--channels) :to-equal 11)
        (expect (alist-get 'topic (gethash 7 ros2--channels)) :to-equal "/odom")))

    (it "lists channels sorted by topic"
      (ros2-tests--with-dashboard
        (ros2--handle-text (current-buffer)
          (ros2-tests--fixture "ros2-advertise.json"))
        (expect (ros2--channel-rows)
          :to-list-topics '("/battery" "/camera/camera_info" "/camera/image_raw"
                            "/cmd_vel" "/gps/fix" "/joint_states" "/odom"
                            "/parameter_events" "/rosout" "/tf" "/tf_static")))))

  (describe "unadvertise"
    (it "drops the named channels"
      (ros2-tests--with-dashboard
        (ros2--handle-text (current-buffer)
          (ros2-tests--fixture "ros2-advertise.json"))
        (ros2--handle-text (current-buffer)
          (ros2-tests--fixture "ros2-unadvertise.json"))
        (expect (hash-table-count ros2--channels) :to-equal 10)
        (expect (mapcar (lambda (c) (alist-get 'topic c)) (ros2--channel-rows))
          :not :to-contain "/odom"))))

  (describe "malformed input"
    (it "ignores a non-JSON frame without signaling"
      (ros2-tests--with-dashboard
        (expect (ros2--handle-text (current-buffer) "not json {[")
          :not :to-throw)))

    (it "ignores an unrecognized op without touching state"
      (ros2-tests--with-dashboard
        (ros2--handle-text (current-buffer) "{\"op\":\"parameterValues\",\"parameters\":[]}")
        (expect (hash-table-count ros2--channels) :to-equal 0)
        (expect ros2--server-info :not :to-be-truthy)))))

(describe "ros2--display-host"
  (it "strips the ws:// scheme"
    (let ((ros2-url "ws://localhost:8765"))
      (expect (ros2--display-host) :to-equal "localhost:8765")))

  (it "strips a wss:// scheme too"
    (let ((ros2-url "wss://example.com:9090"))
      (expect (ros2--display-host) :to-equal "example.com:9090")))

  (it "passes a scheme-less host through unchanged"
    (let ((ros2-url "localhost:8765"))
      (expect (ros2--display-host) :to-equal "localhost:8765"))))

(describe "ros2--set-mode-line"
  :var (icon-names)
  (before-each
    (setq icon-names nil)
    (spy-on 'nerd-icons-mdicon
      :and-call-fake (lambda (name &rest _) (push name icon-names) "")))

  (it "shows the connected glyph and the scheme-stripped host when connected"
    (ros2-tests--with-dashboard
      (let ((ros2-url "ws://localhost:8765"))
        (setq ros2--connected t)
        (ros2--set-mode-line)
        (let ((joined (apply #'concat (seq-filter #'stringp (flatten-list mode-line-process)))))
          (expect joined :to-match "localhost:8765")
          (expect icon-names :to-contain "nf-md-lan_connect")))))

  (it "shows the disconnected glyph when not connected"
    (ros2-tests--with-dashboard
      (setq ros2--connected nil)
      (ros2--set-mode-line)
      (expect icon-names :to-contain "nf-md-lan_disconnect")))

  (it "leaves `mode-name' untouched so ibuffer's Mode column stays `ros2-mode'"
    (ros2-tests--with-dashboard
      (setq ros2--connected t)
      (ros2--set-mode-line)
      (expect mode-name :to-equal "ros2-mode"))))

(describe "ros2--topic-table"
  (it "builds a vui-table listing each channel's topic, type, encoding"
    (ros2-tests--with-dashboard
      (ros2--handle-text (current-buffer)
        (ros2-tests--fixture "ros2-advertise.json"))
      (let ((table (ros2--topic-table)))
        (expect (vui-vnode-table-p table) :to-be-truthy)
        (expect (string-join (apply #'append (vui-vnode-table-rows table)) " ")
          :to-render-substrings '("/odom" "nav_msgs/msg/Odometry" "cdr"))))))

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

(describe "ros2--topic-table filtering"
  (it "lists only the topics matching ros2--topic-filter"
    (ros2-tests--with-dashboard
      (ros2--handle-text (current-buffer)
        (ros2-tests--fixture "ros2-advertise.json"))
      (setq ros2--topic-filter "gps")
      (let ((table (ros2--topic-table)))
        (expect (vui-vnode-table-p table) :to-be-truthy)
        (expect (length (vui-vnode-table-rows table)) :to-equal 1)
        (expect (string-join (apply #'append (vui-vnode-table-rows table)) " ")
          :to-render-substrings '("/gps/fix")))))

  (it "falls back to a filter-aware placeholder when nothing matches"
    (ros2-tests--with-dashboard
      (ros2--handle-text (current-buffer)
        (ros2-tests--fixture "ros2-advertise.json"))
      (setq ros2--topic-filter "nomatch")
      (expect (vui-vnode-table-p (ros2--topic-table)) :not :to-be-truthy))))

(describe "ros2--topics-header"
  (it "is a plain heading with no filter set"
    (ros2-tests--with-dashboard
      (expect (ros2--topics-header) :to-render-substrings '("TOPICS"))
      (expect (ros2--topics-header) :not :to-render-substrings '("⟨"))))

  (it "shows the active filter"
    (ros2-tests--with-dashboard
      (setq ros2--topic-filter "gps")
      (expect (ros2--topics-header) :to-render-substrings '("TOPICS" "gps")))))

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

(describe "node lifecycle helpers"
  (it "names each node's prodigy log buffer"
    (expect (ros2--node-log-buffer-name "bridge") :to-match "\\`\\*prodigy-")
    (expect (ros2--node-log-buffer-name "bridge") :to-match "bridge"))

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
    (expect (lookup-key ros2-mode-map "/") :to-equal #'ros2-filter-topics))

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
    (expect (command-modes 'ros2-filter-topics) :to-equal '(ros2-mode)))

  (it "hides `ros2-mode' from M-x entirely"
    (expect (get 'ros2-mode 'completion-predicate) :to-equal #'ignore)))

;;; ros2-tests.el ends here
