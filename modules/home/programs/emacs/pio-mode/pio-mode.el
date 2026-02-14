;;; pio-mode.el --- PlatformIO & Emacs integration -*- lexical-binding: t; -*-

;; Copyright (C) 2022, 2026 Mumtahin Farabi.
;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; Maintainer: Mumtahin Farabi <mfarabi619@gmail.com>
;; Created: 13 Oct 2025
;;
;; This file is not part of GNU Emacs.
;;
;; Version: 0.0.1
;; Package-Version: 0.0.1
;; Keywords: c, hardware, processes, tools
;; Package-Requires: ((platformio-core "6.1.19"))
;; URL: https://github.com/MFarabi619/MFarabi619/tree/main/modules/home/programs/emacs/pio-mode

;;; Commentary:

;; PlatformIO is a modern alternative to the Arduino CLI, and is widely adopted in the embedded systems development ecosystem.
;; This package provides a guts-out, hackable integration with the modern "pio" CLI; with the goal of being a successor to `platformio-mode'.

;;; Change Log: Initial Release

;;; Code:

(require 'json)
(require 'ansi-color)
(require 'subr-x)
(require 'seq)
(require 'tabulated-list)
(require 'transient nil t)

(defgroup pio nil
  "PlatformIO integration."
  :group 'tools)

(defcustom pio-executable "platformio"
  "Executable name or absolute path for the PlatformIO CLI."
  :type 'string
  :group 'pio)

(defcustom pio-cache-enabled t
  "Enable in-memory caching for stable PlatformIO JSON commands."
  :type 'boolean
  :group 'pio)

(defcustom pio-cache-ttl-account-show 600
  "Seconds to cache `pio account show --json-output'."
  :type 'integer
  :group 'pio)

