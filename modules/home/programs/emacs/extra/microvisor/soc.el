;;; soc.el --- ASCII top-view SoC package diagrams -*- lexical-binding: t; -*-

;; Author: Mumtahin Farabi <farabi@apidaesystems.ca>
;; Keywords: tools, embedded, hardware, zephyr
;; URL: https://github.com/MFarabi619/soc.el
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Companion to `pinout.el'.  Where pinout draws breakout-board pin
;; headers, soc draws QFN/LQFP top-view diagrams of the silicon
;; itself: pin numbers inside the chip body, silicon-function names
;; as Powerline-style chevron tags outside, optional dashed die
;; outline.
;;
;; Three-layer data model:
;;
;;   PACKAGE -- silicon facts (pin -> name, type).  From datasheet.
;;              Lives in `soc-packages'.  Immutable across projects.
;;
;;   OVERLAY -- project facts (pin -> devicetree node assignment).
;;              Lives in `soc-overlays'.  Renderer is silent on this
;;              layer for now; a future tree-sitter pass on the
;;              project .overlay will populate it.
;;
;;   RENDER  -- layout + draw, parameterised by `soc-type-faces'.
;;
;; The chevron tag glyphs (U+E0B0, U+E0B2) live in the Powerline /
;; Nerd Font PUA; pick a font that ships them so the labels render
;; as solid hexagonal tabs rather than empty rectangles.
;;
;; Entry point: `M-x soc'.

;;; Code:

(require 'cl-lib)
(require 'face-remap)


;;; ============================================================
;;; Customization
;;; ============================================================

(defgroup soc nil
  "SoC top-view package diagrams."
  :group 'tools
  :prefix "soc-")

(defcustom soc-default-package "esp32-s3-qfn56"
  "Package key rendered when `soc' is called with no argument."
  :type 'string :group 'soc)

(defcustom soc-pin-pitch-horizontal 5
  "Minimum cells between adjacent top/bottom-side pins."
  :type 'natnum :group 'soc)

(defcustom soc-pin-pitch-vertical 2
  "Minimum rows between adjacent left/right-side pins.
The renderer auto-grows this so the chip body stays near visually
square given `soc-font-aspect-ratio'."
  :type 'natnum :group 'soc)

(defcustom soc-font-aspect-ratio 2.0
  "Assumed monospace font height:width ratio.
2.0 fits Iosevka / JetBrains Mono.  1.6 is closer to SF Mono.
Used only to scale `pitch_v' so the chip body comes out square."
  :type 'number :group 'soc)

(defcustom soc-chip-margin 3
  "Cells of clearance between a corner and the first pin connector."
  :type 'natnum :group 'soc)

(defcustom soc-lead-length 3
  "Length in cells of the lead between chip wall and silicon-name tag."
  :type 'natnum :group 'soc)

(defcustom soc-show-die-outline t
  "When non-nil, draw a dashed inner rectangle suggesting the die."
  :type 'boolean :group 'soc)

