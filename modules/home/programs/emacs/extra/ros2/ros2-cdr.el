;;; ros2-cdr.el --- ros2msg schema parser + CDR message reader -*- lexical-binding: t; -*-

;; Author: Mumtahin Farabi <mfarabi619@gmail.com>
;; Keywords: tools, ros2
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Decodes a ROS2 message from its CDR wire bytes given the concatenated
;; `ros2msg' schema the Foxglove bridge advertises alongside each channel.
;; `ros2-cdr-decode' returns a nested alist of (field-name . value) mirroring
;; the message structure, which the Raw Messages panel renders as a tree.
;;
;; Alignment is body-relative (offsets counted from the first byte after the
;; 4-byte encapsulation header); strings are a `uint32' length (including the
;; null terminator) then that many bytes; fixed arrays are contiguous; `[]'
;; sequences are a `uint32' count then the elements.  Little-endian only (what
;; the bridge sends); the encapsulation byte is checked.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defconst ros2-cdr--primitives
  '("bool" "byte" "char" "int8" "uint8" "int16" "uint16"
    "int32" "uint32" "int64" "uint64" "float32" "float64" "string" "wstring")
  "Primitive ros2msg type names (everything else names a nested message).")

;;; Schema parsing

(defun ros2-cdr--normalize-type (base)
  "Reduce a nested-message type reference BASE to its bare type name.
`std_msgs/Header' and `sensor_msgs/msg/Imu' both become their last segment;
primitive names contain no slash and pass through unchanged."
  (if (string-search "/" base)
      (car (last (split-string base "/")))
    base))

