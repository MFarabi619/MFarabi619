;;; mcumgr-tramp.el --- TRAMP method for MCUmgr device filesystems  -*- lexical-binding: t -*-

;; Copyright (C) 2026 Mumtahin Farabi

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; URL: https://github.com/MFarabi619/MFarabi619/modules/home/programs/emacs/extra/mcumgr
;; Keywords: lisp, tools, comm
;; Version: 0.0.1
;; Package-Requires: ((emacs "30.1"))

;; This file is not part of GNU Emacs.

;;; Commentary:
;;
;; A read-only TRAMP method over Zephyr's MCUmgr protocol:
;;
;;   /mcumgr:usbmodem1101:/SD:/www/index.html
;;
;; opens device files in Dired, dirvish, and `find-file', backed by the
;; mcumgr.el request layer (`shell fs ls' for listings, `fs download'
;; for contents).  Four handlers do real work;
;; everything else aliases TRAMP's generic implementations, and every
;; mutating operation signals that the filesystem is read-only.

;;; Code:

(require 'mcumgr)
(require 'tramp)

(defconst mcumgr-tramp-method "mcumgr"
  "TRAMP method name for MCUmgr device filesystems.")

;;; Host resolution

(defun mcumgr-tramp--candidate-ports ()
  "Return enumerated USB serial ports, without /dev/tty.* duplicates."
  (seq-remove (lambda (port) (string-prefix-p "/dev/tty." port))
              (mapcar (lambda (device) (plist-get device :port_name))
                      (mcumgr-usb-serial-devices))))

(defun mcumgr-tramp-parse-device-names (_ignore)
  "Return (nil HOST) tuples for hosts TRAMP may complete."
  (ignore-errors
    (mapcar (lambda (port) (list nil (file-name-nondirectory port)))
            (mcumgr-tramp--candidate-ports))))

(defun mcumgr-tramp--transport (vec)
  "Resolve VEC's host to a transport plist, serial before UDP, uncached."
  (let ((host (tramp-file-name-host vec)))
    (cond
     ((and (stringp host) (not (string-empty-p host)))
      (if-let* ((port (seq-find (lambda (candidate)
                                  (string-suffix-p host candidate))
                                (mcumgr-tramp--candidate-ports))))
          (list :serial port)
        (list :udp host)))
     (t
      (let ((ports (mcumgr-tramp--candidate-ports)))
        (if (length= ports 1)
            (list :serial (car ports))
          (tramp-error vec 'file-error
                       "Cannot pick among %d connected devices"
                       (length ports))))))))

;;; Listings and attributes

(defun mcumgr-tramp--listing (vec localname)
  "Return the parsed fs entries of the directory LOCALNAME on VEC, cached."
  (let ((path (if (member localname '(nil "" "/"))
                  "/"
                (directory-file-name localname))))
    (with-tramp-file-property vec path "mcumgr-listing"
      (mcumgr--parse-fs-listing
       (apply #'mcumgr--run
              (mcumgr--shell-args (mcumgr-tramp--transport vec)
                                  "fs" "ls" path))))))

(defun mcumgr-tramp--raw-attributes (vec directory-p size)
  "Return a raw `file-attributes' list for VEC from DIRECTORY-P and SIZE."
  (list directory-p
        1
        (cons "root" tramp-unknown-id-integer)
        (cons "root" tramp-unknown-id-integer)
        tramp-time-dont-know
        tramp-time-dont-know
        tramp-time-dont-know
        size
        (if directory-p "dr-xr-xr-x" "-r--r--r--")
        t 1
        (tramp-get-device vec)))

(defun mcumgr-tramp--attributes (vec localname)
  "Return raw attributes for LOCALNAME on VEC, or nil when absent."
  (if (member localname '("" "/"))
      (mcumgr-tramp--raw-attributes vec t 0)
    (let* ((parent (or (file-name-directory (directory-file-name localname))
                       "/"))
           (name (file-name-nondirectory (directory-file-name localname)))
           (entry (seq-find
                   (lambda (candidate)
                     (equal (plist-get candidate :name) name))
                   (mcumgr-tramp--listing vec parent))))
      (when entry
        (mcumgr-tramp--raw-attributes
         vec (plist-get entry :directory-p) (plist-get entry :size))))))

;;; Handlers

(defun mcumgr-tramp-handle-file-attributes (filename &optional id-format)
  "Like `file-attributes' for MCUmgr TRAMP FILENAME, in ID-FORMAT."
  (with-parsed-tramp-file-name (expand-file-name filename) nil
    (tramp-convert-file-attributes v localname id-format
      (mcumgr-tramp--attributes v localname))))

(defun mcumgr-tramp-handle-directory-files-and-attributes
    (directory &optional full match nosort id-format count)
  "Like `directory-files-and-attributes' for MCUmgr TRAMP files.
DIRECTORY, FULL, MATCH, NOSORT, ID-FORMAT and COUNT are as documented."
  (tramp-skeleton-directory-files-and-attributes
      directory full match nosort id-format count
    (let ((self (mcumgr-tramp--raw-attributes v t 0)))
      (append
       (list (cons "." self) (cons ".." self))
       (mapcar (lambda (entry)
                 (cons (plist-get entry :name)
                       (mcumgr-tramp--raw-attributes
                        v
                        (plist-get entry :directory-p)
                        (plist-get entry :size))))
               (mcumgr-tramp--listing v localname))))))

(defun mcumgr-tramp-handle-file-local-copy (filename)
  "Download the MCUmgr TRAMP FILENAME into a local temp file."
  (tramp-skeleton-file-local-copy filename
    (mcumgr-fs-download (mcumgr-tramp--transport v) localname tmpfile)))

(defun mcumgr-tramp-handle-file-name-all-completions (filename directory)
  "Like `file-name-all-completions' for FILENAME in a MCUmgr DIRECTORY."
  (tramp-skeleton-file-name-all-completions filename directory
    (all-completions
     filename
     (with-parsed-tramp-file-name (expand-file-name directory) nil
       (mapcar (lambda (entry)
                 (let ((name (plist-get entry :name)))
                   (if (plist-get entry :directory-p)
                       (file-name-as-directory name)
                     name)))
               (mcumgr-tramp--listing v localname))))))

(defun mcumgr-tramp--read-only (&rest _args)
  "Signal that MCUmgr TRAMP filesystems are read-only."
  (signal 'file-error '("mcumgr TRAMP is read-only (for now)")))

;;; Registration

(defconst mcumgr-tramp-file-name-handler-alist
  '((access-file . tramp-handle-access-file)
    (add-name-to-file . mcumgr-tramp--read-only)
    (copy-directory . mcumgr-tramp--read-only)
    (copy-file . mcumgr-tramp--read-only)
    (delete-directory . mcumgr-tramp--read-only)
    (delete-file . mcumgr-tramp--read-only)
    (directory-file-name . tramp-handle-directory-file-name)
    (directory-files . tramp-handle-directory-files)
    (directory-files-and-attributes
     . mcumgr-tramp-handle-directory-files-and-attributes)
    (dired-compress-file . ignore)
    (dired-uncache . tramp-handle-dired-uncache)
    (exec-path . ignore)
    (expand-file-name . tramp-handle-expand-file-name)
    (file-accessible-directory-p . tramp-handle-file-accessible-directory-p)
    (file-acl . ignore)
    (file-attributes . mcumgr-tramp-handle-file-attributes)
    (file-directory-p . tramp-handle-file-directory-p)
    (file-equal-p . tramp-handle-file-equal-p)
    (file-executable-p . tramp-handle-file-directory-p)
    (file-exists-p . tramp-handle-file-exists-p)
    (file-group-gid . tramp-handle-file-group-gid)
    (file-in-directory-p . tramp-handle-file-in-directory-p)
    (file-local-copy . mcumgr-tramp-handle-file-local-copy)
    (file-locked-p . tramp-handle-file-locked-p)
    (file-modes . tramp-handle-file-modes)
    (file-name-all-completions
     . mcumgr-tramp-handle-file-name-all-completions)
    (file-name-as-directory . tramp-handle-file-name-as-directory)
    (file-name-case-insensitive-p . tramp-handle-file-name-case-insensitive-p)
    (file-name-completion . tramp-handle-file-name-completion)
    (file-name-directory . tramp-handle-file-name-directory)
    (file-name-nondirectory . tramp-handle-file-name-nondirectory)
    (file-newer-than-file-p . tramp-handle-file-newer-than-file-p)
    (file-notify-add-watch . ignore)
    (file-notify-rm-watch . ignore)
    (file-notify-valid-p . ignore)
    (file-ownership-preserved-p . ignore)
    (file-readable-p . tramp-handle-file-exists-p)
    (file-regular-p . tramp-handle-file-regular-p)
    (file-remote-p . tramp-handle-file-remote-p)
    (file-selinux-context . tramp-handle-file-selinux-context)
    (file-symlink-p . tramp-handle-file-symlink-p)
    (file-system-info . ignore)
    (file-truename . tramp-handle-file-truename)
    (file-user-uid . tramp-handle-file-user-uid)
    (file-writable-p . ignore)
    (find-backup-file-name . ignore)
    (insert-directory . tramp-handle-insert-directory)
    (insert-file-contents . tramp-handle-insert-file-contents)
    (list-system-processes . ignore)
    (load . tramp-handle-load)
    (lock-file . ignore)
    (make-auto-save-file-name . ignore)
    (make-directory . mcumgr-tramp--read-only)
    (make-directory-internal . ignore)
    (make-lock-file-name . ignore)
    (make-nearby-temp-file . ignore)
    (make-process . ignore)
    (make-symbolic-link . mcumgr-tramp--read-only)
    (process-attributes . ignore)
    (process-file . ignore)
    (rename-file . mcumgr-tramp--read-only)
    (set-file-acl . ignore)
    (set-file-modes . mcumgr-tramp--read-only)
    (set-file-selinux-context . ignore)
    (set-file-times . mcumgr-tramp--read-only)
    (set-visited-file-modtime . tramp-handle-set-visited-file-modtime)
    (shell-command . ignore)
    (start-file-process . ignore)
    (tramp-get-home-directory . ignore)
    (tramp-set-file-uid-gid . ignore)
    (unhandled-file-name-directory . ignore)
    (unlock-file . ignore)
    (vc-registered . ignore)
    (verify-visited-file-modtime . tramp-handle-verify-visited-file-modtime)
    (write-region . mcumgr-tramp--read-only))
  "Operations handled for /mcumgr: file names.")

(defsubst mcumgr-tramp-file-name-p (vec-or-filename)
  "Non-nil when VEC-OR-FILENAME names a file on the mcumgr TRAMP method."
  (and-let* ((vec (tramp-ensure-dissected-file-name vec-or-filename))
             ((string= (tramp-file-name-method vec) mcumgr-tramp-method)))))

(defun mcumgr-tramp-file-name-handler (operation &rest args)
  "Dispatch OPERATION with ARGS for /mcumgr: file names."
  (if-let* ((handler (cdr (assoc operation
                                 mcumgr-tramp-file-name-handler-alist))))
      (save-match-data (apply handler args))
    (tramp-run-real-handler operation args)))

(add-to-list 'tramp-methods
             `(,mcumgr-tramp-method
               (tramp-login-program "mcumgrctl")
               (tramp-login-args (("%h")))))
(add-to-list 'tramp-default-host-alist `(,mcumgr-tramp-method nil ""))
(tramp-set-completion-function
 mcumgr-tramp-method '((mcumgr-tramp-parse-device-names "")))
(tramp-register-foreign-file-name-handler
 #'mcumgr-tramp-file-name-p #'mcumgr-tramp-file-name-handler)

(provide 'mcumgr-tramp)

;;; mcumgr-tramp.el ends here