(defcustom pio-cache-ttl-org-list 600
  "Seconds to cache `pio org list --json-output'."
  :type 'integer
  :group 'pio)

(defcustom pio-cache-ttl-team-list 600
  "Seconds to cache `pio team list --json-output'."
  :type 'integer
  :group 'pio)

(defcustom pio-cache-ttl-boards 1800
  "Seconds to cache `pio boards --json-output'."
  :type 'integer
  :group 'pio)

(defcustom pio-cache-ttl-device-list 30
  "Seconds to cache `pio device list --json-output'."
  :type 'integer
  :group 'pio)

(defcustom pio-cache-ttl-remote-device-list 30
  "Seconds to cache `pio remote device list --json-output'."
  :type 'integer
  :group 'pio)


(defconst pio-system-info-buffer-name "*PIO*")

(defconst pio-device-list-buffer-name "*PIO*")

(defconst pio-remote-device-list-buffer-name "*PIO*")

(defconst pio-run-list-targets-buffer-name "*PIO*")

(defconst pio-test-list-tests-buffer-name "*PIO*")

(defconst pio-check-buffer-name "*PIO*")

(defconst pio-project-config-buffer-name "*PIO*")

(defconst pio-board-info-buffer-name "*PIO Board Info*")


(defconst pio-account-show-buffer-name "*PIO*")

(defconst pio-org-list-buffer-name "*PIO*")

(defconst pio-team-list-buffer-name "*PIO*")

(defvar-local pio-system-info--json-accumulator nil)

(defvar-local pio-device-list--json-accumulator nil)

(defvar-local pio-remote-device-list--json-accumulator nil)

(defvar-local pio-check--json-accumulator nil)

(defvar-local pio-project-config--json-accumulator nil)

(defvar-local pio-boards--all nil)

(defvar-local pio-boards--filtered nil)

(defvar-local pio-boards--query "")

(defvar-local pio-boards--selected-id nil)

(defvar-local pio-boards--board-by-id nil)


(defvar pio--json-command-cache (make-hash-table :test 'equal)
  "In-memory cache for JSON command results.")

(defvar pio--window-configuration nil
  "Last non-PIO window configuration for restoring on quit.")

(defvar pio-boards--window-configuration nil
  "Saved window configuration before opening boards fullscreen UI.")


(defvar pio-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "a") #'pio-account-show)
    (define-key map (kbd "b") #'pio-boards)
    (define-key map (kbd "c") #'pio-check)
    (define-key map (kbd "d") #'pio-device-list)
    (define-key map (kbd "g") #'pio-project-config)
    (define-key map (kbd "k") #'pio-cache-clear)
    (define-key map (kbd "l") #'pio-run-list-targets)
    (define-key map (kbd "m") #'pio-mode)
    (define-key map (kbd "o") #'pio-org-list)
    (define-key map (kbd "r") #'pio-remote-device-list)
    (define-key map (kbd "s") #'pio-system-info)
    (define-key map (kbd "x") #'pio-test-list-tests)
    (define-key map (kbd "t") #'pio-team-list)
    map)
  "Prefix keymap for PlatformIO commands.")

(defun pio-mode-force-refresh ()
  "Open the PlatformIO command dispatcher."
  (interactive)
  (pio-mode))

(defun pio-account-show-force-refresh ()
  "Show account and bypass cache."
  (interactive)
  (pio-account-show t))

(defun pio-org-list-force-refresh ()
  "Show org list and bypass cache."
  (interactive)
  (pio-org-list t))

(defun pio-team-list-force-refresh ()
  "Show team list and bypass cache."
  (interactive)
  (pio-team-list t))

(defun pio-boards-force-refresh ()
  "Show boards and bypass cache."
  (interactive)
  (pio-boards t))

(when (featurep 'transient)
  (transient-define-prefix pio-transient ()
    "PlatformIO command palette."
    ["General"
     ("m" "Command menu" pio-mode)
     ("k" "Clear cache" pio-cache-clear)]
    ["Project"
     ("s" "System info" pio-system-info)
     ("g" "Project config" pio-project-config)
     ("d" "Device list" pio-device-list)
     ("r" "Remote devices" pio-remote-device-list)
     ("b" "Boards" pio-boards)
     ("B" "Boards (force)" pio-boards-force-refresh)]
    ["Build & Test"
     ("l" "Run list targets" pio-run-list-targets)
     ("x" "Test list" pio-test-list-tests)
     ("c" "Check" pio-check)]
    ["Cloud"
     ("a" "Account" pio-account-show)
     ("A" "Account (force)" pio-account-show-force-refresh)
     ("o" "Organizations" pio-org-list)
     ("O" "Organizations (force)" pio-org-list-force-refresh)
     ("t" "Teams" pio-team-list)
     ("T" "Teams (force)" pio-team-list-force-refresh)]))

(defun pio-dispatch ()
  "Open the PlatformIO command dispatcher.
Uses transient when available, otherwise falls back to `pio-command-map'."
  (interactive)
  (if (fboundp 'pio-transient)
      (pio-transient)
    (message "Transient is unavailable; use `C-c C-p` prefix commands.")))

(defun pio--bind-common-keys (mode-map)
  "Bind common PlatformIO command keys into MODE-MAP."
  (define-key mode-map (kbd "C-c p") #'pio-dispatch)
  (define-key mode-map (kbd "C-c C-p") pio-command-map)
  (define-key mode-map (kbd "C-c a") #'pio-account-show)
  (define-key mode-map (kbd "C-c b") #'pio-boards)
  (define-key mode-map (kbd "C-c c") #'pio-check)
  (define-key mode-map (kbd "C-c d") #'pio-device-list)
  (define-key mode-map (kbd "C-c g") #'pio-project-config)
  (define-key mode-map (kbd "C-c k") #'pio-cache-clear)
  (define-key mode-map (kbd "C-c l") #'pio-run-list-targets)
  (define-key mode-map (kbd "C-c m") #'pio-mode)
  (define-key mode-map (kbd "C-c o") #'pio-org-list)
  (define-key mode-map (kbd "C-c r") #'pio-remote-device-list)
  (define-key mode-map (kbd "C-c s") #'pio-system-info)
  (define-key mode-map (kbd "C-c x") #'pio-test-list-tests)
  (define-key mode-map (kbd "C-c t") #'pio-team-list)
  (define-key mode-map (kbd "q") #'pio-quit-window))

(defun pio-quit-window ()
  "Close the current PIO window cleanly."
  (interactive)
  (if pio-boards--window-configuration
      (progn
        (set-window-configuration pio-boards--window-configuration)
        (setq pio-boards--window-configuration nil))
    (if pio--window-configuration
        (progn
          (set-window-configuration pio--window-configuration)
          (setq pio--window-configuration nil))
      (if (one-window-p)
          (quit-window)
        (delete-window)))))

(defun pio-boards--restore-window-configuration ()
  "Restore the saved pre-boards window configuration."
  (when pio-boards--window-configuration
    (set-window-configuration pio-boards--window-configuration)
    (setq pio-boards--window-configuration nil)))

(defun pio-boards--setup-fullscreen-layout (results-buffer detail-buffer)
  "Show RESULTS-BUFFER and DETAIL-BUFFER in a fullscreen two-pane layout."
  (setq pio-boards--window-configuration (current-window-configuration))
  (setq pio--window-configuration nil)
  (delete-other-windows)
  (let ((results-window (selected-window))
        (detail-window nil))
    (set-window-buffer results-window results-buffer)
    (setq detail-window (split-window results-window nil 'right))
    (set-window-buffer detail-window detail-buffer)
    (select-window results-window)))

(defun pio-boards--display-layout ()
  "Display boards/results in fullscreen split layout."
  (let ((results-buffer (get-buffer-create pio-system-info-buffer-name))
        (detail-buffer (pio-boards--detail-buffer)))
    (pio-boards--setup-fullscreen-layout results-buffer detail-buffer)))

(defun pio-boards-quit-layout ()
  "Quit boards UI and restore the previous window layout."
  (interactive)
  (if pio-boards--window-configuration
      (progn
        (pio-boards--restore-window-configuration)
        (setq pio--window-configuration nil))
    (if (one-window-p)
        (quit-window)
      (delete-window))))

(defun pio--find-visible-window ()
  "Return a visible window currently showing a PIO buffer, or nil."
  (catch 'pio-window
    (dolist (win (window-list nil nil))
      (let ((name (buffer-name (window-buffer win))))
        (when (and (stringp name)
                   (string-prefix-p "*PIO" name))
          (throw 'pio-window win))))
    nil))

(defun pio--display-buffer-passive (buffer)
  "Show BUFFER in a PIO window without changing focus.
If no PIO window is visible, create a regular window on the right." 
  (let ((target-window (or (get-buffer-window buffer t)
                           (pio--find-visible-window))))
    (if (window-live-p target-window)
        (set-window-buffer target-window buffer)
      (let ((origin (selected-window)))
        (unless pio--window-configuration
          (setq pio--window-configuration (current-window-configuration)))
        (setq target-window (split-window origin nil 'right))
        (set-window-buffer target-window buffer)
        (select-window origin)))))

(defun pio--append-ansi-process-output (process output-chunk)
  "Append OUTPUT-CHUNK from PROCESS, applying ANSI color sequences."
  (when-let ((process-buffer (process-buffer process)))
    (with-current-buffer process-buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (ansi-color-apply output-chunk))))))

(defun pio-greet ()
  "Return the greeting string for pio-mode."
  "Hellooo from pio-mode!")

(defun pio-hello ()
  (interactive)
  (message "%s" (pio-greet)))

(defun pio-system-info--resolve-executable ()
  "Return the absolute path to the PlatformIO CLI, or signal a user error."
  (or (executable-find pio-executable)
      (user-error "PlatformIO CLI not found: %s" pio-executable)))

(defun pio--run-json-command-sync (&rest args)
  "Run `platformio' with ARGS and parse JSON output."
  (let ((raw-output (apply #'pio--run-command-sync args)))
    (condition-case err
        (json-parse-string raw-output :object-type 'alist :array-type 'list)
      (error
       (user-error "Failed to parse JSON from platformio %s: %s"
                   (string-join args " ")
                   (error-message-string err))))))

(defun pio--run-command-sync (&rest args)
  "Run `platformio' with ARGS and return trimmed stdout string."
  (let ((platformio-cli (pio-system-info--resolve-executable)))
    (with-temp-buffer
      (let ((exit-code (apply #'process-file platformio-cli nil (current-buffer) nil args))
            (command-label (format "%s %s" platformio-cli (string-join args " "))))
        (let ((raw-output (string-trim (buffer-string))))
          (unless (and (integerp exit-code) (zerop exit-code))
            (user-error "PlatformIO command failed: %s\n%s" command-label raw-output))
          (when (string-empty-p raw-output)
            (user-error "PlatformIO command returned empty output: %s" command-label))
          raw-output)))))

(defun pio-cache-clear ()
  "Clear the in-memory PlatformIO JSON cache."
  (interactive)
  (clrhash pio--json-command-cache)
  (message "PIO cache cleared"))

(defun pio--cache-root-key ()
  "Return a cache root key based on current project context."
  (expand-file-name
   (or (locate-dominating-file default-directory "platformio.ini")
       default-directory)))

(defun pio--cache-entry-fresh-p (entry ttl)
  "Return non-nil when ENTRY is fresh for TTL seconds."
  (and (consp entry)
       (numberp (car entry))
       (< (- (float-time) (car entry)) ttl)))

(defun pio--run-json-command-cached (cache-id ttl force-refresh &rest args)
  "Run JSON command ARGS with CACHE-ID and TTL.
When FORCE-REFRESH is non-nil, bypass cache." 
  (let* ((cache-key (list cache-id (pio--cache-root-key) args))
         (entry (gethash cache-key pio--json-command-cache))
         (use-cache (and pio-cache-enabled
                         (not force-refresh)
                         (pio--cache-entry-fresh-p entry ttl))))
    (if use-cache
        (cdr entry)
      (let ((value (apply #'pio--run-json-command-sync args)))
        (when pio-cache-enabled
          (puthash cache-key (cons (float-time) value) pio--json-command-cache))
        value))))

(defun pio-boards--field (board key)
  "Return KEY from BOARD as a normalized display string."
  (pio-device-list--normalize-field
   (pio-device-list--alist-get-any key board)))

(defun pio-boards--lookup (board key)
  "Return raw KEY value from BOARD alist, preserving list values."
  (cdr (assoc key board)))

(defun pio-boards--format-size-kib (value)
  "Return VALUE in bytes as a human-friendly KiB string."
  (if (numberp value)
      (format "%d KiB" (/ value 1024))
    "n/a"))

(defun pio-boards--format-cpu-hz (value)
  "Return CPU frequency VALUE in Hz as MHz text."
  (if (numberp value)
      (format "%.1f MHz" (/ value 1000000.0))
    "n/a"))

(defun pio-boards--insert-detail-line (label value)
  "Insert one detail row with LABEL and VALUE."
  (insert (propertize (format "%-11s" (concat label ":")) 'face 'font-lock-variable-name-face)
          " "
          (propertize (format "%s" value) 'face 'font-lock-string-face)
          "\n"))

(defun pio-boards--debug-tools-summary (board)
  "Return formatted debug tools string from BOARD."
  (let* ((debug (pio-boards--lookup board 'debug))
         (tools-cell (and (listp debug) (assoc 'tools debug)))
         (tools (cdr tools-cell))
         (names (mapcar (lambda (tool)
                          (if (symbolp tool)
                              (symbol-name tool)
                            (symbol-name (car tool))))
                        tools))
         (default-tool
          (catch 'found
            (dolist (tool tools nil)
              (when (and (listp tool)
                         (assoc 'default tool)
                         (cdr (assoc 'default tool)))
                (throw 'found (symbol-name (car tool))))))))
    (if names
        (if default-tool
            (format "%s (default: %s)" (string-join names ", ") default-tool)
          (string-join names ", "))
      "n/a")))

(defun pio-boards--board-id (board index)
  "Return a stable row id from BOARD and INDEX."
  (let ((raw-id (pio-device-list--alist-get-any 'id board)))
    (if (and raw-id (not (string-empty-p (format "%s" raw-id))))
        (format "%s" raw-id)
      (format "board-%d" index))))

(defun pio-boards--matches-query-p (board query)
  "Return non-nil if BOARD matches QUERY."
  (if (string-empty-p query)
      t
    (let ((q (downcase query)))
      (or (string-match-p (regexp-quote q) (downcase (pio-boards--field board 'name)))
          (string-match-p (regexp-quote q) (downcase (pio-boards--field board 'vendor)))
          (string-match-p (regexp-quote q) (downcase (pio-boards--field board 'platform)))
          (string-match-p (regexp-quote q) (downcase (pio-boards--field board 'id)))))))

(defun pio-boards--tabulated-entry (board index)
  "Convert BOARD at INDEX into one tabulated entry."
  (let ((id (pio-boards--board-id board index))
        (name (pio-boards--field board 'name))
        (vendor (pio-boards--field board 'vendor))
        (platform (pio-boards--field board 'platform)))
    (puthash id board pio-boards--board-by-id)
    (list id (vector name vendor platform))))

(defun pio-boards--render-list ()
  "Render the boards list from local state."
  (setq pio-boards--board-by-id (make-hash-table :test 'equal))
  (let ((index 0))
    (setq tabulated-list-entries
          (mapcar (lambda (board)
                    (setq index (1+ index))
                    (pio-boards--tabulated-entry board index))
                  pio-boards--filtered)))
  (setq header-line-format
        (format " Boards  |  %d/%d  |  Filter: %s"
                (length pio-boards--filtered)
                (length pio-boards--all)
                (if (string-empty-p pio-boards--query) "<none>" pio-boards--query)))
  (tabulated-list-print t)
  (goto-char (point-min))
  (forward-line 1)
  (pio-boards--update-detail-at-point))

(defun pio-boards--apply-filter (query)
  "Apply QUERY to boards list and rerender." 
  (setq pio-boards--query (string-trim (or query ""))
        pio-boards--filtered
        (seq-filter (lambda (board)
                      (pio-boards--matches-query-p board pio-boards--query))
                    pio-boards--all))
  (pio-boards--render-list))

(defun pio-boards--detail-buffer ()
  "Return the board detail buffer." 
  (get-buffer-create pio-board-info-buffer-name))

(defun pio-boards--render-board-detail (board)
  "Render BOARD object into the detail buffer."
  (with-current-buffer (pio-boards--detail-buffer)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (pio-board-info-mode)
      (setq-local truncate-lines t)
      (let ((name (pio-boards--field board 'name))
            (board-id (pio-boards--field board 'id))
            (vendor (pio-boards--field board 'vendor))
            (platform (pio-boards--field board 'platform))
            (mcu (pio-boards--field board 'mcu))
            (frameworks (pio-boards--lookup board 'frameworks))
            (url (pio-boards--field board 'url))
            (ram (pio-boards--lookup board 'ram))
            (rom (pio-boards--lookup board 'rom))
            (f-cpu (pio-boards--lookup board 'f_cpu)))
        (insert (propertize name 'face 'bold) "\n")
        (insert (propertize board-id 'face 'shadow) "\n\n")
        (insert (propertize "Overview\n" 'face 'font-lock-keyword-face))
        (insert "--------\n")
        (pio-boards--insert-detail-line "Vendor" vendor)
        (pio-boards--insert-detail-line "Platform" platform)
        (pio-boards--insert-detail-line "MCU" mcu)
        (pio-boards--insert-detail-line "CPU" (pio-boards--format-cpu-hz f-cpu))
        (pio-boards--insert-detail-line "RAM" (pio-boards--format-size-kib ram))
        (pio-boards--insert-detail-line "Flash" (pio-boards--format-size-kib rom))
        (pio-boards--insert-detail-line "Frameworks"
                                        (if (listp frameworks)
                                            (string-join (mapcar #'format frameworks) ", ")
                                          "n/a"))
        (pio-boards--insert-detail-line "Debug" (pio-boards--debug-tools-summary board))
        (insert "\n")
        (insert (propertize "URL\n" 'face 'font-lock-keyword-face))
        (insert "---\n")
        (insert-text-button url
                            'action (lambda (_)
                                      (browse-url url))
                            'follow-link t
                            'help-echo "Open board page in browser")
        (insert "\n\n")
        (insert (propertize "Raw Data\n" 'face 'font-lock-keyword-face))
        (insert "--------\n")
        (condition-case _err
            (let ((json-encoding-pretty-print t))
              (insert (json-encode board))
              (json-pretty-print-buffer)
              (goto-char (point-max)))
          (error
           (pp board (current-buffer)))))
      (goto-char (point-min)))))

(defun pio-boards--update-detail-at-point ()
  "Update detail pane using the current row in results buffer."
  (when (derived-mode-p 'pio-boards-mode)
    (let ((id (tabulated-list-get-id)))
      (unless (equal id pio-boards--selected-id)
        (setq pio-boards--selected-id id)
        (when id
          (when-let ((board (gethash id pio-boards--board-by-id)))
            (pio-boards--render-board-detail board)))))))

(defun pio-boards-filter (query)
  "Prompt and apply board filter QUERY." 
  (interactive (list (read-from-minibuffer
                      "Boards filter: "
                      pio-boards--query)))
  (pio-boards--apply-filter query))

(defun pio-boards-clear-filter ()
  "Clear board list filter."
  (interactive)
  (pio-boards--apply-filter ""))

(defun pio-boards-refresh (&optional force-refresh)
  "Refresh boards data. With FORCE-REFRESH, bypass cache."
  (interactive "P")
  (let ((boards (pio--run-json-command-cached
                 'boards
                 pio-cache-ttl-boards
                 force-refresh
                 "boards" "--json-output")))
    (setq pio-boards--all boards)
    (pio-boards--apply-filter pio-boards--query)))

(defun pio-boards--post-command-hook ()
  "Keep board detail pane synced with current line."
  (pio-boards--update-detail-at-point))

(define-derived-mode pio-boards-mode tabulated-list-mode "PIO-Boards"
  "Major mode for browsing PlatformIO boards."
  (setq tabulated-list-format
        [("Name" 34 t)
         ("Vendor" 22 t)
         ("Platform" 16 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Name" nil))
  (setq tabulated-list-use-header-line t)
  (tabulated-list-init-header)
  (add-hook 'post-command-hook #'pio-boards--post-command-hook nil t))

(define-derived-mode pio-board-info-mode special-mode "PIO-Board-Info"
  "Major mode for displaying board detail JSON.")

(pio--bind-common-keys pio-boards-mode-map)
(pio--bind-common-keys pio-board-info-mode-map)
(define-key pio-boards-mode-map (kbd "g") #'pio-boards-refresh)
(define-key pio-boards-mode-map (kbd "G") (lambda () (interactive) (pio-boards-refresh t)))
(define-key pio-boards-mode-map (kbd "/") #'pio-boards-filter)
(define-key pio-boards-mode-map (kbd "C-c /") #'pio-boards-clear-filter)
(define-key pio-boards-mode-map (kbd "q") #'pio-boards-quit-layout)
(define-key pio-board-info-mode-map (kbd "q") #'pio-boards-quit-layout)

(defun pio-boards (&optional force-refresh)
  "Open boards explorer with list and board detail panes.
With FORCE-REFRESH, bypass cache for boards data." 
  (interactive "P")
  (let ((results-buffer (get-buffer-create pio-system-info-buffer-name)))
    (with-current-buffer results-buffer
      (pio-boards-mode)
      (setq-local truncate-lines t))
    (pio-boards--display-layout)
    (with-current-buffer results-buffer
      (pio-boards-refresh force-refresh))))

(defun pio--person-display-name (person)
  "Return a readable display name string from PERSON alist."
  (let* ((username (pio-device-list--alist-get-any 'username person))
         (firstname (pio-device-list--alist-get-any 'firstname person))
         (lastname (pio-device-list--alist-get-any 'lastname person))
         (full-name (string-trim (format "%s %s"
                                    (or firstname "")
                                    (or lastname "")))))
    (if (string-empty-p full-name)
        (pio-device-list--normalize-field username)
      full-name)))

(defun pio-system-info--infer-section (field-title)
  "Infer a section label from FIELD-TITLE."
  (cond
   ((string-match-p "Core" field-title) "Core")
   ((string-match-p "Python" field-title) "Python")
   ((string-match-p "System" field-title) "System")
   ((string-match-p "Platform" field-title) "Platform")
   ((string-match-p "Libraries" field-title) "Libraries")
   ((string-match-p "Tool" field-title) "Toolchains")
   (t "Other")))

(defun pio-system-info--format-field-title (raw-title)
  "Return a display title for RAW-TITLE, including a section prefix."
  (let ((section (pio-system-info--infer-section raw-title)))
    (format "%s › %s" section raw-title)))

(defun pio-system-info--propertize-value (value)
  "Return VALUE as a pretty, colored string for display."
  (propertize (format "%s" value) 'face 'font-lock-string-face))

(defun pio-system-info--tabulated-entry-from-json-pair (json-pair)
  "Convert JSON-PAIR into a `tabulated-list-entries' row."
  (let* ((entry-key (car json-pair))
         (entry-object (cdr json-pair))
         (field-title (alist-get 'title entry-object))
         (field-value (alist-get 'value entry-object))
         (display-title (pio-system-info--format-field-title field-title))
         (display-value (pio-system-info--propertize-value field-value)))
    (list (symbol-name entry-key)
          (vector display-title display-value))))

(defun pio-system-info--entries-from-json (json-string)
  "Parse JSON-STRING and return `tabulated-list-entries'."
  (let ((parsed-json (json-parse-string json-string :object-type 'alist :array-type 'list)))
    (mapcar #'pio-system-info--tabulated-entry-from-json-pair parsed-json)))

(defun pio-system-info--render-buffer (system-info-buffer)
  "Initialize and render SYSTEM-INFO-BUFFER for system info output."
  (with-current-buffer system-info-buffer
    (pio-system-info-mode)
    (setq tabulated-list-entries nil)
    (setq-local pio-system-info--json-accumulator nil)
    (tabulated-list-print)))

(defun pio-system-info--append-process-output (process output-chunk)
  "Append OUTPUT-CHUNK from PROCESS into the current buffer accumulator."
  (when-let ((process-buffer (process-buffer process)))
    (with-current-buffer process-buffer
      (setq-local pio-system-info--json-accumulator
                  (concat (or pio-system-info--json-accumulator "") output-chunk)))))

(defun pio-system-info--finalize-process (_process _event)
  "Finalize system info output: parse JSON and refresh the tabulated list."
  (with-current-buffer pio-system-info-buffer-name
    (let* ((json-string (or pio-system-info--json-accumulator "{}"))
           (tabulated-entries (pio-system-info--entries-from-json json-string)))
      (setq tabulated-list-entries tabulated-entries
            pio-system-info--json-accumulator nil)
      (tabulated-list-revert))))

(define-derived-mode pio-system-info-mode tabulated-list-mode "PIO-System"
  "Major mode for displaying `pio system info --json-output' in a table."
  (setq tabulated-list-format
        [("Field" 28 t)
         ("Value" 0 t)])
  (setq tabulated-list-padding 4)
  (setq tabulated-list-sort-key (cons "Field" nil))
  (setq tabulated-list-use-header-line t)
  (tabulated-list-init-header))

(pio--bind-common-keys pio-system-info-mode-map)

(defun pio-system-info ()
  "Display `pio system info --json-output' in a grid."
  (interactive)
  (let* ((platformio-cli (pio-system-info--resolve-executable))
         (system-info-buffer (get-buffer-create pio-system-info-buffer-name)))
    (pio-system-info--render-buffer system-info-buffer)
    (pio--display-buffer-passive system-info-buffer)
    (make-process
     :name "pio-system-info"
     :buffer system-info-buffer
     :command (list platformio-cli "system" "info" "--json-output")
     :filter #'pio-system-info--append-process-output
     :sentinel #'pio-system-info--finalize-process)))

(defun pio-device-list--alist-get-any (key alist)
  "Get KEY from ALIST, supporting symbol and string forms."
  (or (alist-get key alist)
      (alist-get (symbol-name key) alist nil nil #'equal)))

(defun pio-device-list--normalize-field (value)
  "Return VALUE as a display-safe device field string."
  (let ((as-string (string-trim (format "%s" (or value "")))))
    (if (string-empty-p as-string) "n/a" as-string)))

(defun pio-device-list--tabulated-entry-from-device (device index)
  "Convert DEVICE at INDEX into a `tabulated-list-entries' row."
  (let* ((port (pio-device-list--normalize-field
                (pio-device-list--alist-get-any 'port device)))
         (description (pio-device-list--normalize-field
                       (pio-device-list--alist-get-any 'description device)))
         (hwid (pio-device-list--normalize-field
                (pio-device-list--alist-get-any 'hwid device)))
         (entry-id (format "%s#%d" port index)))
    (list entry-id
          (vector port description hwid))))

(defun pio-device-list--entries-from-json (json-string)
  "Parse JSON-STRING and return `tabulated-list-entries'."
  (let ((parsed-json (json-parse-string json-string :object-type 'alist :array-type 'list))
        (index 0))
    (mapcar (lambda (device)
              (setq index (1+ index))
              (pio-device-list--tabulated-entry-from-device device index))
            parsed-json)))

(defun pio-device-list--entries-from-json-data (parsed-json)
  "Convert PARSED-JSON from `pio device list' into `tabulated-list-entries'."
  (let ((index 0))
    (mapcar (lambda (device)
              (setq index (1+ index))
              (pio-device-list--tabulated-entry-from-device device index))
            parsed-json)))

(defun pio-device-list--render-buffer (device-list-buffer)
  "Initialize and render DEVICE-LIST-BUFFER for device list output."
  (with-current-buffer device-list-buffer
    (pio-device-list-mode)
    (setq tabulated-list-entries nil)
    (setq-local pio-device-list--json-accumulator nil)
    (tabulated-list-print)))

(defun pio-device-list--append-process-output (process output-chunk)
  "Append OUTPUT-CHUNK from PROCESS into the current buffer accumulator."
  (when-let ((process-buffer (process-buffer process)))
    (with-current-buffer process-buffer
      (setq-local pio-device-list--json-accumulator
                  (concat (or pio-device-list--json-accumulator "") output-chunk)))))

(defun pio-device-list--finalize-process (_process _event)
  "Finalize device list output: parse JSON and refresh tabulated list."
  (when-let ((device-list-buffer (get-buffer pio-device-list-buffer-name)))
    (with-current-buffer device-list-buffer
      (let* ((json-string (or pio-device-list--json-accumulator "[]"))
             (tabulated-entries (pio-device-list--entries-from-json json-string)))
        (setq tabulated-list-entries tabulated-entries
              pio-device-list--json-accumulator nil)
        (tabulated-list-revert)))))

(define-derived-mode pio-device-list-mode tabulated-list-mode "PIO-Devices"
  "Major mode for displaying `pio device list --json-output' in a table."
  (setq tabulated-list-format
        [("Port" 22 t)
         ("Description" 34 t)
         ("HWID" 0 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Port" nil))
  (setq tabulated-list-use-header-line t)
  (tabulated-list-init-header))

(pio--bind-common-keys pio-device-list-mode-map)

(defun pio-device-list (&optional force-refresh)
  "Display `pio device list --json-output' in a table."
  (interactive "P")
  (let* ((parsed-json (pio--run-json-command-cached
                       'device-list
                       pio-cache-ttl-device-list
                       force-refresh
                       "device" "list" "--json-output"))
         (device-list-buffer (get-buffer-create pio-device-list-buffer-name)))
    (with-current-buffer device-list-buffer
      (pio-device-list-mode)
      (setq tabulated-list-entries (pio-device-list--entries-from-json-data parsed-json))
      (tabulated-list-print))
    (pio--display-buffer-passive device-list-buffer)))

(defun pio-org-list--owners-string (owners)
  "Return a readable owners string from OWNERS list."
  (if owners
      (string-join (mapcar #'pio--person-display-name owners) ", ")
    "n/a"))

(defun pio-org-list--tabulated-entry-from-org (org index)
  "Convert ORG at INDEX into a `tabulated-list-entries' row."
  (let* ((orgname (pio-device-list--normalize-field
                   (pio-device-list--alist-get-any 'orgname org)))
         (displayname (pio-device-list--normalize-field
                       (pio-device-list--alist-get-any 'displayname org)))
         (email (pio-device-list--normalize-field
                 (pio-device-list--alist-get-any 'email org)))
         (owners (pio-org-list--owners-string
                  (pio-device-list--alist-get-any 'owners org))))
    (list (format "%s#%d" orgname index)
          (vector orgname displayname email owners))))

(defun pio-org-list--entries-from-json-data (parsed-json)
  "Convert PARSED-JSON from `pio org list' into `tabulated-list-entries'."
  (let ((index 0))
    (mapcar (lambda (org)
              (setq index (1+ index))
              (pio-org-list--tabulated-entry-from-org org index))
            parsed-json)))

(define-derived-mode pio-org-list-mode tabulated-list-mode "PIO-Orgs"
  "Major mode for displaying `pio org list --json-output' in a table."
  (setq tabulated-list-format
        [("Org" 24 t)
         ("Display Name" 24 t)
         ("Email" 30 t)
         ("Owners" 0 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Org" nil))
  (setq tabulated-list-use-header-line t)
  (tabulated-list-init-header))

(pio--bind-common-keys pio-org-list-mode-map)

(defun pio-org-list (&optional force-refresh)
  "Display `pio org list --json-output' in a table."
  (interactive "P")
  (let* ((parsed-json (pio--run-json-command-cached
                       'org-list
                       pio-cache-ttl-org-list
                       force-refresh
                       "org" "list" "--json-output"))
         (org-list-buffer (get-buffer-create pio-org-list-buffer-name)))
    (with-current-buffer org-list-buffer
      (pio-org-list-mode)
      (setq tabulated-list-entries (pio-org-list--entries-from-json-data parsed-json))
      (tabulated-list-print))
    (pio--display-buffer-passive org-list-buffer)))

(defun pio-team-list--members-string (members)
  "Return a readable members string from MEMBERS list."
  (if members
      (string-join (mapcar #'pio--person-display-name members) ", ")
    "n/a"))

(defun pio-team-list--tabulated-entry-from-team (org team index)
  "Convert ORG TEAM at INDEX into a `tabulated-list-entries' row."
  (let* ((team-name (pio-device-list--normalize-field
                     (pio-device-list--alist-get-any 'name team)))
         (description (pio-device-list--normalize-field
                       (pio-device-list--alist-get-any 'description team)))
         (members (pio-team-list--members-string
                   (pio-device-list--alist-get-any 'members team)))
         (team-id (pio-device-list--normalize-field
                   (pio-device-list--alist-get-any 'id team))))
    (list (format "%s:%s#%d" org team-name index)
          (vector org team-name description members team-id))))

(defun pio-team-list--entries-from-json-data (parsed-json)
  "Convert PARSED-JSON from `pio team list' into `tabulated-list-entries'."
  (let ((entries nil)
        (index 0))
    (dolist (org-pair parsed-json (nreverse entries))
      (let* ((org-key (car org-pair))
             (org-name (if (symbolp org-key) (symbol-name org-key) org-key))
             (teams (cdr org-pair)))
        (dolist (team teams)
          (setq index (1+ index))
          (push (pio-team-list--tabulated-entry-from-team org-name team index) entries))))))

(define-derived-mode pio-team-list-mode tabulated-list-mode "PIO-Teams"
  "Major mode for displaying `pio team list --json-output' in a table."
  (setq tabulated-list-format
        [("Org" 24 t)
         ("Team" 16 t)
         ("Description" 28 t)
         ("Members" 28 t)
         ("ID" 0 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Org" nil))
  (setq tabulated-list-use-header-line t)
  (tabulated-list-init-header))

(pio--bind-common-keys pio-team-list-mode-map)

(defun pio-team-list (&optional force-refresh)
  "Display `pio team list --json-output' in a table."
  (interactive "P")
  (let* ((parsed-json (pio--run-json-command-cached
                       'team-list
                       pio-cache-ttl-team-list
                       force-refresh
                       "team" "list" "--json-output"))
         (team-list-buffer (get-buffer-create pio-team-list-buffer-name)))
    (with-current-buffer team-list-buffer
      (pio-team-list-mode)
      (setq tabulated-list-entries (pio-team-list--entries-from-json-data parsed-json))
      (tabulated-list-print))
    (pio--display-buffer-passive team-list-buffer)))

(defun pio-remote-device-list--tabulated-entry-from-device (host device index)
  "Convert HOST DEVICE at INDEX into a `tabulated-list-entries' row."
  (let* ((port (pio-device-list--normalize-field
                (pio-device-list--alist-get-any 'port device)))
         (description (pio-device-list--normalize-field
                       (pio-device-list--alist-get-any 'description device)))
         (hwid (pio-device-list--normalize-field
                (pio-device-list--alist-get-any 'hwid device)))
         (entry-id (format "%s:%s#%d" host port index)))
    (list entry-id
          (vector host port description hwid))))

(defun pio-remote-device-list--entries-from-json (json-string)
  "Parse JSON-STRING and return `tabulated-list-entries'."
  (let ((parsed-json (json-parse-string json-string :object-type 'alist :array-type 'list))
        (entries nil)
        (index 0))
    (dolist (host-pair parsed-json (nreverse entries))
      (let* ((host-key (car host-pair))
             (host (pio-device-list--normalize-field
                    (if (symbolp host-key)
                        (symbol-name host-key)
                      host-key)))
             (devices (cdr host-pair)))
        (dolist (device devices)
          (setq index (1+ index))
          (push (pio-remote-device-list--tabulated-entry-from-device host device index)
                entries))))))

(defun pio-remote-device-list--entries-from-json-data (parsed-json)
  "Convert PARSED-JSON from `pio remote device list' into `tabulated-list-entries'."
  (let ((entries nil)
        (index 0))
    (dolist (host-pair parsed-json (nreverse entries))
      (let* ((host-key (car host-pair))
             (host (pio-device-list--normalize-field
                    (if (symbolp host-key) (symbol-name host-key) host-key)))
             (devices (cdr host-pair)))
        (dolist (device devices)
          (setq index (1+ index))
          (push (pio-remote-device-list--tabulated-entry-from-device host device index)
                entries))))))

(defun pio-remote-device-list--render-buffer (remote-device-list-buffer)
  "Initialize and render REMOTE-DEVICE-LIST-BUFFER for remote device output."
  (with-current-buffer remote-device-list-buffer
    (pio-remote-device-list-mode)
    (setq tabulated-list-entries nil)
    (setq-local pio-remote-device-list--json-accumulator nil)
    (tabulated-list-print)))

(defun pio-remote-device-list--append-process-output (process output-chunk)
  "Append OUTPUT-CHUNK from PROCESS into the current buffer accumulator."
  (when-let ((process-buffer (process-buffer process)))
    (with-current-buffer process-buffer
      (setq-local pio-remote-device-list--json-accumulator
                  (concat (or pio-remote-device-list--json-accumulator "") output-chunk)))))

(defun pio-remote-device-list--finalize-process (_process _event)
  "Finalize remote device output: parse JSON and refresh tabulated list."
  (when-let ((remote-device-list-buffer (get-buffer pio-remote-device-list-buffer-name)))
    (with-current-buffer remote-device-list-buffer
      (let* ((json-string (or pio-remote-device-list--json-accumulator "{}"))
             (tabulated-entries (pio-remote-device-list--entries-from-json json-string)))
        (setq tabulated-list-entries tabulated-entries
              pio-remote-device-list--json-accumulator nil)
        (tabulated-list-revert)))))

(define-derived-mode pio-remote-device-list-mode tabulated-list-mode "PIO-Remote-Devices"
  "Major mode for displaying `pio remote device list --json-output' in a table."
  (setq tabulated-list-format
        [("Host" 18 t)
         ("Port" 22 t)
         ("Description" 34 t)
         ("HWID" 0 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Host" nil))
  (setq tabulated-list-use-header-line t)
  (tabulated-list-init-header))

(pio--bind-common-keys pio-remote-device-list-mode-map)

(defun pio-remote-device-list (&optional force-refresh)
  "Display `pio remote device list --json-output' in a table."
  (interactive "P")
  (let* ((parsed-json (pio--run-json-command-cached
                       'remote-device-list
                       pio-cache-ttl-remote-device-list
                       force-refresh
                       "remote" "device" "list" "--json-output"))
         (remote-device-list-buffer (get-buffer-create pio-remote-device-list-buffer-name)))
    (with-current-buffer remote-device-list-buffer
      (pio-remote-device-list-mode)
      (setq tabulated-list-entries
            (pio-remote-device-list--entries-from-json-data parsed-json))
      (tabulated-list-print))
    (pio--display-buffer-passive remote-device-list-buffer)))

(define-derived-mode pio-run-list-targets-mode special-mode "PIO-Run-Targets"
  "Major mode for displaying `pio run --list-targets' output.")

(pio--bind-common-keys pio-run-list-targets-mode-map)

(defun pio-run-list-targets--append-process-output (process output-chunk)
  "Append OUTPUT-CHUNK from PROCESS directly into its process buffer."
  (pio--append-ansi-process-output process output-chunk))

(defun pio-run-list-targets--finalize-process (process event)
  "Finalize PROCESS for list targets output and append EVENT if needed."
  (when-let ((process-buffer (process-buffer process)))
    (with-current-buffer process-buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (unless (and (stringp event)
                     (string-match-p "finished" event))
          (insert "\n" event))))))

(defun pio-run-list-targets ()
  "Display raw output of `pio run --list-targets'."
  (interactive)
  (let* ((platformio-cli (pio-system-info--resolve-executable))
         (run-targets-buffer (get-buffer-create pio-run-list-targets-buffer-name)))
    (with-current-buffer run-targets-buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq-local ansi-color-context nil)
        (pio-run-list-targets-mode)))
    (pio--display-buffer-passive run-targets-buffer)
    (make-process
     :name "pio-run-list-targets"
     :buffer run-targets-buffer
     :command (list platformio-cli "run" "--list-targets")
     :filter #'pio-run-list-targets--append-process-output
     :sentinel #'pio-run-list-targets--finalize-process)))

(define-derived-mode pio-test-list-tests-mode special-mode "PIO-Test-List"
  "Major mode for displaying `pio test --list-tests' output.")

(pio--bind-common-keys pio-test-list-tests-mode-map)

(defun pio-test-list-tests--append-process-output (process output-chunk)
  "Append OUTPUT-CHUNK from PROCESS directly into its process buffer."
  (pio--append-ansi-process-output process output-chunk))

(defun pio-test-list-tests--finalize-process (process event)
  "Finalize PROCESS for list tests output and append EVENT if needed."
  (when-let ((process-buffer (process-buffer process)))
    (with-current-buffer process-buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (unless (and (stringp event)
                     (string-match-p "finished" event))
          (insert "\n" event))))))

(defun pio-test-list-tests ()
  "Display raw output of `pio test --list-tests'."
  (interactive)
  (let* ((platformio-cli (pio-system-info--resolve-executable))
         (test-list-buffer (get-buffer-create pio-test-list-tests-buffer-name)))
    (with-current-buffer test-list-buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq-local ansi-color-context nil)
        (pio-test-list-tests-mode)))
    (pio--display-buffer-passive test-list-buffer)
    (make-process
     :name "pio-test-list-tests"
     :buffer test-list-buffer
     :command (list platformio-cli "test" "--list-tests")
     :filter #'pio-test-list-tests--append-process-output
     :sentinel #'pio-test-list-tests--finalize-process)))

(defun pio-check--severity-face (severity)
  "Return a face for SEVERITY string."
  (pcase (downcase (format "%s" severity))
    ("high" 'error)
    ("medium" 'warning)
    ("low" 'font-lock-doc-face)
    (_ 'default)))

(defun pio-check--format-location (file line)
  "Return a compact location string for FILE and LINE."
  (format "%s:%s"
          (abbreviate-file-name (pio-device-list--normalize-field file))
          (if (numberp line) (number-to-string line) "-")))

(defun pio-check--tabulated-entry-from-defect (env tool defect index)
  "Convert DEFECT at INDEX into a `tabulated-list-entries' row."
  (let* ((severity (pio-device-list--normalize-field
                    (pio-device-list--alist-get-any 'severity defect)))
         (category (pio-device-list--normalize-field
                    (pio-device-list--alist-get-any 'category defect)))
         (defect-id (pio-device-list--normalize-field
                     (pio-device-list--alist-get-any 'id defect)))
         (message (pio-device-list--normalize-field
                   (pio-device-list--alist-get-any 'message defect)))
         (file (pio-device-list--alist-get-any 'file defect))
         (line (pio-device-list--alist-get-any 'line defect))
         (location (pio-check--format-location file line)))
    (list (format "%s#%d" defect-id index)
          (vector env
                  tool
                  (propertize severity 'face (pio-check--severity-face severity))
                  category
                  defect-id
                  location
                  message))))

(defun pio-check--entries-from-json (json-string)
  "Parse JSON-STRING and return `tabulated-list-entries'."
  (let ((parsed-json (json-parse-string json-string :object-type 'alist :array-type 'list))
        (entries nil)
        (index 0))
    (dolist (report parsed-json (nreverse entries))
      (let* ((env (pio-device-list--normalize-field
                   (pio-device-list--alist-get-any 'env report)))
             (tool (pio-device-list--normalize-field
                    (pio-device-list--alist-get-any 'tool report)))
             (defects (pio-device-list--alist-get-any 'defects report)))
        (dolist (defect defects)
          (setq index (1+ index))
          (push (pio-check--tabulated-entry-from-defect env tool defect index)
                entries))))))

(defun pio-check--render-buffer (check-buffer)
  "Initialize and render CHECK-BUFFER for pio check output."
  (with-current-buffer check-buffer
    (pio-check-mode)
    (setq tabulated-list-entries nil)
    (setq-local pio-check--json-accumulator nil)
    (tabulated-list-print)))

(defun pio-check--append-process-output (process output-chunk)
  "Append OUTPUT-CHUNK from PROCESS into the current buffer accumulator."
  (when-let ((process-buffer (process-buffer process)))
    (with-current-buffer process-buffer
      (setq-local pio-check--json-accumulator
                  (concat (or pio-check--json-accumulator "") output-chunk)))))

(defun pio-check--finalize-process (_process _event)
  "Finalize pio check output: parse JSON and refresh tabulated list."
  (when-let ((check-buffer (get-buffer pio-check-buffer-name)))
    (with-current-buffer check-buffer
      (let* ((json-string (or pio-check--json-accumulator "[]"))
             (tabulated-entries
              (condition-case err
                  (pio-check--entries-from-json json-string)
                (error
                 (list (list "pio-check-error"
                             (vector "-"
                                     "-"
                                     "error"
                                     "-"
                                     "parse"
                                     "-"
                                     (format "Failed to parse pio check output: %s"
                                             (error-message-string err)))))))))
        (setq tabulated-list-entries tabulated-entries
              pio-check--json-accumulator nil)
        (tabulated-list-revert)))))

(define-derived-mode pio-check-mode tabulated-list-mode "PIO-Check"
  "Major mode for displaying `pio check --json-output' in a table."
  (setq tabulated-list-format
        [("Env" 14 t)
         ("Tool" 10 t)
         ("Severity" 10 t)
         ("Category" 12 t)
         ("ID" 22 t)
         ("Location" 44 t)
         ("Message" 0 t)])
  (setq tabulated-list-padding 2)
  (setq tabulated-list-sort-key (cons "Severity" nil))
  (setq tabulated-list-use-header-line t)
  (tabulated-list-init-header))

(pio--bind-common-keys pio-check-mode-map)

(defun pio-check ()
  "Display `pio check --skip-packages --json-output' in a table."
  (interactive)
  (let* ((platformio-cli (pio-system-info--resolve-executable))
         (check-buffer (get-buffer-create pio-check-buffer-name)))
    (pio-check--render-buffer check-buffer)
    (pio--display-buffer-passive check-buffer)
    (make-process
     :name "pio-check"
     :buffer check-buffer
     :command (list platformio-cli "check" "--skip-packages" "--json-output")
     :filter #'pio-check--append-process-output
     :sentinel #'pio-check--finalize-process)))

(defun pio-project-config--value-to-string (value)
  "Return VALUE as a readable string for project config tables."
  (cond
   ((eq value :false) "false")
   ((eq value t) "true")
   ((null value) "null")
   ((stringp value) (if (string-empty-p value) "" value))
   ((listp value) (mapconcat #'pio-project-config--value-to-string value ", "))
   (t (format "%s" value))))

(defun pio-project-config--tabulated-entry-from-option (section option index)
  "Convert SECTION OPTION at INDEX into a `tabulated-list-entries' row."
  (let* ((option-key (car option))
         (option-value (cadr option))
         (key (pio-device-list--normalize-field option-key))
         (value (pio-project-config--value-to-string option-value)))
    (list (format "%s:%s#%d" section key index)
          (vector section key value))))

(defun pio-project-config--entries-from-json (json-string)
  "Parse JSON-STRING and return `tabulated-list-entries'."
  (let ((parsed-json (json-parse-string json-string :object-type 'alist :array-type 'list))
        (entries nil)
        (index 0))
    (dolist (section-pair parsed-json (nreverse entries))
      (let* ((section-name (pio-device-list--normalize-field (car section-pair)))
             (section-options (cadr section-pair)))
        (dolist (option section-options)
          (setq index (1+ index))
          (push (pio-project-config--tabulated-entry-from-option section-name option index)
                entries))))))

(defun pio-project-config--render-buffer (project-config-buffer)
  "Initialize PROJECT-CONFIG-BUFFER for raw config output."
  (with-current-buffer project-config-buffer
    (pio-project-config-mode)
    (setq-local pio-project-config--json-accumulator nil)
    (let ((inhibit-read-only t))
      (erase-buffer)
      (setq-local ansi-color-context nil))))

(defun pio-project-config--append-process-output (process output-chunk)
  "Append OUTPUT-CHUNK from PROCESS into the buffer as-is."
  (pio--append-ansi-process-output process output-chunk))

(defun pio-project-config--finalize-process (process event)
  "Finalize project config output and append EVENT if needed."
  (when-let ((project-config-buffer (get-buffer pio-project-config-buffer-name)))
    (with-current-buffer project-config-buffer
      (setq-local pio-project-config--json-accumulator nil)
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (unless (and (stringp event)
                     (string-match-p "finished" event))
          (insert "\n" event))))))

(define-derived-mode pio-project-config-mode special-mode "PIO-Project-Config"
  "Major mode for displaying raw `pio project config' output.")

(pio--bind-common-keys pio-project-config-mode-map)

(defun pio-project-config ()
  "Display raw output of `pio project config'."
  (interactive)
  (let* ((platformio-cli (pio-system-info--resolve-executable))
         (project-config-buffer (get-buffer-create pio-project-config-buffer-name)))
    (pio-project-config--render-buffer project-config-buffer)
    (pio--display-buffer-passive project-config-buffer)
    (make-process
     :name "pio-project-config"
     :buffer project-config-buffer
     :command (list platformio-cli "project" "config")
     :filter #'pio-project-config--append-process-output
     :sentinel #'pio-project-config--finalize-process)))

(defun pio-account-show--string-value (value)
  "Return VALUE as a user-friendly string."
  (cond
   ((eq value :false) "false")
   ((null value) "-")
   ((stringp value) (if (string-empty-p value) "-" value))
   (t (format "%s" value))))

(defun pio-account-show--format-expire-at (value)
  "Format VALUE as a friendly expiration time string."
  (if (numberp value)
      (format-time-string "%Y-%m-%d %H:%M:%S %Z" (seconds-to-time value))
    "-"))

(defun pio-account-show--service-title (service-value)
  "Return a user-facing title string for SERVICE-VALUE."
  (if (stringp service-value)
      service-value
    (pio-account-show--string-value
     (pio-device-list--alist-get-any 'title service-value))))

(defun pio-account-show--service-fields (package)
  "Extract human-readable service strings from PACKAGE."
  (let (services)
    (dolist (pair package (nreverse services))
      (let* ((raw-key (car pair))
             (key (if (symbolp raw-key) (symbol-name raw-key) raw-key))
             (value (cdr pair)))
        (when (and (stringp key)
                   (string-prefix-p "service." key))
          (push (pio-account-show--service-title value) services))))))

(defun pio-account-show--insert-heading (title)
  "Insert TITLE as a section heading."
  (insert (propertize title 'face 'font-lock-keyword-face) "\n")
  (insert (make-string (length title) ?=) "\n\n"))

(defun pio-account-show--insert-labeled-line (label value)
  "Insert LABEL and VALUE as a single aligned line."
  (insert (format "%-12s %s\n" (format "%s:" label)
                  (pio-account-show--string-value value))))

(defun pio-account-show--insert-profile (profile)
  "Insert profile details from PROFILE alist."
  (pio-account-show--insert-heading "Profile")
  (pio-account-show--insert-labeled-line "Username"
                                         (pio-device-list--alist-get-any 'username profile))
  (pio-account-show--insert-labeled-line "Email"
                                         (pio-device-list--alist-get-any 'email profile))
  (pio-account-show--insert-labeled-line "First name"
                                         (pio-device-list--alist-get-any 'firstname profile))
  (pio-account-show--insert-labeled-line "Last name"
                                         (pio-device-list--alist-get-any 'lastname profile))
  (insert "\n"))

(defun pio-account-show--insert-organizations (organizations)
  "Insert Organizations section from ORGANIZATIONS list."
  (pio-account-show--insert-heading "Organizations")
  (if organizations
      (dolist (org organizations)
        (let* ((orgname (pio-device-list--normalize-field
                         (pio-device-list--alist-get-any 'orgname org)))
               (displayname (pio-device-list--normalize-field
                             (pio-device-list--alist-get-any 'displayname org)))
               (email (pio-device-list--normalize-field
                       (pio-device-list--alist-get-any 'email org)))
               (owners (pio-org-list--owners-string
                        (pio-device-list--alist-get-any 'owners org))))
          (insert (propertize orgname 'face 'bold) "\n")
          (insert (make-string (length orgname) ?-) "\n")
          (pio-account-show--insert-labeled-line "Display" displayname)
          (pio-account-show--insert-labeled-line "Email" email)
          (pio-account-show--insert-labeled-line "Owners" owners)
          (insert "\n")))
    (insert "No organizations\n\n")))

(defun pio-account-show--insert-teams (teams-by-org)
  "Insert Teams section from TEAMS-BY-ORG alist."
  (pio-account-show--insert-heading "Teams")
  (if teams-by-org
      (dolist (org-pair teams-by-org)
        (let* ((org-key (car org-pair))
               (org-name (if (symbolp org-key) (symbol-name org-key) org-key))
               (teams (cdr org-pair)))
          (insert (propertize (format "Org: %s" org-name) 'face 'bold) "\n")
          (insert (make-string (+ 5 (length org-name)) ?-) "\n")
          (if teams
              (dolist (team teams)
                (let ((team-name (pio-device-list--normalize-field
                                  (pio-device-list--alist-get-any 'name team)))
                      (description (pio-device-list--normalize-field
                                    (pio-device-list--alist-get-any 'description team)))
                      (members (pio-team-list--members-string
                                (pio-device-list--alist-get-any 'members team))))
                  (insert (format "- %s\n" team-name))
                  (pio-account-show--insert-labeled-line "Description" description)
                  (pio-account-show--insert-labeled-line "Members" members)
                  (insert "\n")))
            (insert "No teams\n\n"))))
    (insert "No teams\n\n")))

(defun pio-account-show--insert-package (package)
  "Insert PACKAGE details in a readable text layout."
  (let ((title (pio-account-show--string-value
                (pio-device-list--alist-get-any 'title package)))
        (description (pio-device-list--alist-get-any 'description package))
        (path (pio-device-list--alist-get-any 'path package))
        (services (pio-account-show--service-fields package)))
    (insert (propertize title 'face 'bold) "\n")
    (insert (make-string (length title) ?-) "\n")
    (insert (pio-account-show--string-value description) "\n")
    (pio-account-show--insert-labeled-line "Path" path)
    (if services
        (progn
          (insert "Services:\n")
          (dolist (service services)
            (insert (format "- %s\n" service))))
      (insert "Services: -\n"))
    (insert "\n")))

(defun pio-account-show--render-data (account-show-buffer account)
  "Render ACCOUNT into ACCOUNT-SHOW-BUFFER."
  (with-current-buffer account-show-buffer
    (let ((inhibit-read-only t)
          (profile (pio-device-list--alist-get-any 'profile account))
          (packages (pio-device-list--alist-get-any 'packages account))
          (user-id (pio-device-list--alist-get-any 'user_id account))
          (expire-at (pio-device-list--alist-get-any 'expire_at account)))
      (erase-buffer)
      (pio-account-show-mode)
      (pio-account-show--insert-profile profile)
      (pio-account-show--insert-heading "Packages")
      (if packages
          (dolist (package packages)
            (pio-account-show--insert-package package))
        (insert "No packages\n\n"))
      (pio-account-show--insert-heading "Meta")
      (pio-account-show--insert-labeled-line "User ID" user-id)
      (pio-account-show--insert-labeled-line "Expire at"
                                             (pio-account-show--format-expire-at expire-at))
      (goto-char (point-min)))))

(define-derived-mode pio-account-show-mode special-mode "PIO-Account"
  "Major mode for displaying `pio account show --json-output' in readable text.")

(pio--bind-common-keys pio-account-show-mode-map)

(defun pio-account-show (&optional force-refresh)
  "Display `pio account show --json-output' in a readable text layout."
  (interactive "P")
  (let ((account-show-buffer (get-buffer-create pio-account-show-buffer-name)))
    (condition-case err
        (let ((account (pio--run-json-command-cached
                        'account-show
                        pio-cache-ttl-account-show
                        force-refresh
                        "account" "show" "--json-output")))
          (pio-account-show--render-data account-show-buffer account)
          (pio--display-buffer-passive account-show-buffer))
      (error
       (with-current-buffer account-show-buffer
         (pio-account-show-mode)
         (let ((inhibit-read-only t))
           (erase-buffer)
           (insert (format "Failed to load account data: %s\n" (error-message-string err)))))
       (pio--display-buffer-passive account-show-buffer)))))


(defun pio-mode (&optional _force-refresh)
  "Open the PlatformIO command dispatcher."
  (interactive "P")
  (pio-dispatch))

(provide 'pio-mode)
;;; pio-mode.el ends here
