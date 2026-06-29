;;; tailscale.el --- Tailscale for GNU Emacs  -*- lexical-binding: t -*-

;; Copyright © 2026 Mumtahin Farabi <mfarabi619@gmail.com>

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/tailscale
;; Keywords: tools, comm
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1") (nerd-icons "0.1") (vui "0.1"))

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
;; View tailnet via local `tailscale' CLI.
;;
;;; Code:

(require 'cl-lib)
(require 'iso8601)
(require 'json)
(require 'map)
(require 'nerd-icons)
(require 'vui-components)

(defgroup tailscale ()
  "Tailscale CLI integration."
  :prefix "tailscale-"
  :group 'tools)

(defcustom tailscale-executable "tailscale"
  "Path to the tailscale executable."
  :type 'string
  :group 'tailscale)

(defconst tailscale-buffer-name "*tailscale*"
  "Name of the dashboard buffer.
Named so users can target it from `display-buffer-alist'.")

;;; Error taxonomy
;; Subclasses of `tailscale-error' so callers can `condition-case' on
;; specific failure modes without parsing message strings.

(define-error 'tailscale-error       "Tailscale error")
(define-error 'tailscale-exec-error  "Tailscale CLI execution failed" 'tailscale-error)
(define-error 'tailscale-parse-error "Tailscale output parse failed"  'tailscale-error)

;;; CLI

(defun tailscale--run-json (&rest args)
  "Run `tailscale' with ARGS and parse stdout JSON into a hash table.
Signals `tailscale-exec-error' on non-zero exit, `tailscale-parse-error' on
malformed JSON."
  (with-temp-buffer
    (let ((exit-code (apply #'call-process
                       tailscale-executable nil t nil args)))
      (unless (zerop exit-code)
        (signal 'tailscale-exec-error
          (list :args args :exit-code exit-code
            :output (buffer-string))))
      (condition-case parse-failure
        (json-parse-string (buffer-string)
          :object-type 'hash-table
          :array-type  'list
          :false-object nil
          :null-object  nil)
        (json-parse-error
          (signal 'tailscale-parse-error
            (list :args args :output (buffer-string)
              :cause parse-failure)))))))

;;; Top-level accessors

(defun tailscale-status ()
  "Return parsed `tailscale status --json' as a hash table."
  (tailscale--run-json "status" "--json"))

(defun tailscale-self (&optional status)
  "Return the Self peer hash from STATUS (default: live status)."
  (gethash "Self" (or status (tailscale-status))))

(defun tailscale-peers (&optional status)
  "Return the list of peer hashes from STATUS (default: live status)."
  (when-let* ((peer-map (gethash "Peer" (or status (tailscale-status)))))
    (let (peers)
      (maphash (lambda (_public-key peer) (push peer peers)) peer-map)
      peers)))

(defun tailscale-tailnet-name (&optional status)
  "Return the current tailnet name from STATUS (default: live status)."
  (map-nested-elt (or status (tailscale-status))
    '("CurrentTailnet" "Name")))

(defun tailscale-magic-dns-suffix (&optional status)
  "Return the MagicDNS suffix from STATUS (default: live status)."
  (gethash "MagicDNSSuffix" (or status (tailscale-status))))

(defun tailscale-backend-state (&optional status)
  "Return the daemon backend state from STATUS (default: live status)."
  (gethash "BackendState" (or status (tailscale-status))))

(defun tailscale-version (&optional status)
  "Return the tailscale client version from STATUS, git-rev suffix stripped."
  (when-let* ((version-string (gethash "Version"
                                (or status (tailscale-status)))))
    (car (split-string version-string "-"))))

;;; Netcheck

(defun tailscale-netcheck ()
  "Return parsed `tailscale netcheck --format json' as a hash table."
  (tailscale--run-json "netcheck" "--format" "json"))

(defun tailscale-netcheck-udp              (r) "UDP reachability from report R."          (gethash "UDP"            r))
(defun tailscale-netcheck-ipv4             (r) "IPv4 reachability from report R."         (gethash "IPv4"           r))
(defun tailscale-netcheck-ipv6             (r) "IPv6 reachability from report R."         (gethash "IPv6"           r))
(defun tailscale-netcheck-preferred-derp   (r) "Preferred DERP region ID from report R."  (gethash "PreferredDERP"  r))
(defun tailscale-netcheck-region-latency   (r) "RegionLatency hash from report R."        (gethash "RegionLatency"  r))
(defun tailscale-netcheck-global-ipv4      (r) "Global IPv4 addr:port from report R."     (gethash "GlobalV4"       r))
(defun tailscale-netcheck-global-ipv6      (r) "Global IPv6 addr:port from report R."     (gethash "GlobalV6"       r))
(defun tailscale-netcheck-captive-portal   (r) "Non-nil if a captive portal was detected." (gethash "CaptivePortal" r))

;;; ========= DNS status ==========

(defun tailscale-dns-status ()
  "Return parsed `tailscale dns status --json' as a hash table."
  (tailscale--run-json "dns" "status" "--json"))

(defun tailscale-dns-enabled-p        (s) "Non-nil if Tailscale DNS is active in status S."        (gethash "TailscaleDNS"      s))
(defun tailscale-dns-magic-suffix     (s) "MagicDNS suffix from status S."                         (map-nested-elt s '("CurrentTailnet" "MagicDNSSuffix")))
(defun tailscale-dns-magic-enabled-p  (s) "Non-nil if MagicDNS is enabled in status S."            (map-nested-elt s '("CurrentTailnet" "MagicDNSEnabled")))
(defun tailscale-dns-self-name        (s) "This node's MagicDNS FQDN from status S."               (map-nested-elt s '("CurrentTailnet" "SelfDNSName")))
(defun tailscale-dns-search-domains   (s) "Search domain list from status S."                       (gethash "SearchDomains"     s))
(defun tailscale-dns-cert-domains     (s) "Cert domain list from status S."                         (gethash "CertDomains"       s))
(defun tailscale-dns-split-routes     (s) "SplitDNSRoutes hash (domain → resolver list) from S."   (gethash "SplitDNSRoutes"    s))
(defun tailscale-dns-system-servers   (s) "OS-level nameserver list from status S."                 (map-nested-elt s '("SystemDNS" "Nameservers")))

;;; Whois

(defun tailscale-whois (ip)
  "Return parsed `tailscale whois --json IP' as a hash table."
  (tailscale--run-json "whois" "--json" ip))

(defun tailscale-whois-node          (r) "Node hash from whois result R."                     (gethash "Node"        r))
(defun tailscale-whois-user-profile  (r) "UserProfile hash from whois result R."              (gethash "UserProfile" r))
(defun tailscale-whois-node-name     (r) "Node FQDN from whois result R."                     (map-nested-elt r '("Node" "Name")))
(defun tailscale-whois-node-hostname (r) "Node short hostname from whois result R."            (map-nested-elt r '("Node" "Hostinfo" "Hostname")))
(defun tailscale-whois-node-addrs    (r) "Node Tailscale address CIDRs from whois result R."  (map-nested-elt r '("Node" "Addresses")))
(defun tailscale-whois-login-name    (r) "UserProfile LoginName from whois result R."          (map-nested-elt r '("UserProfile" "LoginName")))
(defun tailscale-whois-display-name  (r) "UserProfile DisplayName from whois result R."        (map-nested-elt r '("UserProfile" "DisplayName")))

;;; Peer accessors

(defun tailscale-peer-hostname        (peer) "PEER hostname."                              (gethash "HostName"       peer))
(defun tailscale-peer-dns-name        (peer) "PEER FQDN."                                  (gethash "DNSName"        peer))
(defun tailscale-peer-os              (peer) "PEER OS string."                             (gethash "OS"             peer))
(defun tailscale-peer-online-p        (peer) "Is PEER online?"                             (gethash "Online"         peer))
(defun tailscale-peer-relay           (peer) "PEER DERP region code."                      (gethash "Relay"          peer))
(defun tailscale-peer-ips             (peer) "PEER Tailscale IP list."                     (gethash "TailscaleIPs"   peer))
(defun tailscale-peer-last-seen       (peer) "PEER LastSeen ISO time."                     (gethash "LastSeen"       peer))
(defun tailscale-peer-created         (peer) "PEER Created ISO time."                      (gethash "Created"        peer))
(defun tailscale-peer-key-expiry      (peer) "PEER KeyExpiry ISO time."                    (gethash "KeyExpiry"      peer))
(defun tailscale-peer-exit-node-p     (peer) "Is PEER our exit node?"                      (gethash "ExitNode"       peer))
(defun tailscale-peer-exit-offered-p  (peer) "Does PEER advertise exit?"                   (gethash "ExitNodeOption" peer))
(defun tailscale-peer-tags            (peer) "PEER tag list (`tag:X')."                    (gethash "Tags"           peer))
(defun tailscale-peer-ssh-host-keys   (peer) "PEER's advertised Tailscale-SSH host keys."  (gethash "sshHostKeys"    peer))
(defun tailscale-peer-ssh-enabled-p   (peer) "Non-nil if PEER has Tailscale SSH enabled."  (and (tailscale-peer-ssh-host-keys peer) t))

;;; Mode

(define-derived-mode tailscale-mode special-mode "tailscale"
  "Major mode for the `*tailscale*' buffer."
  (setq-local truncate-lines t))
(put 'tailscale-mode 'completion-predicate #'ignore)

(with-eval-after-load 'nerd-icons
  (add-to-list 'nerd-icons-mode-icon-alist
    '(tailscale-mode nerd-icons-mdicon "nf-md-vpn"
       :face nerd-icons-green)))

;;; Faces

(defface tailscale-ip-online
  '((t :inherit outline-1))
  "Face for online peers' Tailscale IP addresses."
  :group 'tailscale)

(defface tailscale-tag
  '((t :inherit vui-muted :box (:line-width -1 :color nil :style nil)))
  "Pill chip face for peer tags."
  :group 'tailscale)

(defface tailscale-ssh
  '((t :foreground "white" :background "#3D9C58"
      :box (:line-width -1 :color "#3D9C58" :style nil)))
  "Pill chip face for Tailscale-SSH-enabled peers."
  :group 'tailscale)

(defface tailscale-haos
  '((t :foreground "#41BDF5"))
  "Home Assistant sky-blue accent."
  :group 'tailscale)

(defface tailscale-raspberry
  '((t :foreground "#C51A4A"))
  "Raspberry Pi brand red."
  :group 'tailscale)

;;; Icon maps

(defcustom tailscale-os-icons
  '(("macOS"   nerd-icons-faicon "nf-fa-apple"      nerd-icons-silver)
     ("linux"   nerd-icons-faicon "nf-fa-linux"      nerd-icons-orange)
     ("windows" nerd-icons-faicon "nf-fa-windows"    nerd-icons-blue)
     ("android" nerd-icons-faicon "nf-fa-android"    nerd-icons-green)
     ("freebsd" nerd-icons-faicon "nf-fa-freebsd"    nerd-icons-red)
     ("openbsd" nerd-icons-flicon "nf-linux-openbsd" nerd-icons-yellow))
  "Alist mapping OS string to (ICON-FN ICON-NAME ONLINE-FACE).
Offline peers always render with `vui-muted'."
  :type '(alist :key-type string :value-type sexp)
  :group 'tailscale)

(defcustom tailscale-host-icons
  '(("\\(?:^haos\\|homeassistant\\)"
      nerd-icons-mdicon "nf-md-home_assistant" tailscale-haos)
     ("\\(?:^rpi\\|raspberry\\|raspi\\|dietpi\\)"
       nerd-icons-faicon "nf-fa-raspberry_pi"   tailscale-raspberry))
  "Hostname regexp -> (ICON-FN ICON-NAME ONLINE-FACE).
Matched case-insensitively BEFORE `tailscale-os-icons'. First match wins."
  :type '(repeat (list regexp function string face))
  :group 'tailscale)

;;; Cell renderers (return propertized strings)

(defun tailscale--label (text)
  "Wrap TEXT in the muted-label face."
  (propertize text 'face 'vui-muted))

(defun tailscale--host (text online)
  "Color hostname TEXT green when ONLINE, muted otherwise."
  (propertize text 'face (if online 'vui-success 'vui-muted)))

(defun tailscale--ip (text online)
  "Color IP TEXT pink when ONLINE, muted otherwise."
  (propertize text 'face (if online 'tailscale-ip-online 'vui-muted)))

(defun tailscale--peer-icon-spec (peer)
  "Return (ICON-FN ICON-NAME ONLINE-FACE) for PEER.
Checks `tailscale-host-icons' regexps against hostname first, then
falls back to `tailscale-os-icons' on OS string."
  (let ((hostname  (or (tailscale-peer-hostname peer) ""))
         (os-string (or (tailscale-peer-os peer) ""))
         (case-fold-search t))
    (or (cl-some (pcase-lambda (`(,pattern . ,spec))
                   (when (string-match-p pattern hostname) spec))
          tailscale-host-icons)
      (alist-get os-string tailscale-os-icons
        '(nerd-icons-codicon "nf-cod-question" nerd-icons-silver)
        nil #'equal))))

(defun tailscale--icon (peer online)
  "Render PEER's OS/host icon, colored when ONLINE."
  (pcase-let ((`(,icon-function ,icon-name ,color-face)
                (tailscale--peer-icon-spec peer)))
    (funcall icon-function icon-name
      :face (if online color-face 'vui-muted))))

;;; Time formatting

(defun tailscale--iso-never-p (iso-string)
  "Non-nil if ISO-STRING is the never-seen sentinel (all-zero / nil / empty)."
  (or (null iso-string)
    (string-empty-p iso-string)
    (string-prefix-p "0001-01-01" iso-string)))

(defun tailscale--iso-to-epoch (iso-string)
  "Convert ISO-STRING (ISO 8601) to epoch seconds as a float."
  (float-time (encode-time (iso8601-parse iso-string))))

(defun tailscale--now ()
  "Return current epoch seconds (indirection so tests can stub `now')."
  (float-time))

(defun tailscale--humanize-seconds (seconds)
  "Format SECONDS as a short relative-time string (e.g. `12h', `5mo')."
  (let ((seconds (max 0 (round seconds))))
    (cond ((< seconds 60)        (format "%ds"  seconds))
      ((< seconds 3600)      (format "%dm"  (/ seconds 60)))
      ((< seconds 86400)     (format "%dh"  (/ seconds 3600)))
      ((< seconds 604800)    (format "%dd"  (/ seconds 86400)))
      ((< seconds 2592000)   (format "%dw"  (/ seconds 604800)))
      ((< seconds 31536000)  (format "%dmo" (/ seconds 2592000)))
      (t                     (format "%dy"  (/ seconds 31536000))))))

(defun tailscale--ago (iso-string)
  "Format ISO-STRING as `Nunit ago' (nil for the never sentinel)."
  (unless (tailscale--iso-never-p iso-string)
    (format "%s ago"
      (tailscale--humanize-seconds
        (- (tailscale--now) (tailscale--iso-to-epoch iso-string))))))

(defun tailscale--from-now (iso-string)
  "Format ISO-STRING as `in Nunit' (or `Nunit ago' if already past)."
  (unless (tailscale--iso-never-p iso-string)
    (let ((delta (- (tailscale--iso-to-epoch iso-string) (tailscale--now))))
      (if (< delta 0)
        (format "%s ago" (tailscale--humanize-seconds (- delta)))
        (format "in %s"   (tailscale--humanize-seconds delta))))))

;;; Per-cell formatters

(defun tailscale--last-seen (peer)
  "Render PEER's last-seen cell: dot only when online, `○ <time>' otherwise."
  (cond
    ((tailscale-peer-online-p peer)
      (propertize "●" 'face 'vui-success))
    ((tailscale--iso-never-p (tailscale-peer-last-seen peer))
      (concat (propertize "○" 'face 'vui-muted) " "
        (propertize "—" 'face 'vui-muted)))
    (t
      (concat (propertize "○" 'face 'vui-muted) " "
        (propertize (tailscale--ago (tailscale-peer-last-seen peer))
          'face 'vui-muted)))))

(defun tailscale--key-expiry (peer)
  "Render PEER's key-expiry cell, colored by urgency."
  (let ((iso-string (tailscale-peer-key-expiry peer)))
    (if (tailscale--iso-never-p iso-string)
      (propertize "—" 'face 'vui-muted)
      (let* ((delta (- (tailscale--iso-to-epoch iso-string) (tailscale--now)))
              (face  (cond ((< delta 0)            'vui-error)
                       ((< delta (* 86400 30)) 'vui-warning)
                       (t                      'vui-muted))))
        (propertize (tailscale--from-now iso-string) 'face face)))))

(defun tailscale--created (peer)
  "Render PEER's creation date as a muted relative time."
  (let ((iso-string (tailscale-peer-created peer)))
    (if (tailscale--iso-never-p iso-string)
      (propertize "—" 'face 'vui-muted)
      (propertize (tailscale--ago iso-string) 'face 'vui-muted))))

(defun tailscale--exit (peer)
  "Render PEER's exit-node icon.
Green if active, muted if offered, blank otherwise."
  (cond
    ((tailscale-peer-exit-node-p peer)
      (nerd-icons-faicon "nf-fa-sign_out" :face 'vui-success))
    ((tailscale-peer-exit-offered-p peer)
      (nerd-icons-faicon "nf-fa-sign_out" :face 'vui-muted))
    (t " ")))

(defun tailscale--relay (peer)
  "Render PEER's DERP relay code (or `—' if none)."
  (let ((relay (tailscale-peer-relay peer)))
    (propertize (if (or (null relay) (string-empty-p relay)) "—" relay)
      'face 'vui-muted)))

;;; Pill chips

(defun tailscale--pill (text face)
  "Render TEXT as a pill chip with FACE."
  (propertize (format " %s " text) 'face face))

(defun tailscale--tag-pill (tag)
  "Render TAG (with `tag:' prefix stripped) as a tag pill."
  (tailscale--pill (string-remove-prefix "tag:" tag) 'tailscale-tag))

(defun tailscale--ssh-pill ()
  "Render the green `SSH' badge pill."
  (tailscale--pill "SSH" 'tailscale-ssh))

(defun tailscale--tags-line (peer)
  "Return a space-joined string of tag pills for PEER, or nil."
  (when-let* ((tags (tailscale-peer-tags peer)))
    (mapconcat #'tailscale--tag-pill tags " ")))

(defun tailscale--hostname-cell (peer online)
  "Render PEER's hostname, with an SSH pill appended when applicable."
  (let ((host (tailscale--host (or (tailscale-peer-hostname peer) "?") online)))
    (if (tailscale-peer-ssh-enabled-p peer)
      (concat host "  " (tailscale--ssh-pill))
      host)))

;;; Display assembly

(defun tailscale--display-rows (status)
  "Return self + sorted peers; self is always the first row."
  (let ((self           (tailscale-self status))
         (sorted-peers   (tailscale--sort-for-display
                           (tailscale-peers status))))
    (if self (cons self sorted-peers) sorted-peers)))

(defun tailscale--sort-for-display (peers)
  "Return PEERS with online ones first, each group alphabetized by hostname."
  (sort (copy-sequence peers)
    (lambda (peer-a peer-b)
      (let ((a-online (tailscale-peer-online-p peer-a))
             (b-online (tailscale-peer-online-p peer-b)))
        (cond
          ((and a-online (not b-online)) t)
          ((and (not a-online) b-online) nil)
          (t (string< (or (tailscale-peer-hostname peer-a) "")
               (or (tailscale-peer-hostname peer-b) ""))))))))

;;; Table columns
;; Single source of truth for both the header row and per-peer rows.

(defconst tailscale--columns
  `((:header " "              :width nil :cell ,(lambda (peer online) (tailscale--icon          peer online)))
     (:header "HOSTNAME"       :width 24  :cell ,(lambda (peer online) (tailscale--hostname-cell peer online)))
     (:header "TAGS"           :width 10  :cell ,(lambda (peer _)      (or (tailscale--tags-line peer) "")))
     (:header "ADDRESS (IPV4)" :width 16  :cell ,(lambda (peer online) (tailscale--ip (or (car (tailscale-peer-ips peer)) "") online)))
     (:header "LAST SEEN"      :width 9   :cell ,(lambda (peer _)      (tailscale--last-seen     peer)))
     (:header "↑"              :width nil :cell ,(lambda (peer _)      (tailscale--exit          peer)))
     (:header "EXPIRES"        :width 10  :cell ,(lambda (peer _)      (tailscale--key-expiry    peer)))
     (:header "CREATED"        :width 10  :cell ,(lambda (peer _)      (tailscale--created       peer)))
     (:header "RELAY"          :width nil :cell ,(lambda (peer _)      (tailscale--relay         peer))))
  "Column spec for the dashboard table.
Each entry is a plist: :header label, optional :width for `string-pad',
:cell render function (PEER ONLINE) -> propertized string.")

(defun tailscale--pad (text width)
  "Right-pad TEXT to WIDTH, or pass through unchanged when WIDTH is nil."
  (if width (string-pad text width) text))

(defun tailscale--render-row (cells)
  "Insert CELLS as a row: leading indent, two-space gaps, trailing newline."
  (insert "  " (mapconcat #'identity cells "  ") "\n"))

(defun tailscale--render-header ()
  "Insert the column-header row from `tailscale--columns'."
  (tailscale--render-row
    (mapcar (lambda (col)
              (tailscale--label
                (tailscale--pad (plist-get col :header)
                  (plist-get col :width))))
      tailscale--columns)))

(defun tailscale--render-peer (peer)
  "Insert PEER as a data row using `tailscale--columns'."
  (let ((online (tailscale-peer-online-p peer)))
    (tailscale--render-row
      (mapcar (lambda (col)
                (tailscale--pad (funcall (plist-get col :cell) peer online)
                  (plist-get col :width)))
        tailscale--columns))))

;;; Mode-line

(defun tailscale--set-mode-line (status)
  "Update `mode-name' with VPN icon, version, tailnet, and peer count."
  (let* ((self           (tailscale-self status))
          (peers          (tailscale-peers status))
          (all-peers      (if self (cons self peers) peers))
          (online-count   (seq-count #'tailscale-peer-online-p all-peers))
          (total-count    (length all-peers)))
    (setq mode-name
      (list " "
        (nerd-icons-mdicon "nf-md-vpn" :face 'vui-success)
        "  v" (propertize (or (tailscale-version status) "?")
                'face 'vui-muted)
        "  "
        (propertize (or (tailscale-tailnet-name status) "?")
          'face 'vui-heading-1)
        "  "
        (nerd-icons-mdicon "nf-md-server_network" :face 'vui-muted)
        " "
        (propertize (format "%d/%d" online-count total-count)
          'face 'vui-muted)))))

;;; Render + entry point

(defun tailscale--render (status)
  "Render the header row and peer rows for STATUS into the current buffer."
  (tailscale--set-mode-line status)
  (tailscale--render-header)
  (mapc #'tailscale--render-peer (tailscale--display-rows status)))

(defun tailscale--revert (&rest _)
  "Refresh the `*tailscale*' buffer (bound as `revert-buffer-function')."
  (let ((inhibit-read-only t))
    (erase-buffer)
    (tailscale--render (tailscale-status))
    (goto-char (point-min))))

;;;###autoload
(defun tailscale ()
  "Open the `*tailscale*' buffer showing tailnet status."
  (interactive)
  (let ((buffer (get-buffer-create tailscale-buffer-name)))
    (with-current-buffer buffer
      (tailscale-mode)
      (setq-local revert-buffer-function #'tailscale--revert)
      (tailscale--revert))
    (pop-to-buffer buffer)))

(provide 'tailscale)

;;; tailscale.el ends here