(defun ros2-cdr--parse-type (type name)
  "Return (NAME BASE ARRAY) parsed from a ros2msg TYPE token and field NAME.
ARRAY is nil, `seq' for a sequence, or an integer for a fixed `[N]' array."
  (let (base array)
    (cond
     ((string-match "\\`\\(.+\\)\\[\\([0-9]+\\)\\]\\'" type)
      (setq base (match-string 1 type) array (string-to-number (match-string 2 type))))
     ((string-match "\\`\\(.+\\)\\[<=[0-9]+\\]\\'" type)
      (setq base (match-string 1 type) array 'seq))
     ((string-match "\\`\\(.+\\)\\[\\]\\'" type)
      (setq base (match-string 1 type) array 'seq))
     (t (setq base type array nil)))
    (when (string-match "\\`\\(w?string\\)<=[0-9]+\\'" base)
      (setq base (match-string 1 base)))
    (list name (ros2-cdr--normalize-type base) array)))

(defun ros2-cdr--parse-field-line (line)
  "Return (NAME BASE ARRAY) for a field LINE, or nil for a non-field line.
A constant has `= VALUE' after its name; a plain field does not."
  (let ((s (string-trim (replace-regexp-in-string "#.*\\'" "" line))))
    (when (and (not (string-empty-p s))
               (not (string-prefix-p "MSG:" s))
               (not (string-match-p "\\`[^ \t]+[ \t]+[A-Za-z_][A-Za-z0-9_]*[ \t]*=" s))
               (string-match "\\`\\([^ \t]+\\)[ \t]+\\([A-Za-z_][A-Za-z0-9_]*\\)" s))
      (ros2-cdr--parse-type (match-string 1 s) (match-string 2 s)))))

(defun ros2-cdr--parse-named-section (lines)
  "Return (TYPE-NAME . FIELDS) for a nested-message section's LINES.
The name comes from the section's `MSG: pkg/Type' header."
  (let (name fields)
    (dolist (line lines)
      (let ((s (string-trim line)))
        (if (string-prefix-p "MSG:" s)
            (setq name (ros2-cdr--normalize-type (string-trim (substring s 4))))
          (when-let ((field (ros2-cdr--parse-field-line line)))
            (push field fields)))))
    (cons name (nreverse fields))))

(defun ros2-cdr--parse-schema (text)
  "Parse concatenated ros2msg TEXT into (MAIN-FIELDS . TYPE-TABLE).
MAIN-FIELDS is the root message's field list; TYPE-TABLE maps each nested
type name to its field list."
  (let (sections current)
    (dolist (line (split-string text "\n"))
      (if (string-match-p "\\`=\\{3,\\}\\'" (string-trim line))
          (progn (push (nreverse current) sections) (setq current nil))
        (push line current)))
    (push (nreverse current) sections)
    (setq sections (nreverse sections))
    (cons (delq nil (mapcar #'ros2-cdr--parse-field-line (car sections)))
          (mapcar #'ros2-cdr--parse-named-section (cdr sections)))))

;;; CDR reader

(cl-defstruct (ros2-cdr--cursor (:constructor ros2-cdr--cursor)
                                (:copier nil))
  bytes (offset 0))

(defun ros2-cdr--align (cursor size)
  "Advance CURSOR's offset to the next boundary of SIZE bytes."
  (let ((rem (% (ros2-cdr--cursor-offset cursor) size)))
    (unless (zerop rem)
      (cl-incf (ros2-cdr--cursor-offset cursor) (- size rem)))))

(defun ros2-cdr--uint (cursor size)
  "Read an unsigned little-endian integer of SIZE bytes from CURSOR."
  (ros2-cdr--align cursor size)
  (let ((bytes (ros2-cdr--cursor-bytes cursor))
        (offset (ros2-cdr--cursor-offset cursor))
        (value 0))
    (dotimes (i size)
      (setq value (logior value (ash (aref bytes (+ offset i)) (* 8 i)))))
    (cl-incf (ros2-cdr--cursor-offset cursor) size)
    value))

(defun ros2-cdr--sint (cursor size)
  "Read a signed little-endian integer of SIZE bytes from CURSOR."
  (let ((value (ros2-cdr--uint cursor size))
        (bits (* 8 size)))
    (if (>= value (ash 1 (1- bits))) (- value (ash 1 bits)) value)))

(defun ros2-cdr--bits-to-float (bits nbytes)
  "Reinterpret integer BITS, which spans NBYTES bytes, as an IEEE-754 float."
  (let* ((total (* 8 nbytes))
         (ebits (if (= nbytes 8) 11 8))
         (mbits (if (= nbytes 8) 52 23))
         (bias (if (= nbytes 8) 1023 127))
         (sign (if (zerop (logand bits (ash 1 (1- total)))) 1 -1))
         (exp  (logand (ash bits (- mbits)) (1- (ash 1 ebits))))
         (frac (logand bits (1- (ash 1 mbits)))))
    (cond
     ((and (zerop exp) (zerop frac)) (* sign 0.0))
     ((= exp (1- (ash 1 ebits)))
      (if (zerop frac) (* sign 1.0e+INF) 0.0e+NaN))
     ((zerop exp)
      (* sign (ldexp (/ (float frac) (ash 1 mbits)) (- 1 bias))))
     (t (* sign (ldexp (+ 1.0 (/ (float frac) (ash 1 mbits))) (- exp bias)))))))

(defun ros2-cdr--float (cursor size)
  "Read a little-endian IEEE-754 float of SIZE bytes from CURSOR."
  (ros2-cdr--bits-to-float (ros2-cdr--uint cursor size) size))

(defun ros2-cdr--string (cursor)
  "Read a CDR string (uint32 length including null, then the bytes) from CURSOR."
  (let* ((len (ros2-cdr--uint cursor 4))
         (bytes (ros2-cdr--cursor-bytes cursor))
         (offset (ros2-cdr--cursor-offset cursor))
         (raw (if (> len 0) (substring bytes offset (+ offset (1- len))) "")))
    (cl-incf (ros2-cdr--cursor-offset cursor) len)
    (decode-coding-string raw 'utf-8)))

(defun ros2-cdr--read-scalar (cursor base table)
  "Read one value of type BASE from CURSOR, resolving nested types via TABLE."
  (pcase base
    ("bool" (if (= (ros2-cdr--uint cursor 1) 1) t :false))
    ("int8" (ros2-cdr--sint cursor 1))
    ((or "uint8" "byte" "char") (ros2-cdr--uint cursor 1))
    ("int16" (ros2-cdr--sint cursor 2))
    ("uint16" (ros2-cdr--uint cursor 2))
    ("int32" (ros2-cdr--sint cursor 4))
    ("uint32" (ros2-cdr--uint cursor 4))
    ("int64" (ros2-cdr--sint cursor 8))
    ("uint64" (ros2-cdr--uint cursor 8))
    ("float32" (ros2-cdr--float cursor 4))
    ("float64" (ros2-cdr--float cursor 8))
    ((or "string" "wstring") (ros2-cdr--string cursor))
    (_ (if-let ((fields (cdr (assoc base table))))
           (ros2-cdr--read-message cursor fields table)
         (error "Unknown ros2 message type `%s'" base)))))

(defun ros2-cdr--read-field (cursor base array table)
  "Read a field of BASE type with ARRAY multiplicity from CURSOR via TABLE."
  (cond
   ((eq array 'seq)
    (let ((n (ros2-cdr--uint cursor 4)))
      (cl-loop repeat n collect (ros2-cdr--read-scalar cursor base table))))
   ((integerp array)
    (cl-loop repeat array collect (ros2-cdr--read-scalar cursor base table)))
   (t (ros2-cdr--read-scalar cursor base table))))

(defun ros2-cdr--read-message (cursor fields table)
  "Read a message of FIELDS from CURSOR via TABLE into a (name . value) alist."
  (mapcar (lambda (field)
            (cons (nth 0 field)
                  (ros2-cdr--read-field cursor (nth 1 field) (nth 2 field) table)))
          fields))

;;; Entry point

(defun ros2-cdr-decode (schema-text bytes)
  "Decode CDR BYTES against the concatenated ros2msg SCHEMA-TEXT.
BYTES is a unibyte string starting with the 4-byte encapsulation header.
Return a nested alist of (field-name . value) for the root message."
  (unless (and (>= (length bytes) 4) (= (aref bytes 1) 1))
    (error "Not little-endian CDR (encapsulation byte %s)"
           (and (>= (length bytes) 2) (aref bytes 1))))
  (pcase-let* ((`(,main . ,table) (ros2-cdr--parse-schema schema-text))
               (cursor (ros2-cdr--cursor :bytes (substring bytes 4))))
    (ros2-cdr--read-message cursor main table)))

(provide 'ros2-cdr)
;;; ros2-cdr.el ends here
