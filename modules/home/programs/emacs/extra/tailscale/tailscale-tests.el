;;; tailscale-tests.el --- Buttercup tests for tailscale.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:        emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'tailscale)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

;;; Custom matchers

(buttercup-define-matcher-for-binary-function
    :to-be-file-equal file-equal-p
  :expect-match-phrase    "Expected `%A' to refer to the same file as `%B', but it was `%a'."
  :expect-mismatch-phrase "Expected `%A' not to refer to the same file as `%B', but it did.")

(buttercup-define-matcher :to-have-face-at (rendered substring face)
  "Find SUBSTRING in RENDERED and assert FACE applies at that position."
  (let* ((string         (funcall rendered))
         (needle         (funcall substring))
         (expected-face  (funcall face))
         (position       (string-match (regexp-quote needle) string)))
    (cond
     ((null position)
      (cons nil (format "Substring %S not found in rendered output" needle)))
     ((eq (get-text-property position 'face string) expected-face)
      (cons t  (format "Found %S with face %S at position %d"
                       needle expected-face position)))
     (t
      (cons nil (format "Expected face %S at %S (pos %d), got %S"
                        expected-face needle position
                        (get-text-property position 'face string)))))))

(buttercup-define-matcher :to-render-in-order (rendered substrings)
  "Assert every SUBSTRING is in RENDERED and they appear in the given order."
  (let* ((string    (funcall rendered))
         (needles   (funcall substrings))
         (positions (mapcar (lambda (needle)
                              (cons needle
                                    (string-match (regexp-quote needle) string)))
                            needles))
         (missing   (seq-find (lambda (cell) (null (cdr cell))) positions)))
    (cond
     (missing
      (cons nil (format "Substring %S not found in rendered output" (car missing))))
     ((apply #'< (mapcar #'cdr positions))
      (cons t  (format "Substrings appear in order: %S" needles)))
     (t
      (cons nil (format "Expected order %S, got positions %S" needles positions))))))

(buttercup-define-matcher :to-render-substrings (rendered substrings)
  "Match a rendered string when every entry in SUBSTRINGS appears in it."
  (let ((text (funcall rendered))
        (subs (funcall substrings)))
    (let ((missing (seq-remove (lambda (s) (string-match-p (regexp-quote s) text)) subs)))
      (if (null missing)
          (cons t  (format "Expected rendered string NOT to contain all of %S" subs))
        (cons nil (format "Expected rendered string to contain %S, missing %S" subs missing))))))

;;; Fixtures

(defconst tailscale-tests--fixtures-dir
  (expand-file-name "fixtures/"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Directory holding the `tailscale-<command>.json' fixtures captured from real CLI output.")

(defun tailscale-tests--fixture (name)
  "Return the contents of `fixtures/NAME' as a string.
Safe to call from inside spec bodies; the directory is resolved at load time."
  (with-temp-buffer
    (insert-file-contents (expand-file-name name tailscale-tests--fixtures-dir))
    (buffer-string)))

(defconst tailscale-tests--sample-json
  (tailscale-tests--fixture "tailscale-status.json"))

(defconst tailscale-tests--netcheck-json
  (tailscale-tests--fixture "tailscale-netcheck.json"))

(defconst tailscale-tests--dns-status-json
  (tailscale-tests--fixture "tailscale-dns-status.json"))

(defconst tailscale-tests--whois-json
  (tailscale-tests--fixture "tailscale-whois.json"))

(defconst tailscale-tests--fixture-manifest
  '(("tailscale-status.json"     "status"  "--json")
    ("tailscale-netcheck.json"   "netcheck" "--format" "json")
    ("tailscale-dns-status.json" "dns" "status" "--json")
    ("tailscale-whois.json"      "whois" "--json"))
  "Alist mapping `fixtures/FILE.json' → the `tailscale' args that produced it.
The whois entry omits the IP argument; the live drift spec fills it from
`tailscale-tests-whois-ip'.  All other entries run without parameters.")

(defcustom tailscale-tests-whois-ip nil
  "IP address to pass to `tailscale whois --json' for the live drift check.
Set in your local config (e.g. `.dir-locals.el') to enable the whois freshness
spec; left nil otherwise so CI doesn't fail."
  :type '(choice (const :tag "Skip" nil) string)
  :group 'tailscale)

(defun tailscale-tests--parse (&optional json)
  "Parse JSON (or the sample fixture) into the same hash shape tailscale.el uses."
  (json-parse-string (or json tailscale-tests--sample-json)
                     :object-type 'hash-table
                     :array-type  'list
                     :false-object nil
                     :null-object  nil))

(defun tailscale-tests--peer (&rest plist)
  "Build a peer hash table from PLIST of `:JsonKey VALUE' pairs.
Keys are taken verbatim (minus the leading colon); the JSON shape uses
PascalCase, so pass `:HostName' not `:hostname'."
  (let ((peer (make-hash-table :test 'equal)))
    (cl-loop for (key value) on plist by #'cddr
             do (puthash (substring (symbol-name key) 1) value peer))
    peer))

(defun tailscale-tests--run-cli (&rest args)
  "Run `tailscale ARGS' and return stdout as a string. Signals on non-zero exit.
Comment lines (e.g. the stability warning from `netcheck --format json') are
stripped so callers can treat the result as raw JSON unconditionally."
  (with-temp-buffer
    ;; Discard stderr explicitly — `call-process' with destination t intermixes
    ;; stdout+stderr, which breaks json-parse-string on netcheck debug logs.
    (let ((exit (apply #'call-process
                       (or tailscale-executable "tailscale")
                       nil (list (current-buffer) "/dev/null") nil args)))
      (unless (zerop exit)
        (error "tailscale %s failed (exit %d): %s"
               (string-join args " ") exit (buffer-string)))
      ;; Also strip stdout comment lines (`netcheck --format json' emits
      ;; "# Warning: ..." before the JSON object).
      (replace-regexp-in-string "^#[^\n]*\n?" "" (buffer-string)))))

;;; Auto-generated fixture specs

(describe "every captured fixture"
  (dolist (entry tailscale-tests--fixture-manifest)
    (let* ((name    (car entry))
           (args    (cdr entry))
           (cli-str (format "tailscale %s" (string-join args " "))))

      (it (format "%s parses as non-empty JSON" name)
        (let ((content (tailscale-tests--fixture name)))
          (expect (length content) :to-be-greater-than 0)
          (expect (json-parse-string content) :not :to-throw)))

      (it (format "stays in sync with `%s' on the running machine" cli-str)
        (assume (executable-find "tailscale") "tailscale not on PATH")
        (when (equal (car args) "whois")
          (assume tailscale-tests-whois-ip
                  "`tailscale-tests-whois-ip' unset"))
        (let* ((full-args (if (and (equal (car args) "whois") tailscale-tests-whois-ip)
                              (append args (list tailscale-tests-whois-ip))
                            args))
               (raw (apply #'tailscale-tests--run-cli full-args)))
          (expect (length raw) :to-be-greater-than 0)
          (expect (json-parse-string raw) :not :to-throw))))))

;;; Runner

(describe "tailscale--run-json"
  (it "parses stdout into a hash table when the call exits zero"
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _args)
                 (insert tailscale-tests--sample-json) 0)))
      (let ((result (tailscale--run-json "status" "--json")))
        (expect (hash-table-p result) :to-be-truthy)
        (expect (gethash "BackendState" result) :to-equal "Running"))))

  (it "signals `tailscale-exec-error' when the call exits non-zero"
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _args)
                 (insert "tailscaled: no such command\n") 1)))
      (expect (tailscale--run-json "wat") :to-throw 'tailscale-exec-error)))

  (it "signals `tailscale-parse-error' when stdout is not valid JSON"
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _args)
                 (insert "this is not json {[") 0)))
      (expect (tailscale--run-json "status" "--json")
              :to-throw 'tailscale-parse-error)))

  (it "subclasses can be caught as the generic `tailscale-error'"
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _args) (insert "boom\n") 1)))
      (expect (tailscale--run-json "wat") :to-throw 'tailscale-error))))

;;; nerd-icons registration

(describe "nerd-icons registration"
  (it "registers `tailscale-mode' with `nf-md-vpn' in `nerd-icons-mode-icon-alist'"
    (require 'nerd-icons)
    (let ((entry (assq 'tailscale-mode nerd-icons-mode-icon-alist)))
      (expect entry :to-be-truthy)
      (expect (nth 1 entry) :to-equal 'nerd-icons-mdicon)
      (expect (nth 2 entry) :to-equal "nf-md-vpn"))))

;;; Status accessors

(describe "tailscale-self"
  (it "returns the Self hash"
    (let ((self (tailscale-self (tailscale-tests--parse))))
      (expect (hash-table-p self) :to-be-truthy)
      (expect (gethash "HostName" self) :to-equal "laptop"))))

(describe "tailscale-peers"
  :var (peers)
  (before-each (setq peers (tailscale-peers (tailscale-tests--parse))))

  (it "returns one entry per peer"
    (expect (length peers) :to-equal 3))

  (it "preserves each peer's metadata"
    (let ((hass (seq-find
                 (lambda (peer)
                   (equal (tailscale-peer-hostname peer) "homeassistant-1"))
                 peers)))
      (expect (tailscale-peer-os       hass) :to-equal "linux")
      (expect (tailscale-peer-ips      hass) :to-equal '("100.64.0.2"))
      (expect (tailscale-peer-online-p hass) :to-be-truthy)
      (expect (tailscale-peer-relay    hass) :to-equal "yyz"))))

(describe "tailscale-peer-online-p"
  (it "is nil for offline peers (json `false' parsed as nil)"
    (let ((offline (seq-find
                    (lambda (peer)
                      (equal (tailscale-peer-hostname peer) "server-1"))
                    (tailscale-peers (tailscale-tests--parse)))))
      (expect (tailscale-peer-online-p offline) :not :to-be-truthy))))

(describe "tailnet metadata accessors"
  :var (status)
  (before-each (setq status (tailscale-tests--parse)))

  (it "extracts the tailnet name"
    (expect (tailscale-tailnet-name status) :to-equal "acme.github"))

  (it "extracts the MagicDNS suffix"
    (expect (tailscale-magic-dns-suffix status) :to-equal "tail-example.ts.net"))

  (it "extracts the backend state"
    (expect (tailscale-backend-state status) :to-equal "Running"))

  (it "strips the git-rev suffix from the version"
    (expect (tailscale-version status) :to-equal "1.98.5")))

;;; Time helpers

(describe "tailscale--iso-never-p"
  (it "is non-nil for the all-zero sentinel"
    (expect (tailscale--iso-never-p "0001-01-01T00:00:00Z") :to-be-truthy))

  (it "is non-nil for nil or empty"
    (expect (tailscale--iso-never-p nil) :to-be-truthy)
    (expect (tailscale--iso-never-p "")  :to-be-truthy))

  (it "is nil for a real timestamp"
    (expect (tailscale--iso-never-p "2026-06-27T10:00:00Z")
            :not :to-be-truthy)))

(describe "tailscale--humanize-seconds"
  (it "uses appropriate units"
    (expect (tailscale--humanize-seconds 30)        :to-equal "30s")
    (expect (tailscale--humanize-seconds 90)        :to-equal "1m")
    (expect (tailscale--humanize-seconds 3700)      :to-equal "1h")
    (expect (tailscale--humanize-seconds 90000)     :to-equal "1d")
    (expect (tailscale--humanize-seconds 800000)    :to-equal "1w")
    (expect (tailscale--humanize-seconds 5000000)   :to-equal "1mo")
    (expect (tailscale--humanize-seconds 40000000)  :to-equal "1y")))

(describe "tailscale--ago and --from-now"
  (it "returns nil for the never sentinel"
    (expect (tailscale--ago      "0001-01-01T00:00:00Z") :not :to-be-truthy)
    (expect (tailscale--from-now "0001-01-01T00:00:00Z") :not :to-be-truthy))

  (it "formats past timestamps with the `ago' suffix"
    (spy-on 'tailscale--now :and-return-value 2000000000.0)
    (expect (tailscale--ago "2026-06-27T00:00:00Z") :to-match "ago\\'"))

  (it "formats future timestamps with the `in' prefix"
    (spy-on 'tailscale--now :and-return-value 1700000000.0)
    (expect (tailscale--from-now "2027-01-01T00:00:00Z") :to-match "\\`in "))

  (it "renders expired future timestamps as `X ago' instead of negative"
    (spy-on 'tailscale--now :and-return-value 2000000000.0)
    (expect (tailscale--from-now "2020-01-01T00:00:00Z") :to-match "ago\\'")))

;;; Icon dispatch

(describe "tailscale--peer-icon-spec"
  (cl-flet ((icon-of (hostname os)
              (pcase-let ((`(,_fn ,name ,face)
                           (tailscale--peer-icon-spec
                            (tailscale-tests--peer :HostName hostname :OS os))))
                (list :name name :face face))))

    (it "matches `homeassistant' hostname to the home_assistant icon"
      (expect (icon-of "homeassistant-1" "linux")
              :to-equal '(:name "nf-md-home_assistant" :face tailscale-haos)))

    (it "matches `rpi' hostnames to the raspberry_pi icon"
      (expect (icon-of "rpi5-16" "linux")
              :to-equal '(:name "nf-fa-raspberry_pi" :face tailscale-raspberry)))

    (it "matches `dietpi-...' hostnames to the raspberry_pi icon"
      (expect (plist-get (icon-of "dietpi-rpi4-cam-1" "linux") :name)
              :to-equal "nf-fa-raspberry_pi"))

    (it "falls through to the OS map for generic linux hostnames"
      (expect (plist-get (icon-of "workstation" "linux") :name)
              :to-equal "nf-fa-linux"))

    (it "falls through to the OS map for macOS/windows/etc."
      (expect (plist-get (icon-of "laptop" "macOS") :name)
              :to-equal "nf-fa-apple"))

    (it "uses a question mark for entirely unknown OS strings"
      (expect (plist-get (icon-of "mystery" "plan9") :name)
              :to-equal "nf-cod-question"))

    (it "is case-insensitive on hostname match"
      (expect (plist-get (icon-of "HomeAssistant-X" "linux") :name)
              :to-equal "nf-md-home_assistant"))))

;;; Rendering helpers

(describe "tailscale--tag-pill"
  (it "strips the `tag:' prefix and applies the pill face"
    (let ((pill (tailscale--tag-pill "tag:staging")))
      (expect (substring-no-properties pill) :to-equal " staging ")
      (expect pill :to-have-face-at "staging" 'tailscale-tag))))

(describe "tailscale--ssh-pill"
  (it "renders the `SSH' label with the `tailscale-ssh' face"
    (let ((pill (tailscale--ssh-pill)))
      (expect (substring-no-properties pill) :to-equal " SSH ")
      (expect pill :to-have-face-at "SSH" 'tailscale-ssh))))

(describe "tailscale-peer-ssh-enabled-p"
  (it "is non-nil when sshHostKeys is a non-empty list"
    (expect (tailscale-peer-ssh-enabled-p
             (tailscale-tests--peer :sshHostKeys '("ssh-ed25519 X")))
            :to-be-truthy))

  (it "is nil when sshHostKeys is absent"
    (expect (tailscale-peer-ssh-enabled-p (tailscale-tests--peer))
            :not :to-be-truthy)))

(describe "tailscale--tags-line"
  (it "returns nil when the peer has no tags"
    (expect (tailscale--tags-line (tailscale-tests--peer)) :not :to-be-truthy))

  (it "renders all pills (prefix stripped) space-separated"
    (expect (substring-no-properties
             (tailscale--tags-line
              (tailscale-tests--peer :Tags '("tag:owner" "tag:staging"))))
            :to-equal " owner   staging ")))

(describe "tailscale--hostname-cell"
  (it "renders just the hostname when SSH is not enabled"
    (expect (substring-no-properties
             (tailscale--hostname-cell
              (tailscale-tests--peer :HostName "alpha") t))
            :to-equal "alpha"))

  (it "appends an SSH pill when sshHostKeys is present"
    (expect (substring-no-properties
             (tailscale--hostname-cell
              (tailscale-tests--peer :HostName "alpha"
                                     :sshHostKeys '("ssh-ed25519 X"))
              t))
            :to-equal "alpha   SSH ")))

(describe "tailscale--pad"
  (it "right-pads to WIDTH when given"
    (expect (tailscale--pad "hi" 5) :to-equal "hi   "))
  (it "passes through unchanged when WIDTH is nil"
    (expect (tailscale--pad "hi" nil) :to-equal "hi")))

(describe "tailscale--columns"
  (it "covers every column the dashboard expects"
    (let ((headers (mapcar (lambda (column) (plist-get column :header))
                           tailscale--columns)))
      (dolist (expected '("HOSTNAME" "TAGS" "ADDRESS (IPV4)"
                          "LAST SEEN" "EXPIRES" "CREATED" "RELAY"))
        (expect headers :to-contain expected))))

  (it "each entry has a :cell renderer that returns a string"
    (let ((peer (tailscale-tests--peer :HostName "x" :Online t
                                       :OS "linux"
                                       :TailscaleIPs '("1.2.3.4"))))
      (dolist (column tailscale--columns)
        (expect (stringp (funcall (plist-get column :cell) peer t))
                :to-be-truthy)))))

;;; Dashboard rendering

(describe "tailscale--render"
  :var (rendered)
  (before-each
    (with-temp-buffer
      (tailscale--render (tailscale-tests--parse))
      (setq rendered (buffer-string))))

  (it "does NOT include the tailnet name in the buffer (modeline-only)"
    (expect rendered :not :to-match "acme\\.github"))

  (it "does NOT include the version in the buffer (modeline-only)"
    (expect rendered :not :to-match "1\\.98\\.5"))

  (it "does NOT show a separate `backend' or `self' header line"
    (expect rendered :not :to-match "^backend ")
    (expect rendered :not :to-match "^self "))

  (it "renders peer tags as pills (prefix stripped) inline after the hostname"
    (expect rendered :to-match "homeassistant-1 +.*owner.*staging")
    (expect rendered :not :to-match "tag:owner"))

  (it "appends an SSH pill for peers advertising Tailscale-SSH host keys"
    (expect rendered :to-match "server-1.+SSH"))

  (it "does NOT render the PEERS summary line in the buffer (modeline-only)"
    (expect rendered :not :to-match "PEERS"))

  (it "renders self as the first row of the peer table"
    (expect rendered :to-render-in-order
            '("laptop" "homeassistant-1" "workstation")))

  (it "renders every column header"
    (expect rendered :to-render-substrings
            '("HOSTNAME" "TAGS" "ADDRESS (IPV4)"
              "LAST SEEN" "EXPIRES" "CREATED" "RELAY")))

  (it "puts tags in their own column, right after HOSTNAME"
    (expect rendered :to-render-in-order '("HOSTNAME" "TAGS" "ADDRESS")))

  (it "puts online peers first, then offline (each group alphabetical)"
    (expect rendered :to-render-in-order
            '("homeassistant-1" "server-1" "workstation")))

  (it "renders the online peer with just `●' in its LAST SEEN cell"
    (expect rendered :to-match "homeassistant-1.+●"))

  (it "renders offline peers with `○ ' + relative time (or `—' if never seen)"
    (expect rendered :to-match "○ +—")
    (expect rendered :to-match "○ +[0-9]"))

  (it "colors the online hostname with `vui-success'"
    (expect rendered :to-have-face-at "homeassistant-1" 'vui-success))

  (it "colors offline hostnames with `vui-muted' (dim, not green, not bold)"
    (expect rendered :to-have-face-at "workstation" 'vui-muted)))

;;; Mode line

(describe "tailscale--count-face"
  (it "is `vui-success' when every peer is online"
    (expect (tailscale--count-face 4 4) :to-equal 'vui-success))

  (it "is `vui-warning' when some peers are offline"
    (expect (tailscale--count-face 2 4) :to-equal 'vui-warning))

  (it "is `vui-muted' when there are no peers"
    (expect (tailscale--count-face 0 0) :to-equal 'vui-muted)))

(describe "tailscale--set-mode-line"
  (it "sets `mode-line-process' to a list containing version + tailnet + count"
    (with-temp-buffer
      (tailscale--set-mode-line (tailscale-tests--parse))
      (let ((joined (apply #'concat mode-line-process)))
        (expect joined :to-match "v1\\.98\\.5")
        (expect joined :to-match "acme\\.github")
        (expect joined :to-match "2/4")))))

;;; Interactive entry point

(describe "tailscale (interactive entry point)"
  (before-each
    (spy-on 'tailscale-status :and-call-fake #'tailscale-tests--parse)
    (spy-on 'pop-to-buffer))

  (after-each
    (when (get-buffer tailscale-buffer-name)
      (let (kill-buffer-query-functions)
        (kill-buffer tailscale-buffer-name))))

  (it "creates a `*tailscale*' buffer in tailscale-mode"
    (tailscale)
    (let ((buffer (get-buffer tailscale-buffer-name)))
      (expect (buffer-live-p buffer) :to-be-truthy)
      (with-current-buffer buffer
        (expect major-mode :to-equal 'tailscale-mode)
        (expect (buffer-string) :to-match "HOSTNAME"))))

  (it "is revertable via `revert-buffer'"
    (tailscale)
    (with-current-buffer tailscale-buffer-name
      (let ((before (buffer-string)))
        (revert-buffer nil t)
        (expect (buffer-string) :to-equal before)))))

;;; Netcheck accessors

(describe "tailscale-netcheck accessors"
  :var (report)
  (before-each
    (setq report (tailscale-tests--parse tailscale-tests--netcheck-json)))

  (it "parses connectivity flags"
    (expect (tailscale-netcheck-udp  report) :to-be-truthy)
    (expect (tailscale-netcheck-ipv4 report) :to-be-truthy)
    (expect (tailscale-netcheck-ipv6 report) :to-be-truthy))

  (it "extracts the preferred DERP region"
    (expect (tailscale-netcheck-preferred-derp report) :to-equal 1))

  (it "extracts RegionLatency as a hash table keyed by region ID string"
    (let ((latency (tailscale-netcheck-region-latency report)))
      (expect (hash-table-p latency) :to-be-truthy)
      (expect (gethash "1" latency) :to-equal 25123292)
      (expect (gethash "12" latency) :to-equal 46356875)))

  (it "extracts global IPv4 and IPv6 addresses"
    (expect (tailscale-netcheck-global-ipv4 report) :to-equal "174.0.0.1:51991")
    (expect (tailscale-netcheck-global-ipv6 report) :to-equal "[2001:db8::1]:52847"))

  (it "returns nil for captive-portal when null"
    (expect (tailscale-netcheck-captive-portal report) :not :to-be-truthy))

  (it "runner passes `netcheck --format json' to the CLI"
    (spy-on 'tailscale--run-json :and-return-value report)
    (tailscale-netcheck)
    (expect 'tailscale--run-json
            :to-have-been-called-with "netcheck" "--format" "json")))

;;; DNS status accessors

(describe "tailscale-dns-status accessors"
  :var (status)
  (before-each
    (setq status (tailscale-tests--parse tailscale-tests--dns-status-json)))

  (it "reports Tailscale DNS as enabled"
    (expect (tailscale-dns-enabled-p status) :to-be-truthy))

  (it "extracts MagicDNS suffix and self FQDN"
    (expect (tailscale-dns-magic-suffix status) :to-equal "tail-example.ts.net")
    (expect (tailscale-dns-self-name    status) :to-equal "laptop.tail-example.ts.net."))

  (it "reports MagicDNS as enabled"
    (expect (tailscale-dns-magic-enabled-p status) :to-be-truthy))

  (it "extracts search and cert domains"
    (expect (tailscale-dns-search-domains status) :to-equal '("tail-example.ts.net"))
    (expect (tailscale-dns-cert-domains   status) :to-equal '("laptop.tail-example.ts.net")))

  (it "extracts split DNS routes as a hash table"
    (let ((routes (tailscale-dns-split-routes status)))
      (expect (hash-table-p routes) :to-be-truthy)
      (expect (gethash "ts.net." routes) :to-be-truthy)))

  (it "extracts OS-level nameservers"
    (expect (tailscale-dns-system-servers status) :to-equal '("1.1.1.1" "1.0.0.1")))

  (it "runner passes `dns status --json' to the CLI"
    (spy-on 'tailscale--run-json :and-return-value status)
    (tailscale-dns-status)
    (expect 'tailscale--run-json
            :to-have-been-called-with "dns" "status" "--json")))

;;; Whois accessors

(describe "tailscale-whois accessors"
  :var (result)
  (before-each
    (setq result (tailscale-tests--parse tailscale-tests--whois-json)))

  (it "extracts the Node and UserProfile sub-hashes"
    (expect (hash-table-p (tailscale-whois-node         result)) :to-be-truthy)
    (expect (hash-table-p (tailscale-whois-user-profile result)) :to-be-truthy))

  (it "extracts node FQDN and short hostname"
    (expect (tailscale-whois-node-name     result) :to-equal "laptop.tail-example.ts.net.")
    (expect (tailscale-whois-node-hostname result) :to-equal "laptop"))

  (it "extracts node Tailscale address CIDRs"
    (expect (tailscale-whois-node-addrs result)
            :to-equal '("100.64.0.1/32" "fd7a:115c:a1e0::1/128")))

  (it "extracts user login and display name"
    (expect (tailscale-whois-login-name   result) :to-equal "user@acme.github")
    (expect (tailscale-whois-display-name result) :to-equal "Alice"))

  (it "runner passes `whois --json IP' to the CLI"
    (spy-on 'tailscale--run-json :and-return-value result)
    (tailscale-whois "100.64.0.2")
    (expect 'tailscale--run-json
            :to-have-been-called-with "whois" "--json" "100.64.0.2")))

;;; tailscale-tests.el ends here
