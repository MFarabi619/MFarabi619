;;; tailscale-tests.el --- Buttercup tests for tailscale.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:        emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'tailscale)

;;; Fixtures

(defconst tailscale-tests--sample-json
  "{
     \"Version\": \"1.98.5-t8f8fe6a2e-gc1619fb10\",
     \"BackendState\": \"Running\",
     \"MagicDNSSuffix\": \"tail-example.ts.net\",
     \"CurrentTailnet\": {
       \"Name\": \"acme.github\",
       \"MagicDNSSuffix\": \"tail-example.ts.net\",
       \"MagicDNSEnabled\": true
     },
     \"Self\": {
       \"ID\": \"nKxxxxxxxxxxCNTRL\",
       \"HostName\": \"laptop\",
       \"DNSName\": \"laptop.tail-example.ts.net.\",
       \"OS\": \"macOS\",
       \"TailscaleIPs\": [\"100.64.0.1\", \"fd7a:115c:a1e0::1\"],
       \"Online\": true,
       \"Relay\": \"tor\"
     },
     \"Peer\": {
       \"nodekey:aaa\": {
         \"HostName\": \"homeassistant-1\",
         \"DNSName\": \"homeassistant-1.tail-example.ts.net.\",
         \"OS\": \"linux\",
         \"TailscaleIPs\": [\"100.64.0.2\"],
         \"Online\": true,
         \"Relay\": \"yyz\",
         \"Created\": \"2026-01-15T00:00:00Z\",
         \"LastSeen\": \"2026-06-27T10:00:00Z\",
         \"KeyExpiry\": \"2027-01-15T00:00:00Z\",
         \"ExitNode\": false,
         \"ExitNodeOption\": true,
         \"Tags\": [\"tag:owner\", \"tag:staging\"]
       },
       \"nodekey:bbb\": {
         \"HostName\": \"server-1\",
         \"DNSName\": \"server-1.tail-example.ts.net.\",
         \"OS\": \"linux\",
         \"TailscaleIPs\": [\"100.64.0.3\"],
         \"Online\": false,
         \"Relay\": \"\",
         \"Created\": \"2025-06-01T00:00:00Z\",
         \"LastSeen\": \"2026-06-20T00:00:00Z\",
         \"KeyExpiry\": \"2026-07-10T00:00:00Z\",
         \"ExitNode\": false,
         \"ExitNodeOption\": false,
         \"sshHostKeys\": [\"ssh-ed25519 AAAA...\"]
       },
       \"nodekey:ccc\": {
         \"HostName\": \"workstation\",
         \"DNSName\": \"workstation.tail-example.ts.net.\",
         \"OS\": \"linux\",
         \"TailscaleIPs\": [\"100.64.0.4\"],
         \"Online\": false,
         \"Relay\": \"\",
         \"Created\": \"2025-12-01T00:00:00Z\",
         \"LastSeen\": \"0001-01-01T00:00:00Z\",
         \"KeyExpiry\": \"0001-01-01T00:00:00Z\",
         \"ExitNode\": false,
         \"ExitNodeOption\": false
       }
     }
   }")

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
      (cons nil (format "Substring %S not found in rendered output"
                        needle)))
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
      (cons nil (format "Substring %S not found in rendered output"
                        (car missing))))
     ((apply #'< (mapcar #'cdr positions))
      (cons t  (format "Substrings appear in order: %S" needles)))
     (t
      (cons nil (format "Expected order %S, got positions %S"
                        needles positions))))))

;;; Specs

(describe "nerd-icons registration"
  (it "registers `tailscale-mode' with `nf-md-vpn' in `nerd-icons-mode-icon-alist'"
    (require 'nerd-icons)
    (let ((entry (assq 'tailscale-mode nerd-icons-mode-icon-alist)))
      (expect entry :to-be-truthy)
      (expect (nth 1 entry) :to-equal 'nerd-icons-mdicon)
      (expect (nth 2 entry) :to-equal "nf-md-vpn"))))

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
  ;; Each spec stubs `tailscale--now' to its own value because the
  ;; future-vs-past branch differs per test.

  (it "returns nil for the never sentinel"
    (expect (tailscale--ago     "0001-01-01T00:00:00Z") :not :to-be-truthy)
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
    (dolist (header '("HOSTNAME" "TAGS" "ADDRESS (IPV4)"
                      "LAST SEEN" "EXPIRES" "CREATED" "RELAY"))
      (expect rendered :to-match (regexp-quote header))))

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

(describe "tailscale--set-mode-line"
  (it "sets `mode-name' to a list containing version + tailnet + count"
    (with-temp-buffer
      (tailscale--set-mode-line (tailscale-tests--parse))
      (let ((joined (apply #'concat mode-name)))
        (expect joined :to-match "v1\\.98\\.5")
        (expect joined :to-match "acme\\.github")
        ;; 1 online peer + self (online) = 2 online of 4 total
        (expect joined :to-match "2/4")))))

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

;;; tailscale-tests.el ends here