(defcustom soc-font-family nil
  "Buffer-local font family for soc buffers.
Use a font shipping the Powerline / Nerd Font glyphs so the
chevron tags render as solid hexagonal arrow tabs."
  :type '(choice (const :tag "Default" nil) (string :tag "Family"))
  :group 'soc)

(defcustom soc-font-height 3.5
  "Maximum scale factor for the default face height in soc buffers."
  :type 'number :group 'soc)

(defcustom soc-packages
  '((esp32-s3-qfn56
     :family  "ESP32-S3"
     :core    "Xtensa LX7"
     :package "QFN56"
     :sides
     ((left   . (1  2  3  4  5  6  7  8  9 10 11 12 13 14))
      (bottom . (15 16 17 18 19 20 21 22 23 24 25 26 27 28))
      (right  . (42 41 40 39 38 37 36 35 34 33 32 31 30 29))
      (top    . (56 55 54 53 52 51 50 49 48 47 46 45 44 43)))
     :pins
     ((1  :name "LNA_IN"     :type rf)
      (2  :name "VDD3P3"     :type power)
      (3  :name "VDD3P3"     :type power)
      (4  :name "CHIP_PU"    :type reset)
      (5  :name "GPIO0"      :type gpio)
      (6  :name "GPIO1"      :type gpio)
      (7  :name "GPIO2"      :type gpio)
      (8  :name "GPIO3"      :type gpio)
      (9  :name "GPIO4"      :type gpio)
      (10 :name "GPIO5"      :type gpio)
      (11 :name "GPIO6"      :type gpio)
      (12 :name "GPIO7"      :type gpio)
      (13 :name "GPIO8"      :type gpio)
      (14 :name "GPIO9"      :type gpio)
      (15 :name "GPIO10"     :type gpio)
      (16 :name "GPIO11"     :type gpio)
      (17 :name "GPIO12"     :type gpio)
      (18 :name "GPIO13"     :type gpio)
      (19 :name "GPIO14"     :type gpio)
      (20 :name "VDD3P3_RTC" :type power)
      (21 :name "XTAL_32K_P" :type clock)
      (22 :name "XTAL_32K_N" :type clock)
      (23 :name "GPIO17"     :type gpio)
      (24 :name "GPIO18"     :type gpio)
      (25 :name "GPIO19"     :type gpio)
      (26 :name "GPIO20"     :type gpio)
      (27 :name "GPIO21"     :type gpio)
      (28 :name "SPICS1"     :type spi)
      (29 :name "VDD_SPI"    :type power)
      (30 :name "SPIHD"      :type spi)
      (31 :name "SPIWP"      :type spi)
      (32 :name "SPICS0"     :type spi)
      (33 :name "SPICLK"     :type spi)
      (34 :name "SPIQ"       :type spi)
      (35 :name "SPID"       :type spi)
      (36 :name "SPICLK_N"   :type spi)
      (37 :name "SPICLK_P"   :type spi)
      (38 :name "GPIO33"     :type gpio)
      (39 :name "GPIO34"     :type gpio)
      (40 :name "GPIO35"     :type gpio)
      (41 :name "GPIO36"     :type gpio)
      (42 :name "GPIO37"     :type gpio)
      (43 :name "GPIO38"     :type gpio)
      (44 :name "MTCK"       :type debug)
      (45 :name "MTDO"       :type debug)
      (46 :name "VDD3P3_CPU" :type power)
      (47 :name "MTDI"       :type debug)
      (48 :name "MTMS"       :type debug)
      (49 :name "U0TXD"      :type uart)
      (50 :name "U0RXD"      :type uart)
      (51 :name "GPIO45"     :type gpio)
      (52 :name "GPIO46"     :type gpio)
      (53 :name "XTAL_N"     :type clock)
      (54 :name "XTAL_P"     :type clock)
      (55 :name "VDDA"       :type power)
      (56 :name "VDDA"       :type power))))
  "Alist of package-key -> (:family :core :package :sides :pins).
:sides maps side -> pin numbers in visual order.
:pins  maps pin number -> (:name STR :type SYM)."
  :type 'sexp :group 'soc)

(defcustom soc-overlays nil
  "Alist of overlay-key -> (:package KEY :assignments ALIST).
:assignments maps pin number -> (:label STR :type SYM).
Renderer is silent on this layer for now; a future tree-sitter
pass on the project .overlay will populate it."
  :type 'sexp :group 'soc)


;;; ============================================================
;;; Faces
;;; ============================================================

(defface soc-power        '((t :background "#e57373" :foreground "#1d2021" :weight bold)) "Power rail.")
(defface soc-ground       '((t :background "#bdbdbd" :foreground "#1d2021" :weight bold)) "Ground.")
(defface soc-gpio         '((t :background "#9ccc65" :foreground "#1d2021" :weight bold)) "General GPIO.")
(defface soc-adc          '((t :background "#ff9800" :foreground "#1d2021" :weight bold)) "Analog input.")
(defface soc-i2c          '((t :background "#4fc3f7" :foreground "#1d2021" :weight bold)) "I2C peripheral.")
(defface soc-spi          '((t :background "#ce93d8" :foreground "#1d2021" :weight bold)) "SPI peripheral.")
(defface soc-uart         '((t :background "#26a69a" :foreground "#1d2021" :weight bold)) "UART peripheral.")
(defface soc-clock        '((t :background "#cddc39" :foreground "#1d2021" :weight bold)) "Crystal / clock pin.")
(defface soc-reset        '((t :background "#ffc107" :foreground "#1d2021" :weight bold)) "Reset / strap pin.")
(defface soc-debug        '((t :background "#8896a0" :foreground "#1d2021" :weight bold)) "Debug / JTAG.")
(defface soc-rf           '((t :background "#7986cb" :foreground "#1d2021" :weight bold)) "RF / antenna.")
(defface soc-flash        '((t :background "#90a4ae" :foreground "#1d2021" :weight bold)) "Flash / PSRAM bus.")
(defface soc-pin-number   '((t :weight bold))                                             "Pin numbers inside the chip body (per-pin colour applied via `soc--num-face').")
(defface soc-chip-body    '((t :weight bold))                                             "Generic centred chip label.")
(defface soc-chip-family  '((t :background "#78909c" :foreground "#1d2021" :weight bold)) "Family-name chip in chip centre.")
(defface soc-chip-core    '((t :slant italic :weight bold))                               "Core / CPU name under family.")
(defface soc-chip-package '((t :foreground "#8896a0" :slant italic))                      "Package marking under core.")
(defface soc-die          '((t :foreground "#8896a0"))                                    "Dashed die outline.")
(defface soc-assignment   '((t :background "#26a69a" :foreground "#1d2021" :slant italic)) "Devicetree assignment tag (overlay layer).")

(defcustom soc-type-faces
  '((power  . soc-power)
    (ground . soc-ground)
    (gpio   . soc-gpio)
    (adc    . soc-adc)
    (i2c    . soc-i2c)
    (spi    . soc-spi)
    (uart   . soc-uart)
    (clock  . soc-clock)
    (reset  . soc-reset)
    (debug  . soc-debug)
    (rf     . soc-rf)
    (flash  . soc-flash))
  "Mapping from pin :type symbol to face for its tag."
  :type '(alist :key-type symbol :value-type face)
  :group 'soc)


;;; ============================================================
;;; Type / colour helpers
;;; ============================================================

(defun soc--type-face (type)
  "Face for pin TYPE.  Falls back to `soc-gpio'."
  (or (alist-get type soc-type-faces) 'soc-gpio))

(defun soc--type-color (type)
  "Foreground colour for pin numbers of TYPE — the tag face's background."
  (let* ((face (soc--type-face type))
         (bg   (face-attribute face :background nil 'default)))
    (and (stringp bg) (not (string-prefix-p "unspecified" bg)) bg)))

(defun soc--num-face (type)
  "Face spec for a pin number coloured by its TYPE."
  (let ((color (soc--type-color type)))
    (if color
        `(:foreground ,color :weight bold)
      'soc-pin-number)))

(defun soc--line-face (type)
  "Face spec for connection lines: foreground-only colour from TYPE."
  (let ((color (soc--type-color type)))
    (and color `(:foreground ,color))))


;;; ============================================================
;;; Grid
;;;
;;; A grid is a vector of rows; each row is a vector of cells.  A
;;; cell is nil (renders as a space) or (CHAR . PROPS-PLIST).
;;; Drawing functions mutate the grid; one flush at the end writes
;;; the buffer.
;;; ============================================================

(defun soc--grid (rows cols)
  "Allocate a fresh ROWS×COLS grid."
  (cl-loop with g = (make-vector rows nil)
           for i below rows do (aset g i (make-vector cols nil))
           finally return g))

(defun soc--cell (char &rest props)
  "Build a cell of CHAR with text PROPS plist."
  (cons char props))

(defun soc--set (grid row col cell)
  "Set GRID[ROW][COL] = CELL when in bounds."
  (when (and (>= row 0) (< row (length grid))
             (>= col 0) (< col (length (aref grid 0))))
    (aset (aref grid row) col cell)))

(defun soc--write (grid row col text &rest props)
  "Write TEXT into GRID starting at (ROW, COL).  PROPS applied per char."
  (cl-loop for i below (length text) do
           (soc--set grid row (+ col i)
                     (apply #'soc--cell (aref text i) props))))

(defun soc--flush (grid left-pad)
  "Insert GRID into the current buffer.
Each row is prefixed with LEFT-PAD spaces."
  (let ((pad (make-string left-pad ?\s)))
    (cl-loop for row across grid do
             (insert pad)
             (cl-loop for cell across row do
                      (cond
                       ((null cell) (insert ?\s))
                       ((consp cell)
                        (let ((s (char-to-string (car cell))))
                          (when (cdr cell)
                            (add-text-properties 0 1 (cdr cell) s))
                          (insert s)))))
             (insert ?\n))))


;;; ============================================================
;;; Drawing primitives
;;; ============================================================

(defun soc--draw-chip-body (grid layout)
  "Draw the outer chip rectangle into GRID.
Pin connectors overwrite the edges at their pin columns."
  (let ((top   (plist-get layout :chip-top))
        (bot   (plist-get layout :chip-bot))
        (left  (plist-get layout :chip-left))
        (right (plist-get layout :chip-right)))
    (soc--set grid top left  (soc--cell ?┌))
    (soc--set grid top right (soc--cell ?┐))
    (soc--set grid bot left  (soc--cell ?└))
    (soc--set grid bot right (soc--cell ?┘))
    (cl-loop for c from (1+ left) below right do
             (soc--set grid top c (soc--cell ?─))
             (soc--set grid bot c (soc--cell ?─)))
    (cl-loop for r from (1+ top) below bot do
             (soc--set grid r left  (soc--cell ?│))
             (soc--set grid r right (soc--cell ?│)))))

(defun soc--draw-die (grid layout)
  "Draw the dashed inner-die rectangle when `soc-show-die-outline'."
  (when soc-show-die-outline
    (let* ((top   (+ (plist-get layout :chip-top)   3))
           (bot   (- (plist-get layout :chip-bot)   3))
           (left  (+ (plist-get layout :chip-left)  4))
           (right (- (plist-get layout :chip-right) 4))
           (face  'soc-die))
      (when (and (< (1+ top) bot) (< (1+ left) right))
        (soc--set grid top left  (soc--cell ?┌ 'face face))
        (soc--set grid top right (soc--cell ?┐ 'face face))
        (soc--set grid bot left  (soc--cell ?└ 'face face))
        (soc--set grid bot right (soc--cell ?┘ 'face face))
        (cl-loop for c from (1+ left) below right by 2 do
                 (soc--set grid top c (soc--cell ?┄ 'face face))
                 (soc--set grid bot c (soc--cell ?┄ 'face face)))
        (cl-loop for r from (1+ top) below bot by 2 do
                 (soc--set grid r left  (soc--cell ?┊ 'face face))
                 (soc--set grid r right (soc--cell ?┊ 'face face)))))))

(defun soc--draw-centre (grid layout pkg)
  "Draw centred :family / :core / :package text inside the chip body.
Each line uses a distinct face (`soc-chip-family' / -core / -package)."
  (let* ((mid-r (/ (+ (plist-get layout :chip-top)
                      (plist-get layout :chip-bot)) 2))
         (mid-c (/ (+ (plist-get layout :chip-left)
                      (plist-get layout :chip-right)) 2))
         (family (plist-get pkg :family))
         (entries (cl-remove
                   nil
                   (list (and family (cons (format " %s " family) 'soc-chip-family))
                         (and (plist-get pkg :core)
                              (cons (plist-get pkg :core) 'soc-chip-core))
                         (and (plist-get pkg :package)
                              (cons (plist-get pkg :package) 'soc-chip-package)))
                   :key #'car))
         (n     (length entries))
         (start (- mid-r (/ (1- n) 2))))
    (cl-loop for entry in entries
             for i from 0
             for text = (car entry)
             for face = (cdr entry)
             do (soc--write grid (+ start i)
                            (- mid-c (/ (length text) 2))
                            text 'face face))))

(defun soc--draw-tag (grid r c text face line-face direction)
  "Draw a chevron-tipped tag (`< name >' shape) for a side pin.
Body uses FACE (with background); chevrons use LINE-FACE
\(foreground-only) so they read as outward-pointing arrow tabs.
\(R, C) is the chip-facing chevron position.  DIRECTION is `right'
on the left side, `left' on the right side."
  (let ((len (length text)))
    (pcase direction
      (`right
       (soc--set grid r c (soc--cell ? 'face line-face))
       (soc--set grid r (- c 1) (soc--cell ?\s 'face face))
       (cl-loop for i below len do
                (soc--set grid r (- c 2 (- len 1 i))
                          (soc--cell (aref text i) 'face face)))
       (soc--set grid r (- c 2 len) (soc--cell ?\s 'face face))
       (soc--set grid r (- c 3 len) (soc--cell ? 'face line-face)))
      (`left
       (soc--set grid r c (soc--cell ? 'face line-face))
       (soc--set grid r (+ c 1) (soc--cell ?\s 'face face))
       (cl-loop for i below len do
                (soc--set grid r (+ c 2 i)
                          (soc--cell (aref text i) 'face face)))
       (soc--set grid r (+ c 2 len) (soc--cell ?\s 'face face))
       (soc--set grid r (+ c 3 len) (soc--cell ? 'face line-face))))))

(defun soc--draw-pin (grid layout side index pin)
  "Draw a left/right SIDE pin at slot INDEX into GRID."
  (let* ((chip-left  (plist-get layout :chip-left))
         (chip-right (plist-get layout :chip-right))
         (lead       soc-lead-length)
         (type       (plist-get pin :type))
         (name       (plist-get pin :name))
         (face       (soc--type-face type))
         (line-face  (soc--line-face type))
         (num-face   (soc--num-face type))
         (num-str    (format "%2d" (plist-get pin :n))))
    (pcase side
      (`left
       (let* ((row (soc--pin-row layout index))
              (col chip-left))
         (soc--set grid row col (soc--cell ?● 'face line-face))
         (cl-loop for i from 1 to lead do
                  (soc--set grid row (- col i) (soc--cell ?─ 'face line-face)))
         (soc--write grid row (+ col 2) num-str 'face num-face)
         (soc--draw-tag grid row (- col lead 1) name face line-face 'right)))
      (`right
       (let* ((row (soc--pin-row layout index))
              (col chip-right))
         (soc--set grid row col (soc--cell ?● 'face line-face))
         (cl-loop for i from 1 to lead do
                  (soc--set grid row (+ col i) (soc--cell ?─ 'face line-face)))
         (soc--write grid row (- col 3) num-str 'face num-face)
         (soc--draw-tag grid row (+ col lead 1) name face line-face 'left))))))


;;; ============================================================
;;; Staircase drawing (top / bottom sides)
;;; ============================================================

(defun soc--draw-top-staircase (grid layout pkg)
  "Draw top-side pins as a split-direction staircase.
Left half (indices < half-l) extends labels leftward from ┐
corners; right half extends labels rightward from ┌."
  (let* ((top-pins  (plist-get layout :top-pins))
         (n         (length top-pins))
         (half-l    (/ n 2))
         (chip-top  (plist-get layout :chip-top))
         (chip-left (plist-get layout :chip-left))
         (margin    soc-chip-margin)
         (pitch     (plist-get layout :pitch-h))
         (h-lead    1))
    (cl-loop
     for n-pin in top-pins
     for i from 0
     for pin = (soc--pin-plist pkg n-pin)
     when pin do
     (let* ((corner    (+ chip-left 1 margin (* i pitch)))
            (in-left   (< i half-l))
            (label-row (if in-left (- half-l 1 i) (- i half-l)))
            (type      (plist-get pin :type))
            (name      (plist-get pin :name))
            (face      (soc--type-face type))
            (line-face (soc--line-face type))
            (label     (concat " " name " "))
            (lab-len   (length label)))
       (if in-left
           (let* ((lab-end    (- corner h-lead 2))
                  (lab-start  (- lab-end lab-len -1))
                  (chev-far   (1- lab-start))
                  (chev-near  (1+ lab-end)))
             (soc--set grid label-row chev-far (soc--cell ? 'face line-face))
             (soc--write grid label-row lab-start label 'face face)
             (soc--set grid label-row chev-near (soc--cell ? 'face line-face))
             (cl-loop for c from (+ chev-near 1) below corner do
                      (soc--set grid label-row c (soc--cell ?─ 'face line-face)))
             (soc--set grid label-row corner (soc--cell ?┐ 'face line-face)))
         (let* ((chev-near (+ corner h-lead 1))
                (lab-start (+ chev-near 1))
                (lab-end   (+ lab-start lab-len -1))
                (chev-far  (1+ lab-end)))
           (soc--set grid label-row corner (soc--cell ?┌ 'face line-face))
           (cl-loop for c from (1+ corner) below chev-near do
                    (soc--set grid label-row c (soc--cell ?─ 'face line-face)))
           (soc--set grid label-row chev-near (soc--cell ? 'face line-face))
           (soc--write grid label-row lab-start label 'face face)
           (soc--set grid label-row chev-far (soc--cell ? 'face line-face))))
       (cl-loop for r from (1+ label-row) below chip-top do
                (soc--set grid r corner (soc--cell ?│ 'face line-face)))
       (soc--set grid chip-top corner (soc--cell ?● 'face line-face))
       (soc--write grid (1+ chip-top) corner
                   (format "%2d" (plist-get pin :n))
                   'face (soc--num-face type))))))

(defun soc--draw-bottom-staircase (grid layout pkg)
  "Draw bottom-side pins as a split-direction staircase (mirror of top)."
  (let* ((bot-pins  (plist-get layout :bottom-pins))
         (n         (length bot-pins))
         (half-l    (/ n 2))
         (chip-bot  (plist-get layout :chip-bot))
         (chip-left (plist-get layout :chip-left))
         (margin    soc-chip-margin)
         (pitch     (plist-get layout :pitch-h))
         (h-lead    1))
    (cl-loop
     for n-pin in bot-pins
     for i from 0
     for pin = (soc--pin-plist pkg n-pin)
     when pin do
     (let* ((corner    (+ chip-left 1 margin (* i pitch)))
            (in-left   (< i half-l))
            (label-row (+ chip-bot 1 (if in-left i (- n 1 i))))
            (type      (plist-get pin :type))
            (name      (plist-get pin :name))
            (face      (soc--type-face type))
            (line-face (soc--line-face type))
            (label     (concat " " name " "))
            (lab-len   (length label)))
       (cl-loop for r from (1+ chip-bot) below label-row do
                (soc--set grid r corner (soc--cell ?│ 'face line-face)))
       (if in-left
           (let* ((lab-end   (- corner h-lead 2))
                  (lab-start (- lab-end lab-len -1))
                  (chev-far  (1- lab-start))
                  (chev-near (1+ lab-end)))
             (soc--set grid label-row corner (soc--cell ?┘ 'face line-face))
             (cl-loop for c from (+ chev-near 1) below corner do
                      (soc--set grid label-row c (soc--cell ?─ 'face line-face)))
             (soc--set grid label-row chev-near (soc--cell ? 'face line-face))
             (soc--write grid label-row lab-start label 'face face)
             (soc--set grid label-row chev-far (soc--cell ? 'face line-face)))
         (let* ((chev-near (+ corner h-lead 1))
                (lab-start (+ chev-near 1))
                (lab-end   (+ lab-start lab-len -1))
                (chev-far  (1+ lab-end)))
           (soc--set grid label-row corner (soc--cell ?└ 'face line-face))
           (cl-loop for c from (1+ corner) below chev-near do
                    (soc--set grid label-row c (soc--cell ?─ 'face line-face)))
           (soc--set grid label-row chev-near (soc--cell ? 'face line-face))
           (soc--write grid label-row lab-start label 'face face)
           (soc--set grid label-row chev-far (soc--cell ? 'face line-face))))
       (soc--set grid chip-bot corner (soc--cell ?● 'face line-face))
       (soc--write grid (1- chip-bot) corner
                   (format "%2d" (plist-get pin :n))
                   'face (soc--num-face type))))))


;;; ============================================================
;;; Layout
;;; ============================================================

(defun soc--pin-plist (pkg n)
  "Return a `(:n N :name STR :type SYM)' plist for pin N in PKG, or nil."
  (when-let* ((rest (alist-get n (plist-get pkg :pins))))
    `(:n ,n ,@rest)))

(defun soc--side-name-widths (pkg pin-numbers)
  "List of label lengths for PIN-NUMBERS resolved against PKG."
  (mapcar (lambda (n)
            (length (or (plist-get (soc--pin-plist pkg n) :name) "")))
          pin-numbers))

(defun soc--pin-row (layout i)
  "Row for left/right side pin index I in LAYOUT."
  (+ (plist-get layout :chip-top) 1 soc-chip-margin
     (* i (plist-get layout :pitch-v))))

(defun soc--compute-layout (pkg)
  "Compute the chip + canvas layout for PKG.
Returns a plist used by every draw pass."
  (let* ((sides    (plist-get pkg :sides))
         (left     (alist-get 'left   sides))
         (right    (alist-get 'right  sides))
         (top      (alist-get 'top    sides))
         (bottom   (alist-get 'bottom sides))
         (margin   soc-chip-margin)
         (lead     soc-lead-length)
         (extra    4)
         (n-left   (length left))
         (n-right  (length right))
         (n-top    (length top))
         (n-bot    (length bottom))
         (max-l    (apply #'max 0 (soc--side-name-widths pkg left)))
         (max-r    (apply #'max 0 (soc--side-name-widths pkg right)))
         (n-v      (max n-left n-right))
         (pitch-h  soc-pin-pitch-horizontal)
         (chip-w   (+ 2 (* 2 margin)
                      (* (max 0 (1- (max n-top n-bot))) pitch-h)))
         (target-h (/ (float chip-w) (max 0.1 soc-font-aspect-ratio)))
         (pitch-v  (max soc-pin-pitch-vertical
                        (max 1 (round (/ (- target-h 2 (* 2 margin))
                                         (float (max 1 (1- n-v))))))))
         (chip-h   (+ 2 (* 2 margin) (* (max 0 (1- n-v)) pitch-v)))
         (region-l (+ max-l extra lead))
         (region-r (+ max-r extra lead))
         (region-t (/ (1+ n-top) 2))
         (region-b (/ (1+ n-bot) 2))
         (canvas-w (+ region-l chip-w region-r))
         (canvas-h (+ region-t chip-h region-b))
         (chip-top   region-t)
         (chip-bot   (+ chip-top chip-h -1))
         (chip-left  region-l)
         (chip-right (+ chip-left chip-w -1)))
    (list :chip-top    chip-top
          :chip-bot    chip-bot
          :chip-left   chip-left
          :chip-right  chip-right
          :chip-w      chip-w
          :chip-h      chip-h
          :canvas-w    canvas-w
          :canvas-h    canvas-h
          :pitch-h     pitch-h
          :pitch-v     pitch-v
          :left-pins   left
          :right-pins  right
          :top-pins    top
          :bottom-pins bottom)))

(defun soc--side-pins (layout side)
  "Pin-number list for SIDE in LAYOUT."
  (pcase side
    (`left   (plist-get layout :left-pins))
    (`right  (plist-get layout :right-pins))
    (`top    (plist-get layout :top-pins))
    (`bottom (plist-get layout :bottom-pins))))

(defun soc--draw-side (grid layout pkg side)
  "Dispatch drawing for SIDE.
Left/right use `soc--draw-pin' per pin; top/bottom use the
split-direction staircase drawers."
  (pcase side
    ((or `left `right)
     (cl-loop for n in (soc--side-pins layout side)
              for i from 0
              for pin = (soc--pin-plist pkg n)
              when pin do (soc--draw-pin grid layout side i pin)))
    (`top    (soc--draw-top-staircase    grid layout pkg))
    (`bottom (soc--draw-bottom-staircase grid layout pkg))))


;;; ============================================================
;;; Rendering
;;; ============================================================

(defvar-local soc--current-package nil
  "Symbol identifying the package shown in this buffer.")

(defvar-local soc--face-remap-cookie nil
  "Cookie from `face-remap-add-relative' for default-face scaling.")

(defun soc--fit-height (cols rows)
  "Pick a font scale that fits a COLS×ROWS canvas in the current window.
Capped by `soc-font-height'."
  (let* ((char-w (or (window-font-width  nil 'default) (frame-char-width)))
         (char-h (or (window-font-height nil 'default) (frame-char-height)))
         (win-w  (window-body-width  nil t))
         (win-h  (window-body-height nil t))
         (fit-w  (/ (float win-w) (* char-w (max 1 cols))))
         (fit-h  (/ (float win-h) (* char-h (max 1 rows))))
         (pref   (or soc-font-height 1.0)))
    (max 0.3 (min pref (* 0.98 (min fit-w fit-h))))))

(defun soc--apply-face-remap (height)
  "Apply font HEIGHT (and `soc-font-family' if set) via face remap.
Removes any prior remap on this buffer first."
  (when soc--face-remap-cookie
    (face-remap-remove-relative soc--face-remap-cookie)
    (setq soc--face-remap-cookie nil))
  (let (spec)
    (when soc-font-family
      (setq spec (append spec (list :family soc-font-family))))
    (when (and (numberp height) (/= height 1.0))
      (setq spec (append spec (list :height height))))
    (when spec
      (setq soc--face-remap-cookie
            (apply #'face-remap-add-relative 'default spec)))))

(defun soc--render (pkg)
  "Render PKG into the current buffer."
  (let* ((layout   (soc--compute-layout pkg))
         (canvas-w (plist-get layout :canvas-w))
         (canvas-h (plist-get layout :canvas-h))
         (grid     (soc--grid canvas-h canvas-w)))
    (soc--apply-face-remap (soc--fit-height canvas-w canvas-h))
    (let ((top-pad (max 0 (/ (- (window-body-height) canvas-h) 2))))
      (dotimes (_ top-pad) (insert "\n")))
    (soc--draw-chip-body grid layout)
    (soc--draw-die       grid layout)
    (soc--draw-centre    grid layout pkg)
    (dolist (side '(left right top bottom))
      (soc--draw-side grid layout pkg side))
    (let* ((window-cols (window-text-width))
           (left-pad    (max 0 (/ (- window-cols canvas-w) 2))))
      (soc--flush grid left-pad))))


;;; ============================================================
;;; Major mode
;;; ============================================================

(defvar soc-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    map)
  "Keymap for `soc-mode'.  Inherits `special-mode-map' (`g' reverts).")

(define-derived-mode soc-mode special-mode "SoC"
  "Major mode for displaying SoC top-view package diagrams.
\\<soc-mode-map>`\\[revert-buffer]' re-renders for the current
window width."
  (buffer-disable-undo)
  (setq-local truncate-lines               t
              tab-width                    1
              cursor-type                  nil
              cursor-in-non-selected-windows nil
              show-trailing-whitespace     nil
              indicate-empty-lines         nil
              revert-buffer-function
              (lambda (&rest _)
                (when-let* ((key  soc--current-package)
                            (data (alist-get key soc-packages)))
                  (with-silent-modifications
                    (erase-buffer)
                    (soc--render data)
                    (goto-char (point-min)))
                  (set-buffer-modified-p t))))
  (font-lock-mode -1))


;;; ============================================================
;;; Reload-and-reset
;;; ============================================================

(defun soc--reload-and-reset ()
  "Reload `soc.el' from disk and reset every defcustom.
Without this, edits to soc.el don't take effect until Emacs
restart.  Called from the `soc' entry point so the workflow is
edit → save → \\[soc]."
  (let ((file (or (and buffer-file-name
                       (string-match-p (rx "/soc.el" eos) buffer-file-name)
                       buffer-file-name)
                  (locate-library "soc"))))
    (when file (load file nil 'nomessage)))
  (dolist (sym '(soc-default-package soc-pin-pitch-horizontal
                 soc-pin-pitch-vertical soc-font-aspect-ratio
                 soc-chip-margin soc-lead-length soc-show-die-outline
                 soc-font-family soc-font-height soc-type-faces
                 soc-packages soc-overlays))
    (custom-reevaluate-setting sym)))


;;; ============================================================
;;; Entry point
;;; ============================================================

;;;###autoload
(defun soc (&optional package)
  "Display the SoC package diagram for PACKAGE.
With no argument or with a prefix arg, picks interactively from
`soc-packages'."
  (interactive
   (list (if (or current-prefix-arg (null soc-default-package))
             (completing-read "SoC package: "
                              (mapcar (lambda (e) (symbol-name (car e)))
                                      soc-packages)
                              nil t)
           soc-default-package)))
  (soc--reload-and-reset)
  (let* ((key (intern package))
         (pkg (alist-get key soc-packages)))
    (unless pkg (user-error "Unknown SoC package: %s" package))
    (let ((buffer (get-buffer-create (format "*soc:%s*" package))))
      (switch-to-buffer buffer)
      (with-silent-modifications
        (erase-buffer)
        (unless (derived-mode-p 'soc-mode) (soc-mode))
        (setq soc--current-package key)
        (soc--render pkg)
        (goto-char (point-min)))
      ;; Doom-modeline colours modified buffer names yellow; flag it
      ;; so soc buffers match the same convention pinout uses.
      (set-buffer-modified-p t))))

(unless read-extended-command-predicate
  (setq read-extended-command-predicate #'command-completion-default-include-p))

(put 'soc-mode 'completion-predicate #'ignore)

;; Doom users: wire `M-x soc' to a leader binding yourself, e.g.
;;   (map! :leader "p s" #'soc)
;; Not bundled here to avoid clashing with existing prefixes.

(provide 'soc)
;;; soc.el ends here
