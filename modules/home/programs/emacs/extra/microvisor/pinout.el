;;; pinout.el --- Pretty board-pin diagrams for embedded dev -*- lexical-binding: t; -*-

;; Author: Mumtahin Farabi <farabi@apidaesystems.ca>
;; Keywords: tools, embedded, hardware
;; URL: https://github.com/MFarabi619/pinout.el
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; Standalone Emacs package that draws colored ASCII pinout diagrams
;; for embedded development boards.  Pin labels are clickable
;; text-property buttons; each segment is color-coded by inferred role
;; (power / ground / gpio / adc / i2c / spi / uart / pin-name / system
;; / peripheral).
;;
;; Architecture: rectangle-first.  Each board describes its pins by
;; SIDE (left, right, top, bottom).  The renderer computes the chip's
;; rectangle bounds once, builds an in-memory char grid, draws the
;; rectangle + USB connector + each side's pins as independent passes,
;; and flushes the grid into the buffer at the end.  Clickable buttons
;; are applied after flush using deterministic grid-to-buffer position
;; math.
;;
;; Entry point: `M-x pinout'.  Doom users get `SPC p n' for free.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'treesit)
(require 'text-property-search)
(require 'face-remap)

(declare-function consult--read "consult" (table &rest options))

(defvar pinout--chip-overlays)
(defvar pinout--current-board)
(defvar pinout--show-legend)

(defgroup pinout nil
  "Board pinout visualizer."
  :group 'tools
  :prefix "pinout-")

;;; ============================================================
;;; defcustoms
;;; ============================================================

(defcustom pinout-box-width 51
  "Width (in columns) of the chip body in the pinout diagram.
Includes both side walls; must be odd so the `┴' / `●' markers center."
  :type 'natnum
  :group 'pinout)

(defcustom pinout-row-spacing 4
  "Extra blank lines inserted between pin rows.
0 produces the compact single-row layout; 1+ gives breathing room."
  :type 'natnum
  :group 'pinout)

(defcustom pinout-pin-lead-length 2
  "Length (in columns) of the `─' lead between a pin label and the chip body."
  :type 'natnum
  :group 'pinout)

(defcustom pinout-label-padding 1
  "Number of space characters padding each pin-label segment.
The padding is rendered with the same colored background as the
segment text, so it visually thickens each colored chip."
  :type 'natnum
  :group 'pinout)

(defcustom pinout-font-family nil
  "Font family to use in pinout buffers.
Set to a font that draws `─' as a continuous line (Iosevka, Fira
Code, JetBrains Mono, Hack) to eliminate gaps between box-drawing
characters.  Remapped buffer-locally."
  :type '(choice (const :tag "Default font" nil) (string :tag "Font family"))
  :group 'pinout)

(defcustom pinout-font-height 2.0
  "Maximum scale factor for the default face height in pinout buffers.
Auto-fit picks the largest scale that fits the diagram in both axes
and caps at this value.  Use `C-x C-=' / `C-x C--' in the buffer for
live zoom adjustments on top of the computed base scale."
  :type 'number
  :group 'pinout)

(defcustom pinout-font-height-min 0.6
  "Lower bound on the auto-fit scale.
Prevents pinout from shrinking to unreadable sizes in tiny windows."
  :type 'number
  :group 'pinout)

(defcustom pinout-fit-margin 0.80
  "Fraction of the window the auto-fit scale should target.
Lower values leave more breathing room around the diagram; higher
values pack tighter.  0.90 nearly fills the window; 0.80 leaves a
visible margin on all four sides."
  :type 'number
  :group 'pinout)

(defcustom pinout-default-board "xiao_esp32s3"
  "Board key used when `pinout' is called without a prefix arg."
  :type 'string
  :group 'pinout)

(defcustom pinout-show-legend t
  "Whether the role legend appears below the diagram by default.
Toggle live in a pinout buffer with `pinout-toggle-legend' (bound to
`SPC p h' in Doom)."
  :type 'boolean
  :group 'pinout)

(defcustom pinout-board-info-format "%vendor %full_name"
  "Format string for the board info message shown by `pinout'.
`%<key>' tokens are replaced with values parsed from the active
board's `board.yml'."
  :type 'string
  :group 'pinout)

(defcustom pinout-boards
  '((xiao_esp32s3
     :name   "XIAO ESP32-S3"
     :vendor "seeed"
     :usb    (:type usb-c :side top :offset center)
     :sides
     ((left
       (:n 1 :primary "D0" :aliases ("ADC1/A0" "GPIO1" "RTC") :pwm t :touch t)
       (:n 2 :primary "D1" :aliases ("ADC1/A1" "GPIO2" "RTC") :pwm t :touch t)
       (:n 3 :primary "D2" :aliases ("ADC1/A2" "GPIO3" "RTC") :pwm t :touch t)
       (:n 4 :primary "D3" :aliases ("ADC1/A3" "GPIO4" "RTC") :pwm t :touch t)
       (:n 5 :primary "D4" :aliases ("ADC1/A4" "GPIO5" "SDA1" "RTC") :pwm t :touch t)
       (:n 6 :primary "D5" :aliases ("ADC1/A5" "GPIO6" "SCL1" "RTC") :pwm t :touch t)
       (:n 7 :primary "D6" :aliases ("GPIO43" "TX0") :pwm t))
      (right
       (:n 14 :primary "VBUS")
       (:n 13 :primary "GND")
       (:n 12 :primary "3.3V-OUT")
       (:n 11 :primary "D10" :aliases ("ADC1/A10" "GPIO9" "MOSI0" "RTC") :pwm t :touch t)
       (:n 10 :primary "D9"  :aliases ("ADC1/A9"  "GPIO8" "MISO0" "RTC") :pwm t :touch t)
       (:n 9  :primary "D8"  :aliases ("ADC1/A8"  "GPIO7" "SCK0"  "RTC") :pwm t :touch t)
       (:n 8  :primary "D7"  :aliases ("GPIO44"   "RX0") :pwm t))))
    (esp32s3_devkitc1
     :name   "ESP32-S3-DevKitC-1"
     :vendor "espressif"
     :row-spacing 1
     :usb    (:type usb-micro :side bottom :offset center)
     :sides
     ((left
       (:n 1  :primary "3V3")
       (:n 2  :primary "3V3")
       (:n 3  :primary "RST")
       (:n 4  :primary "GPIO4"  :aliases ("ADC1_3" "RTC") :pwm t :touch t)
       (:n 5  :primary "GPIO5"  :aliases ("ADC1_4" "RTC") :pwm t :touch t)
       (:n 6  :primary "GPIO6"  :aliases ("ADC1_5" "RTC") :pwm t :touch t)
       (:n 7  :primary "GPIO7"  :aliases ("ADC1_6" "RTC") :pwm t :touch t)
       (:n 8  :primary "GPIO15" :aliases ("ADC2_4" "RTC") :pwm t)
       (:n 9  :primary "GPIO16" :aliases ("ADC2_5" "RTC") :pwm t)
       (:n 10 :primary "GPIO17" :aliases ("ADC2_6" "RTC") :pwm t)
       (:n 11 :primary "GPIO18" :aliases ("ADC2_7" "RTC") :pwm t)
       (:n 12 :primary "GPIO8"  :aliases ("ADC1_7" "RTC") :pwm t :touch t)
       (:n 13 :primary "GPIO3"  :aliases ("ADC1_2" "RTC") :pwm t :touch t)
       (:n 14 :primary "GPIO46" :pwm t)
       (:n 15 :primary "GPIO9"  :aliases ("ADC1_8" "RTC") :pwm t :touch t)
       (:n 16 :primary "GPIO10" :aliases ("ADC1_9" "RTC") :pwm t :touch t)
       (:n 17 :primary "GPIO11" :aliases ("ADC2_0" "RTC") :pwm t :touch t)
       (:n 18 :primary "GPIO12" :aliases ("ADC2_1" "RTC") :pwm t :touch t)
       (:n 19 :primary "GPIO13" :aliases ("ADC2_2" "RTC") :pwm t :touch t)
       (:n 20 :primary "GPIO14" :aliases ("ADC2_3" "RTC") :pwm t :touch t)
       (:n 21 :primary "5V0")
       (:n 22 :primary "GND"))
      (right
       (:n 43 :primary "GND")
       (:n 42 :primary "GPIO43" :aliases ("U0TXD")                  :pwm t)
       (:n 41 :primary "GPIO44" :aliases ("U0RXD")                  :pwm t)
       (:n 40 :primary "GPIO1"  :aliases ("ADC1_0" "RTC") :pwm t :touch t)
       (:n 39 :primary "GPIO2"  :aliases ("ADC1_1" "RTC") :pwm t :touch t)
       (:n 38 :primary "GPIO42" :pwm t)
       (:n 37 :primary "GPIO41" :pwm t)
       (:n 36 :primary "GPIO40" :pwm t)
       (:n 35 :primary "GPIO39" :pwm t)
       (:n 34 :primary "GPIO38" :pwm t)
       (:n 33 :primary "GPIO37" :pwm t)
       (:n 32 :primary "GPIO36" :pwm t)
       (:n 31 :primary "GPIO35" :pwm t)
       (:n 30 :primary "GPIO0"  :pwm t)
       (:n 29 :primary "GPIO45" :pwm t)
       (:n 28 :primary "GPIO48" :pwm t)
       (:n 27 :primary "GPIO47" :pwm t)
       (:n 26 :primary "GPIO21" :aliases ("RTC")                    :pwm t)
       (:n 25 :primary "GPIO20" :aliases ("ADC2_9" "RTC")           :pwm t)
       (:n 24 :primary "GPIO19" :aliases ("ADC2_8" "RTC")           :pwm t)
       (:n 23 :primary "GND")))))
  "Board pinout definitions, keyed by board name.
Each entry is (KEY . PLIST).  PLIST keys:
  :name        -- human display name
  :vendor      -- vendor directory under `zephyr/boards/'
  :row-spacing -- optional override for `pinout-row-spacing' (per-board);
                  useful for dense boards where the global default
                  would produce an excessively tall diagram
  :usb         -- connector spec
                  (:type SYM :side top|bottom|left|right
                   :offset center|start|end)
  :sides       -- alist mapping side symbol to list of pin plists
                  (:n NUM :primary STR :aliases (STR ...)
                   :pwm BOOL :touch BOOL)"
  :type 'sexp
  :group 'pinout)

;;; ============================================================
;;; Faces and palette
;;; ============================================================

(defface pinout-power           '((t :background "#e57373" :foreground "#1d2021" :weight bold)) "POWER face.")
(defface pinout-ground          '((t :background "#000000" :foreground "#1d2021" :weight bold)) "GND face.")
(defface pinout-gpio            '((t :background "#9ccc65" :foreground "#1d2021" :weight bold)) "DIGITAL face.")
(defface pinout-pin-name        '((t :background "#a87858" :foreground "#1d2021" :weight bold)) "PIN NAME face.")
(defface pinout-adc             '((t :background "#ff9800" :foreground "#1d2021" :weight bold)) "ADC INPUT face.")
(defface pinout-i2c             '((t :background "#fabd2f" :foreground "#1d2021" :weight bold)) "I²C face.")
(defface pinout-spi             '((t :background "#ba68c8" :foreground "#1d2021" :weight bold)) "SPI face.")
(defface pinout-uart            '((t :background "#26a69a" :foreground "#1d2021" :weight bold)) "UART face.")
(defface pinout-system          '((t :background "#8896a0" :foreground "#1d2021" :weight bold)) "SYSTEM face.")
(defface pinout-peripheral      '((t :background "#34495e" :foreground "#1d2021" :weight bold)) "PERIPHERAL face.")
(defface pinout-usb             '((t :background "#3c3836" :foreground "#ebdbb2" :weight bold)) "USB connector pill face.")

(defface pinout-legend-system      '((t :inherit pinout-system))      "Legend: SYSTEM.")
(defface pinout-legend-power       '((t :inherit pinout-power))       "Legend: POWER.")
(defface pinout-legend-ground      '((t :inherit pinout-ground))      "Legend: GND.")
(defface pinout-legend-gpio        '((t :inherit pinout-gpio))        "Legend: DIGITAL.")
(defface pinout-legend-adc         '((t :inherit pinout-adc))         "Legend: ADC INPUT.")
(defface pinout-legend-pinname     '((t :inherit pinout-pin-name))    "Legend: PIN NAME.")
(defface pinout-legend-spi         '((t :inherit pinout-spi))         "Legend: SPI.")
(defface pinout-legend-uart        '((t :inherit pinout-uart))        "Legend: UART.")
(defface pinout-legend-i2c         '((t :inherit pinout-i2c))         "Legend: I²C.")
(defface pinout-legend-peripheral  '((t :inherit pinout-peripheral))  "Legend: PERIPHERAL.")

(defface pinout-edge-power      '((t :foreground "#e74c3c")) "POWER edge glyph face.")
(defface pinout-edge-ground     '((t :foreground "#000000")) "GND edge glyph face.")
(defface pinout-edge-gpio       '((t :foreground "#9ccc65")) "DIGITAL edge glyph face.")
(defface pinout-edge-pin-name   '((t :foreground "#a87858")) "PIN NAME edge glyph face.")
(defface pinout-edge-adc        '((t :foreground "#ff9800")) "ADC INPUT edge glyph face.")
(defface pinout-edge-i2c        '((t :foreground "#fabd2f")) "I²C edge glyph face.")
(defface pinout-edge-spi        '((t :foreground "#ba68c8")) "SPI edge glyph face.")
(defface pinout-edge-uart       '((t :foreground "#26a69a")) "UART edge glyph face.")
(defface pinout-edge-system     '((t :foreground "#8896a0")) "SYSTEM edge glyph face.")
(defface pinout-edge-peripheral '((t :foreground "#34495e")) "PERIPHERAL edge glyph face.")

(defface pinout-hover           '((t :background "#fabd2f" :foreground "#1d2021" :weight bold))
  "Mouse-hover face for pin segment BODY cells.  Yellow background +
dark foreground.  Used by the per-chip overlay applied to all cells.")

(defface pinout-edge-hover      '((t :foreground "#fabd2f" :weight bold))
  "Mouse-hover face for pin segment EDGE cells (the `◥' and `◣' triangle
glyphs).  Yellow foreground only — no background — so the triangle
glyph reads as the OUTER extension of the yellow body parallelogram
rather than as a yellow cell with a dark glyph inside.")

(defconst pinout--face-sources
  '((pinout-power            nil                 "#e57373")
    (pinout-ground           nerd-icons-dsilver  "#000000")
    (pinout-gpio             nil                 "#9ccc65")
    (pinout-pin-name         nerd-icons-dmaroon  "#a87858")
    (pinout-adc              nerd-icons-orange   "#ff9800")
    (pinout-i2c              nerd-icons-yellow   "#fabd2f")
    (pinout-spi              nerd-icons-purple   "#ba68c8")
    (pinout-uart             nerd-icons-dcyan    "#26a69a")
    (pinout-system           nerd-icons-silver   "#8896a0")
    (pinout-peripheral       nerd-icons-dblue    "#34495e"))
  "Map of pinout face → (source-face . fallback-hex).")

(defconst pinout--legend-items
  '(("SYSTEM"       . pinout-legend-system)
    ("POWER"        . pinout-legend-power)
    ("GND"          . pinout-legend-ground)
    ("DIGITAL"      . pinout-legend-gpio)
    ("ADC INPUT"    . pinout-legend-adc)
    ("PIN NAME"     . pinout-legend-pinname)
    ("SPI"          . pinout-legend-spi)
    ("UART"         . pinout-legend-uart)
    ("I2C"          . pinout-legend-i2c)
    ("PERIPHERAL"   . pinout-legend-peripheral))
  "Boxes shown in the legend strip, in display order.")

(defun pinout--resolve-bg (entry)
  "Resolve ENTRY's background: nerd-icons fg if real, else fallback."
  (let* ((source (nth 1 entry))
         (fg     (and (facep source) (face-attribute source :foreground nil t))))
    (if (and (stringp fg) (not (string-prefix-p "unspecified" fg)))
        fg
      (nth 2 entry))))

(defun pinout--apply-theme-colors ()
  "Sweep the role faces.  First reset each face from its `defface'
spec via `face-spec-set' (so stale overrides from previous loads don't
stick), then override `:background' with the resolved nerd-icons color.
The matching `pinout-edge-*' face's `:foreground' is synced to the
same resolved color so the slanted triangle glyphs (◥/◣) draw in
the same role color."
  (dolist (entry pinout--face-sources)
    (let* ((face       (car entry))
           (color      (pinout--resolve-bg entry))
           (edge-face  (intern (format "pinout-edge-%s"
                                       (string-remove-prefix
                                         "pinout-" (symbol-name face))))))
      (face-spec-set face (face-default-spec face) 'face-defface-spec)
      (set-face-attribute face nil
                          :background color
                          :underline  nil)
      (when (facep edge-face)
        (face-spec-set edge-face (face-default-spec edge-face) 'face-defface-spec)
        (set-face-attribute edge-face nil :foreground color)))))

(pinout--apply-theme-colors)

;; Re-resolve role and edge face colors whenever the user enables a
;; new theme — the resolved colors come from `nerd-icons-*' faces, so
;; a theme change without this hook would leave them stale (chips and
;; the triangle edges would render with the previous theme's palette).
(add-hook 'enable-theme-functions
  (lambda (&rest _) (pinout--apply-theme-colors)))

;;; ============================================================
;;; Segment role inference
;;; ============================================================

(defun pinout--segment-role (segment)
  "Infer role symbol for pin SEGMENT name."
  (cond
   ((member segment '("5V" "5V0" "3V3" "VDD" "VCC" "VBUS" "3.3V-OUT"))                                  'power)
   ((member segment '("GND" "VSS"))                                                                    'ground)
   ((member segment '("RTC" "RST"))                                                                    'system)
   ((string-match-p (rx bos "I2C"  digit "_")                                                segment) 'i2c)
   ((string-match-p (rx bos "SPI"  digit "_")                                                segment) 'spi)
   ((string-match-p (rx bos "UART" digit "_")                                                segment) 'uart)
   ((string-match-p (rx bos "ADC"  digit (or "/A" "_") (+ digit) eos)                        segment) 'adc)
   ((string-match-p (rx bos (or "SDA" "SCL") (* digit) eos)                                  segment) 'i2c)
   ((string-match-p (rx bos (or "MOSI" "MISO" "SCK" "CS" "SS") (* digit) eos)                segment) 'spi)
   ((string-match-p (rx bos (or "TX" "RX" "RTS" "CTS") (* digit) eos)                        segment) 'uart)
   ((string-match-p (rx bos "U" digit (or "TXD" "RXD" "RTS" "CTS") eos)                      segment) 'uart)
   ((string-match-p (rx bos "TOUCH" (+ digit) eos)                                           segment) 'pin-name)
   ((string-match-p (rx bos "A"    (+ digit) eos)                                            segment) 'adc)
   ((string-match-p (rx bos "D"    (+ digit) eos)                                            segment) 'gpio)
   ((string-match-p (rx bos "GPIO" (+ digit) eos)                                            segment) 'pin-name)
   (t                                                                                                  'gpio)))

(defun pinout--role-face (role)
  "Face symbol for ROLE."
  (intern (format "pinout-%s" role)))

(defun pinout--reorder-rtc-next-to-gpio (segments)
  "Return SEGMENTS with `RTC' moved to immediately follow the pin-name
segment (`GPIO[0-9]+').  If either is absent or RTC is already there,
return SEGMENTS unchanged."
  (let ((rtc-pos  (cl-position "RTC" segments :test #'string=))
        (gpio-pos (cl-position-if
                   (lambda (s) (string-match-p (rx bos "GPIO" (+ digit) eos) s))
                   segments)))
    (if (and rtc-pos gpio-pos (/= rtc-pos (1+ gpio-pos)))
        (let* ((without-rtc (cl-remove "RTC" segments :test #'string=))
               (new-gpio    (cl-position-if
                             (lambda (s) (string-match-p (rx bos "GPIO" (+ digit) eos) s))
                             without-rtc)))
          (append (cl-subseq without-rtc 0 (1+ new-gpio))
                  '("RTC")
                  (cl-subseq without-rtc (1+ new-gpio))))
      segments)))

(defun pinout--pin-display-segments (pin &optional side)
  "Return (SEGMENT . ROLE) pairs for PIN in left-to-right display order.
Aliases are stored inside-out from `:primary'; SIDE = `left' reverses.
`RTC' is always positioned adjacent to the pin-name segment."
  (let* ((primary (plist-get pin :primary))
         (aliases (plist-get pin :aliases))
         (visible (if (string-match-p (rx bos "D" (+ digit) eos) primary)
                      aliases
                    (cons primary aliases)))
         (reordered (pinout--reorder-rtc-next-to-gpio visible))
         (ordered   (if (eq side 'left) (reverse reordered) reordered)))
    (mapcar (lambda (s) (cons s (pinout--segment-role s))) ordered)))

(defun pinout--pin-display-width (pin)
  "Width in columns of PIN's rendered label strip.
Each segment is `◥[pad][text][pad]◣' — a triangle-edged parallelogram."
  (let ((pad-w (* 2 pinout-label-padding)))
    (cl-loop for (text . _) in (pinout--pin-display-segments pin)
             sum (+ (length text) pad-w 2))))

(defun pinout--role-color (role)
  "Background color for ROLE's chip face.  Used by both the pin
number tint and the slanted edge glyphs."
  (let ((val (face-attribute (pinout--role-face role) :background nil t)))
    (and (stringp val) (not (string-prefix-p "unspecified" val)) val)))

(defun pinout--pin-number-color (pin)
  "Color used to tint the pin number, taken from PIN's primary role."
  (pinout--role-color (pinout--segment-role (plist-get pin :primary))))

;;; ============================================================
;;; Grid data type
;;;
;;; A grid is a vector of rows; each row is a vector of cells.  A cell
;;; is nil (renders as space) or (CHAR . PROPS-PLIST).  Drawing
;;; functions mutate the grid by setting cells; the flush converts the
;;; grid into a single buffer write and returns the start position so
;;; callers can derive buffer positions for any (row, col).
;;; ============================================================

(defun pinout--grid-make (rows cols)
  "Make a fresh ROWS×COLS grid."
  (let ((grid (make-vector rows nil)))
    (dotimes (i rows)
      (aset grid i (make-vector cols nil)))
    grid))

(defun pinout--cell (char &rest props)
  "Cell of CHAR with text PROPS plist."
  (cons char props))

(defun pinout--grid-set (grid row col cell)
  "Set GRID[ROW][COL] = CELL."
  (when (and (>= row 0) (< row (length grid))
             (>= col 0) (< col (length (aref grid 0))))
    (aset (aref grid row) col cell)))

(defun pinout--grid-place (grid row col text &optional face)
  "Place TEXT into GRID starting at (ROW, COL).  Optional FACE on every char."
  (cl-loop for ch across text
           for i from 0 do
           (pinout--grid-set grid row (+ col i)
                             (apply #'pinout--cell ch (when face (list 'face face))))))

(defun pinout--grid-flush (grid left-pad)
  "Insert GRID into the current buffer, prefixing each row with LEFT-PAD spaces.
Returns an origin plist (:start :cols :left-pad) for `pinout--grid-buffer-pos'."
  (let ((start   (point))
        (cols    (length (aref grid 0)))
        (pad-str (make-string left-pad ?\s)))
    (cl-loop for row across grid do
             (insert pad-str)
             (cl-loop for cell across row do
                      (cond
                       ((null cell) (insert ?\s))
                       ((consp cell)
                        (insert (apply #'propertize
                                       (char-to-string (car cell)) (cdr cell))))
                       (t (insert cell))))
             (insert ?\n))
    (list :start start :cols cols :left-pad left-pad)))

(defun pinout--grid-buffer-pos (origin row col)
  "Map grid (ROW, COL) to a buffer position given ORIGIN plist."
  (let ((start (plist-get origin :start))
        (cols  (plist-get origin :cols))
        (lpad  (plist-get origin :left-pad)))
    (+ start (* row (+ lpad cols 1)) lpad col)))

;;; ============================================================
;;; Rectangle: bounds + per-pin row assignments
;;; ============================================================

(defun pinout--side-pins (board side)
  "Get pin list for BOARD's SIDE (a symbol)."
  (alist-get side (plist-get board :sides)))

(defun pinout--legend-width ()
  "Total horizontal width of the legend strip in columns."
  (let ((n (length pinout--legend-items)))
    (+ (cl-loop for (label . _) in pinout--legend-items
                sum (+ 2 (length label)))
       (* 2 (max 0 (1- n))))))

(defun pinout--compute-rect (board)
  "Compute the chip rect + canvas layout for BOARD.
Returns a plist with rectangle bounds (absolute char coords on the
canvas), per-pin row assignments, and total canvas dimensions."
  (let* ((left-pins   (pinout--side-pins board 'left))
         (right-pins  (pinout--side-pins board 'right))
         (left-max    (cl-loop for pin in left-pins  maximize
                               (+ (pinout--pin-display-width pin)
                                  (if (plist-get pin :touch) 1 0))))
         (right-max   (cl-loop for pin in right-pins maximize
                               (+ (pinout--pin-display-width pin)
                                  (if (plist-get pin :touch) 1 0))))
         (lead        pinout-pin-lead-length)
         (chip-w      (max 11 pinout-box-width))
         (max-pins    (max (length left-pins) (length right-pins)))
         (gap         (max 0 (or (plist-get board :row-spacing)
                                 pinout-row-spacing)))
         (chip-h      (+ 2 max-pins (* (max 0 (1- max-pins)) gap)))
         ;; Vertical layout: USB label, chip rows, board name, blank, legend.
         (usb-row     0)
         (chip-top    1)
         (chip-bot    (+ chip-top chip-h -1))
         (show-legend (and (boundp 'pinout--show-legend) pinout--show-legend))
         (legend-row  (if show-legend (+ chip-bot 2) (+ chip-bot 1)))
         (canvas-h    (+ legend-row 1))
         ;; Horizontal layout: left-labels | lead | chip | lead | right-labels.
         ;; When the legend is visible the canvas must accommodate it
         ;; (centered with the diagram via h-offset).  Hidden legend
         ;; drops the canvas width back to the diagram-only width.
         (diagram-w   (+ left-max lead chip-w lead right-max))
         (legend-w    (if show-legend (pinout--legend-width) 0))
         (canvas-w    (max diagram-w legend-w))
         (h-offset    (/ (- canvas-w diagram-w) 2))
         (chip-left   (+ h-offset left-max lead))
         (chip-right  (+ chip-left chip-w -1))
         (left-rows
          (cl-loop for pin in left-pins
                   for i from 0
                   collect (cons (plist-get pin :n)
                                 (+ chip-top 1 (* i (1+ gap))))))
         (right-rows
          (cl-loop for pin in right-pins
                   for i from 0
                   collect (cons (plist-get pin :n)
                                 (+ chip-top 1 (* i (1+ gap)))))))
    (list :usb-row    usb-row
          :chip-top   chip-top
          :chip-bot   chip-bot
          :legend-row legend-row
          :chip-left  chip-left
          :chip-right chip-right
          :chip-w     chip-w
          :left-max   left-max
          :right-max  right-max
          :lead       lead
          :canvas-w   canvas-w
          :canvas-h   canvas-h
          :left-rows  left-rows
          :right-rows right-rows)))

;;; ============================================================
;;; Drawing primitives
;;;
;;; Each draws onto the grid using rect coordinates.  None of them
;;; references another draw function; positions come from the rect.
;;; Button regions accumulate in `pinout--pending-buttons' and get
;;; applied after grid flush.
;;; ============================================================

(defvar pinout--pending-buttons nil
  "List of (ROW COL-START COL-END . BUTTON-PROPS) tuples.
Applied after grid flush by `pinout--apply-buttons'.")

(defun pinout--draw-rect (grid rect)
  "Draw the chip rectangle (4 edges + 4 corners) into GRID."
  (cl-destructuring-bind
    (&key chip-top chip-bot chip-left chip-right chip-w &allow-other-keys) rect
    (let ((mid-x (+ chip-left (/ chip-w 2))))
      (pinout--grid-set grid chip-top chip-left  (pinout--cell ?┌))
      (cl-loop for c from (1+ chip-left) below mid-x do
        (pinout--grid-set grid chip-top c (pinout--cell ?─)))
      (pinout--grid-set grid chip-top mid-x (pinout--cell ?┴))
      (cl-loop for c from (1+ mid-x) below chip-right do
        (pinout--grid-set grid chip-top c (pinout--cell ?─)))
      (pinout--grid-set grid chip-top chip-right (pinout--cell ?┐))
      (pinout--grid-set grid chip-bot chip-left  (pinout--cell ?└))
      (cl-loop for c from (1+ chip-left) below chip-right do
        (pinout--grid-set grid chip-bot c (pinout--cell ?─)))
      (pinout--grid-set grid chip-bot chip-right (pinout--cell ?┘))
      (cl-loop for r from (1+ chip-top) below chip-bot do
        (pinout--grid-set grid r chip-left  (pinout--cell ?│))
        (pinout--grid-set grid r chip-right (pinout--cell ?│))))))

(defun pinout--draw-usb (grid rect usb)
  "Place the USB label according to USB spec (:type :side :offset)."
  (cl-destructuring-bind
    (&key chip-left chip-right chip-bot usb-row &allow-other-keys) rect
    (let* ((type   (plist-get usb :type))
            (side   (plist-get usb :side))
            (offset (or (plist-get usb :offset) 'center))
            (label  (pcase type
                      ('usb-c "USB-C")
                      ('usb-micro "uUSB")
                      ('usb-mini "miniUSB")
                      ('usb-a "USB-A")
                      (_ (or (symbol-name type) "USB"))))
            (chip-mid   (/ (+ chip-left chip-right) 2))
            (padded     (format " %s " label))
            (pill-w     (+ 2 (length padded)))
            (usb-color  (face-attribute 'pinout-usb :background nil t))
            (edge-face  (when (stringp usb-color) (list :foreground usb-color))))
      (pcase side
        ((or 'top 'bottom)
          (let* ((y (if (eq side 'top) usb-row (1+ chip-bot)))
                  (x (pcase offset
                       ('start  chip-left)
                       ('end    (- chip-right pill-w))
                       (_       (- chip-mid (/ pill-w 2))))))
            (pinout--grid-set   grid y x (pinout--cell ?◖ 'face edge-face))
            (pinout--grid-place grid y (1+ x) padded 'pinout-usb)
            (pinout--grid-set   grid y (+ x 1 (length padded))
              (pinout--cell ?◗ 'face edge-face))))
        (_ nil)))))

(defun pinout--draw-board-name (grid rect name)
  "Embed board NAME centered inside the chip's bottom edge."
  (cl-destructuring-bind
    (&key chip-left chip-right chip-bot &allow-other-keys) rect
    (let* ((mid   (/ (+ chip-left chip-right) 2))
            (label (format " %s " name))
            (x     (- mid (/ (length label) 2))))
      (pinout--grid-place grid chip-bot x label 'bold))))

(defun pinout--draw-pin (grid rect side pin)
  "Draw PIN on SIDE of the chip.
Writes: pin-number pill inside chip (skipped for power/ground roles,
which only show their external trapezoid chip), lead chars, chip-wall
connector, touch glyph at outermost lead position, and external label
chips.  Queues clickable button regions onto `pinout--pending-buttons'.
Side-specific differences (chip wall position, lead step direction,
pin-pill anchor, label-start column) are derived from SIDE."
  (cl-destructuring-bind
      (&key chip-left chip-right lead left-rows right-rows &allow-other-keys) rect
    (let* ((leftp         (eq side 'left))
           (n             (plist-get pin :n))
           (row           (alist-get n (if leftp left-rows right-rows)))
           (pad           (make-string pinout-label-padding ?\s))
           (segments      (pinout--pin-display-segments pin side))
           (label-w       (pinout--pin-display-width pin))
           (color         (pinout--pin-number-color pin))
           (pin-num-str   (number-to-string n))
           (primary-role  (pinout--segment-role (plist-get pin :primary)))
           (skip-num      (memq primary-role '(power ground)))
           (pwm-p         (plist-get pin :pwm))
           (lead-char     (if pwm-p ?∿ ?─))
           (lead-face     (when color
                            (if pwm-p
                                `(:foreground ,color :height 1.3)
                              `(:foreground ,color))))
           (lead-cell     (apply #'pinout--cell lead-char
                                 (and lead-face (list 'face lead-face))))
           (color-props   (when color (list 'face (list :foreground color))))
           (wall-cell     (apply #'pinout--cell
                                 (if leftp ?┤ ?├) color-props))
           (pill-color    (face-attribute 'pinout-gpio :background nil t))
           (pill-edge     (list :foreground pill-color))
           (pill-left     (pinout--cell ?◖ 'face pill-edge))
           (pill-right    (pinout--cell ?◗ 'face pill-edge))
           (touch-cell    (when (plist-get pin :touch)
                            (pinout--cell ?󰩕 'face
                                          `(:foreground ,pill-color :weight bold :height 1.3))))
           (effective-lead (if touch-cell (1+ lead) lead))
           (chip-edge     (if leftp chip-left chip-right))
           (step          (if leftp -1 1))
           (num-col       (if leftp
                              (+ chip-left 2)
                            (- chip-right (+ (length pin-num-str) 3))))
           (label-col     (if leftp
                              (- chip-left effective-lead label-w)
                            (+ chip-right effective-lead 1))))
      (pinout--grid-set grid row chip-edge wall-cell)
      (when touch-cell
        (pinout--grid-set grid row (+ chip-edge step) touch-cell))
      (cl-loop for i from (if touch-cell 2 1) to effective-lead do
               (pinout--grid-set grid row (+ chip-edge (* step i)) lead-cell))
      (unless skip-num
        (let ((digits-end (+ num-col 1 (length pin-num-str))))
          (pinout--grid-set   grid row num-col              pill-left)
          (pinout--grid-place grid row (1+ num-col) pin-num-str 'pinout-gpio)
          (pinout--grid-set   grid row digits-end           pill-right)))
      (let ((col label-col))
        (dolist (seg segments)
          (let* ((text       (car seg))
                 (role       (cdr seg))
                 (face       (pinout--role-face role))
                 (edge-face  (intern (format "pinout-edge-%s" role)))
                 (body       (concat pad text pad))
                 (segw       (+ 2 (length body)))
                 (start-col  col))
            (pinout--grid-set grid row col (pinout--cell ?◥ 'face edge-face))
            (setq col (1+ col))
            (pinout--grid-place grid row col body face)
            (setq col (+ col (length body)))
            (pinout--grid-set grid row col (pinout--cell ?◣ 'face edge-face))
            (setq col (1+ col))
            (push (list row start-col (+ start-col segw -1)
                        :type 'pinout-pin-segment
                        'pinout-pin pin
                        'pinout-segment text)
                  pinout--pending-buttons)))))))

(defun pinout--draw-legend (grid rect)
  "Draw the legend strip centered on `canvas-w'."
  (cl-destructuring-bind (&key legend-row canvas-w &allow-other-keys) rect
    (let* ((boxes (mapcar (lambda (item)
                            (cons (format " %s " (car item)) (cdr item)))
                    pinout--legend-items))
            (sep   "  ")
            (total (+ (cl-loop for (text . _) in boxes sum (length text))
                     (* (length sep) (max 0 (1- (length boxes))))))
            (col   (max 0 (/ (- canvas-w total) 2))))
      (cl-loop for (text . face) in boxes
               for need-sep = nil then t do
        (when need-sep
          (pinout--grid-place grid legend-row col sep)
          (cl-incf col (length sep)))
        (pinout--grid-place grid legend-row col text face)
        (cl-incf col (length text))))))

(defun pinout--apply-buttons (origin)
  "Apply queued buttons as OVERLAYS and register each chip's geometry for
custom mouse-hover tracking.  See `pinout--poll-mouse'.

The button overlay (created via `make-button') carries click + help-echo
but NOT `mouse-face' — we set it to nil because standard `mouse-face'
applies a single face uniformly across its region, which can't paint
body cells differently from edge cells.  Hover visuals are instead
driven by manual `face' overlays toggled by `pinout--poll-mouse'."
  (when (fboundp 'pinout--clear-hover) (pinout--clear-hover))
  (setq pinout--chip-overlays nil)
  (pcase-dolist (`(,row ,col-start ,col-end . ,props) pinout--pending-buttons)
    (let* ((pos-start (pinout--grid-buffer-pos origin row col-start))
           (pos-end   (1+ (pinout--grid-buffer-pos origin row col-end)))
           (button    (apply #'make-button pos-start pos-end props)))
      (push (list button pos-start (1- pos-end)) pinout--chip-overlays))))

;;; ============================================================
;;; Custom hover (manual mouse-position tracking)
;;;
;;; Emacs' built-in `mouse-face' resolves to ONE face per hover region,
;;; determined by the single winning overlay's start..end (see
;;; `note_mouse_highlight' in xdisp.c).  We want body cells to show
;;; `pinout-hover' (yellow bg + dark fg) and the two edge cells to show
;;; `pinout-edge-hover' (yellow fg only) simultaneously — that requires
;;; different faces in the same hover region, which `mouse-face' cannot
;;; express.
;;;
;;; Solution: poll mouse position on a short repeating timer.  When the
;;; mouse moves over a chip we create three `face' overlays (body +
;;; left edge + right edge); on leave we delete them.  Overlay `face'
;;; MERGES per-attribute with the underlying text-property face, so an
;;; edge overlay with only `:foreground' set lets the cell's bg fall
;;; through to default (dark), producing the desired yellow-triangle-
;;; on-dark-bg look.
;;; ============================================================

(defvar-local pinout--chip-overlays nil
  "List of registered chips for hover tracking.
Each entry: (BUTTON-OVERLAY LEFT-EDGE-POS RIGHT-EDGE-POS).")

(defvar-local pinout--hover-overlays nil
  "Currently-active `face' overlays that paint the hovered chip.")

(defvar-local pinout--current-hover-chip nil
  "The chip entry currently being highlighted, or nil.")

(defvar pinout--mouse-tracker-timer nil
  "Repeating timer that drives `pinout--poll-mouse'.")

(defun pinout--clear-hover ()
  "Remove the active hover overlays in the current buffer."
  (mapc #'delete-overlay pinout--hover-overlays)
  (setq pinout--hover-overlays nil
        pinout--current-hover-chip nil))

(defun pinout--apply-hover (chip)
  "Create hover overlays painting CHIP as a yellow parallelogram.
The body overlay covers ONLY the 6 body cells (between the two
triangle edge cells).  Edge overlays cover the `◥' and `◣' cells
individually.  Non-overlapping ranges ensure the body's yellow
`:background' doesn't bleed into the edge cells where we want the
default dark bg to show through behind the yellow triangle glyph."
  (pcase-let ((`(,_button ,left-pos ,right-pos) chip))
    (let* ((body-start (1+ left-pos))
           (body-end   right-pos)
           (body-ov    (make-overlay body-start body-end))
           (left-ov    (make-overlay left-pos  (1+ left-pos)))
           (right-ov   (make-overlay right-pos (1+ right-pos))))
      (overlay-put body-ov  'face 'pinout-hover)
      (overlay-put body-ov  'priority 200)
      (overlay-put left-ov  'face 'pinout-edge-hover)
      (overlay-put left-ov  'priority 200)
      (overlay-put right-ov 'face 'pinout-edge-hover)
      (overlay-put right-ov 'priority 200)
      (setq pinout--hover-overlays  (list body-ov left-ov right-ov)
            pinout--current-hover-chip chip))))

(defun pinout--chip-at (pos)
  "Return the chip entry covering POS in the current buffer, or nil."
  (cl-find-if (lambda (entry)
                (let ((btn (car entry)))
                  (and (overlay-buffer btn)
                       (>= pos (overlay-start btn))
                       (< pos (overlay-end btn)))))
              pinout--chip-overlays))

(defun pinout--poll-mouse ()
  "Read the mouse position and update hover overlays for each
visible pinout buffer."
  (pcase-let* ((`(,frame ,mx . ,my) (mouse-pixel-position))
                (hover-buf  nil)
                (hover-chip nil))
    (when (and (framep frame) (numberp mx) (numberp my)
            (>= mx -1) (>= my 0))
      (when-let* ((posn (posn-at-x-y mx my frame))
                   ((windowp (posn-window posn)))
                   (buf (window-buffer (posn-window posn)))
                   (pos (posn-point posn))
                   ((numberp pos))
                   ((buffer-live-p buf)))
        (with-current-buffer buf
          (when (derived-mode-p 'pinout-mode)
            (setq hover-buf  buf
              hover-chip (pinout--chip-at pos))))))
    (dolist (b (match-buffers '(derived-mode . pinout-mode)))
      (with-current-buffer b
        (let ((target (and (eq b hover-buf) hover-chip)))
          (unless (eq target pinout--current-hover-chip)
            (pinout--clear-hover)
            (when target (pinout--apply-hover target))))))))

(defun pinout--enable-hover-tracking ()
  "Start the global mouse-position polling timer if not running."
  (unless (and pinout--mouse-tracker-timer
               (memq pinout--mouse-tracker-timer timer-list))
    (setq pinout--mouse-tracker-timer
          (run-with-timer 0.016 0.016 #'pinout--poll-mouse))))

(defun pinout--maybe-stop-hover-tracking ()
  "Cancel the mouse-tracker timer when no other pinout buffer remains.
Hooked onto buffer-local `kill-buffer-hook' so it fires as a pinout
buffer is being killed; the current buffer is excluded from the
remaining-pinout count."
  (when (and pinout--mouse-tracker-timer
          (memq pinout--mouse-tracker-timer timer-list)
          (not (seq-find (lambda (b) (not (eq b (current-buffer))))
                 (match-buffers '(derived-mode . pinout-mode)))))
    (cancel-timer pinout--mouse-tracker-timer)
    (setq pinout--mouse-tracker-timer nil)))

;;; ============================================================
;;; Pin segment button type + action
;;; ============================================================

(defun pinout--segment-action (button)
  "Echo info about the pin segment at BUTTON."
  (let* ((segment (button-get button 'pinout-segment))
         (pin     (button-get button 'pinout-pin))
         (role    (pinout--segment-role segment)))
    (message "Pin %d · %s · %s" (plist-get pin :n) segment role)))

(defun pinout--eldoc-at-point (callback &rest _)
  "Eldoc: describe the pin segment at point, if any."
  (when-let* ((pin (get-text-property (point) 'pinout-pin))
              (seg (get-text-property (point) 'pinout-segment)))
    (funcall callback
             (format "Pin %d · %s · %s"
                     (plist-get pin :n) seg (pinout--segment-role seg)))))

(defun pinout--imenu-create-index ()
  "Imenu index: one entry per pin in the current pinout buffer."
  (save-excursion
    (goto-char (point-min))
    (let (index seen)
      (while-let ((match (text-property-search-forward 'pinout-pin nil nil t)))
        (let* ((pin (prop-match-value match))
               (n   (plist-get pin :n)))
          (unless (memq n seen)
            (push n seen)
            (push (cons (format "Pin %d (%s)" n (plist-get pin :primary))
                        (prop-match-beginning match))
                  index))))
      (nreverse index))))

(define-button-type 'pinout-pin-segment
  'face        nil
  'mouse-face  nil
  'follow-link t
  'action      #'pinout--segment-action
  'help-echo
  (lambda (_win _obj pos)
    (let ((pin (get-text-property pos 'pinout-pin))
          (seg (get-text-property pos 'pinout-segment)))
      (format "Pin %d · %s · %s"
              (plist-get pin :n) seg
              (pinout--segment-role seg)))))

;;; ============================================================
;;; Render orchestrator
;;; ============================================================

(defun pinout--render (board)
  "Render BOARD into the current buffer."
  (let* ((rect       (pinout--compute-rect board))
         (canvas-h   (plist-get rect :canvas-h))
         (canvas-w   (plist-get rect :canvas-w))
         (grid       (pinout--grid-make canvas-h canvas-w))
         (pinout--pending-buttons nil))
    (pinout--apply-face-remap (pinout--compute-fit-scale canvas-w canvas-h))
    (insert-char ?\n (max 0 (/ (- (window-body-height nil 'remap) canvas-h) 2)))
    (pinout--draw-rect       grid rect)
    (pinout--draw-usb        grid rect (plist-get board :usb))
    (dolist (pin (pinout--side-pins board 'left))
      (pinout--draw-pin grid rect 'left pin))
    (dolist (pin (pinout--side-pins board 'right))
      (pinout--draw-pin grid rect 'right pin))
    (when (plist-get board :name)
      (pinout--draw-board-name grid rect (plist-get board :name)))
    (when pinout--show-legend
      (pinout--draw-legend grid rect))
    (let* ((window-cols (window-body-width nil 'remap))
           (left-pad    (max 0 (/ (- window-cols canvas-w) 2)))
           (origin      (pinout--grid-flush grid left-pad)))
      (pinout--apply-buttons origin))))

(defun pinout--render-board-in-buffer (board)
  "Re-render the current buffer with BOARD's pinout."
  (when-let ((data (alist-get board pinout-boards)))
    (with-silent-modifications
      (erase-buffer)
      (unless (derived-mode-p 'pinout-mode) (pinout-mode))
      (setq pinout--current-board board)
      (pinout--render data)
      (goto-char (point-min)))
    (set-buffer-modified-p t)))

;;; ============================================================
;;; Zephyr workspace discovery
;;; ============================================================

(defun pinout--workspace-root ()
  (locate-dominating-file default-directory ".west"))

(defun pinout--west-config-value (section key)
  (when-let* ((root   (pinout--workspace-root))
              (config (file-name-concat root ".west" "config"))
              ((file-exists-p config)))
    (with-temp-buffer
      (insert-file-contents config)
      (goto-char (point-min))
      (when (re-search-forward (format "^\\[%s\\]" (regexp-quote section)) nil t)
        (let ((section-end (or (save-excursion (re-search-forward "^\\[" nil t))
                               (point-max))))
          (when (re-search-forward
                 (format "^%s[[:space:]]*=[[:space:]]*\\(.+?\\)[[:space:]]*$"
                         (regexp-quote key))
                 section-end t)
            (match-string 1)))))))

(defun pinout--zephyr-base ()
  (when-let* ((root (pinout--workspace-root))
              (base (pinout--west-config-value "zephyr" "base")))
    (file-name-as-directory (expand-file-name base root))))

(defun pinout--active-board-name ()
  (when-let* ((board (pinout--west-config-value "build" "board")))
    (intern (car (split-string board "/")))))

(defun pinout--locate-board-yml (board)
  (when-let* ((entry  (alist-get board pinout-boards))
              (vendor (plist-get entry :vendor))
              (zephyr (pinout--zephyr-base))
              (file   (file-name-concat
                       zephyr "boards" vendor (symbol-name board) "board.yml"))
              ((file-exists-p file)))
    file))

;;; ============================================================
;;; YAML parsing (tree-sitter)
;;; ============================================================

(defun pinout--yaml-node-to-data (node)
  (pcase (treesit-node-type node)
    ("stream"
     (when-let* ((doc (treesit-search-subtree node "\\`document\\'")))
       (pinout--yaml-node-to-data doc)))
    ("document"
     (when-let* ((inner (treesit-search-subtree
                         node "\\`\\(?:block_node\\|flow_node\\)\\'")))
       (pinout--yaml-node-to-data inner)))
    ((or "block_node" "flow_node")
     (when-let* ((child (treesit-node-child node 0 t)))
       (pinout--yaml-node-to-data child)))
    ((or "block_mapping" "flow_mapping")
     (cl-loop for child in (treesit-node-children node t)
              when (member (treesit-node-type child)
                           '("block_mapping_pair" "flow_pair"))
              collect (cons (pinout--yaml-node-to-data
                             (treesit-node-child-by-field-name child "key"))
                            (pinout--yaml-node-to-data
                             (treesit-node-child-by-field-name child "value")))))
    ((or "block_sequence" "flow_sequence")
     (cl-loop for child in (treesit-node-children node t)
              when (member (treesit-node-type child)
                           '("block_sequence_item" "flow_node"))
              collect (let ((inner (treesit-search-subtree
                                    child "\\`\\(?:block_node\\|flow_node\\)\\'")))
                        (and inner (pinout--yaml-node-to-data inner)))))
    ((or "plain_scalar" "block_scalar")
     (string-trim (treesit-node-text node t)))
    ((or "single_quote_scalar" "double_quote_scalar")
     (let ((raw (treesit-node-text node t)))
       (if (and (>= (length raw) 2) (memq (aref raw 0) '(?' ?\")))
           (substring raw 1 -1)
         raw)))
    (_ (string-trim (treesit-node-text node t)))))

(defun pinout--parse-board-yml (file)
  (when (treesit-ready-p 'yaml 'message)
    (with-temp-buffer
      (insert-file-contents file)
      (let* ((parser (treesit-parser-create 'yaml))
             (root   (treesit-parser-root-node parser)))
        (pinout--yaml-node-to-data root)))))

(defun pinout--yaml-find (key data)
  (cond
   ((and (consp data) (stringp (car data)) (string= (car data) key))
    (cdr data))
   ((listp data)
    (cl-loop for entry in data
             for found = (pinout--yaml-find key entry)
             when found return found))
   (t nil)))

(defun pinout--format-board-info (data format-string)
  (replace-regexp-in-string
   "%\\([a-zA-Z_][a-zA-Z0-9_]*\\)"
   (lambda (match)
     (let ((val (pinout--yaml-find (substring match 1) data)))
       (if (stringp val) val match)))
   format-string t t))

;;; ============================================================
;;; Major mode + responsive sizing
;;; ============================================================

(defvar-local pinout--current-board nil
  "Symbol identifying the board shown in this buffer.")

(defvar-local pinout--face-remap-cookie nil
  "Cookie from `face-remap-add-relative' for height + family remap.")

(defvar-local pinout--show-legend t
  "Buffer-local legend visibility, initialized from `pinout-show-legend'.
Flip with `pinout-toggle-legend'.")

(defun pinout-toggle-legend ()
  "Toggle the role legend below the diagram in the current pinout buffer."
  (interactive)
  (unless (derived-mode-p 'pinout-mode)
    (user-error "Not in a pinout buffer"))
  (setq pinout--show-legend (not pinout--show-legend))
  (revert-buffer))

(defvar-keymap pinout-mode-map
  :doc "Keymap for `pinout-mode'."
  :parent special-mode-map
  "TAB"       #'forward-button
  "<backtab>" #'backward-button)

(defun pinout--hide-cursor ()
  "Hide the cursor in the current buffer.
Uses dirvish's `(bar . 0)' trick: a real cursor spec of width 0.
Robuster than `(list nil)' because evil never treats a non-nil
`cursor-type' as something to recover from."
  (setq-local cursor-type nil)
  (setq-local cursor-in-non-selected-windows nil)
  (dolist (sym '(evil-normal-state-cursor
                 evil-insert-state-cursor
                 evil-visual-state-cursor
                 evil-motion-state-cursor
                 evil-operator-state-cursor
                 evil-replace-state-cursor
                 evil-emacs-state-cursor))
    (when (boundp sym)
      (set (make-local-variable sym) '(bar . 0))))
  (when (fboundp 'evil-refresh-cursor) (evil-refresh-cursor)))

(defun pinout--hide-cursor-deferred ()
  "Schedule `pinout--hide-cursor' for the next event-loop turn.
`run-mode-hooks' runs `pinout-mode-hook' BEFORE
`after-change-major-mode-hook' (where evil activates).  A zero-delay
timer fires after evil has finished initial state setup."
  (let ((buf (current-buffer)))
    (run-at-time
     0 nil
     (lambda ()
       (when (buffer-live-p buf)
         (with-current-buffer buf (pinout--hide-cursor)))))))

(defun pinout--apply-face-remap (&optional scale)
  "Apply font-family + font-height face-remap.
With SCALE non-nil use it as the height factor; otherwise fall back
to `pinout-font-height'."
  (when pinout--face-remap-cookie
    (face-remap-remove-relative pinout--face-remap-cookie))
  (let* ((height (or scale pinout-font-height))
          (spec (append
                  (and pinout-font-family
                    (list :family pinout-font-family))
                  (and (numberp height) (/= height 1.0)
                    (list :height height)))))
    (setq pinout--face-remap-cookie
      (when spec (apply #'face-remap-add-relative 'default spec)))))

(defun pinout--compute-fit-scale (canvas-w canvas-h)
  "Largest face-height scale that fits a CANVAS-W × CANVAS-H grid.
Clamped to [`pinout-font-height-min', `pinout-font-height'].  In
the terminal this typically returns `pinout-font-height' since
`:height' is a no-op there and pixel/char ratios collapse to 1."
  (let* ((px-w (window-body-width  nil t))
          (px-h (window-body-height nil t))
          (cw   (max 1 (frame-char-width)))
          (ch   (max 1 (frame-char-height)))
          (cells-w (/ (float px-w) cw))
          (cells-h (/ (float px-h) ch))
          (margin  (if (numberp pinout-fit-margin) pinout-fit-margin 0.80))
          (fit-w   (* margin (/ cells-w (max 1 canvas-w))))
          (fit-h   (* margin (/ cells-h (max 1 canvas-h))))
          (max-h   (if (numberp pinout-font-height) pinout-font-height 2.0))
          (min-h   (if (numberp pinout-font-height-min) pinout-font-height-min 0.6)))
    (max min-h (min fit-w fit-h max-h))))

(defvar pinout--resize-timer nil)

(defun pinout--handle-resize (_frame)
  "Re-render visible pinout buffers after window resize."
  (when pinout--resize-timer (cancel-timer pinout--resize-timer))
  (setq pinout--resize-timer
        (run-with-idle-timer
         0.15 nil
         (lambda ()
           (dolist (buf (match-buffers '(derived-mode . pinout-mode)))
             (when (get-buffer-window buf 'visible)
               (with-current-buffer buf
                 (let ((inhibit-message t))
                   (revert-buffer)))))))))

(defun pinout--reload-and-reset ()
  "Reload `pinout.el' from disk and reset every `pinout' defcustom.
Iterates the `pinout' custom group via the symbol's `custom-group'
property — no hardcoded list to maintain when new defcustoms are
added."
  (let ((file (or (and buffer-file-name
                    (string-match-p (rx "/pinout.el" eos) buffer-file-name)
                    buffer-file-name)
                (locate-library "pinout"))))
    (when file (load file nil 'nomessage)))
  (dolist (entry (get 'pinout 'custom-group))
    (when (eq (cadr entry) 'custom-variable)
      (custom-reevaluate-setting (car entry)))))

(define-derived-mode pinout-mode special-mode "Pinout"
  "Major mode for displaying board pinout diagrams.
TAB / S-TAB navigate between labels.  RET / mouse-1 echoes a label's
role + pin number.  g re-renders for the current window width."
  (buffer-disable-undo)
  (pinout--hide-cursor)
  (setq-local truncate-lines               t
              tab-width                    1
              line-spacing                 0
              show-trailing-whitespace     nil
              indicate-empty-lines         nil
              pinout--show-legend          pinout-show-legend
              imenu-create-index-function  #'pinout--imenu-create-index
              revert-buffer-function       (lambda (&rest _)
                                             (when-let* ((key pinout--current-board)
                                                         (data (alist-get key pinout-boards)))
                                               (with-silent-modifications
                                                 (erase-buffer)
                                                 (pinout--render data)
                                                 (goto-char (point-min)))
                                               (set-buffer-modified-p t))))
  (font-lock-mode -1)
  (transient-mark-mode -1)
  (add-hook 'eldoc-documentation-functions #'pinout--eldoc-at-point nil t)
  (eldoc-mode 1)
  (add-hook 'window-size-change-functions #'pinout--handle-resize nil t)
  (add-hook 'kill-buffer-hook #'pinout--maybe-stop-hover-tracking nil t)
  (pinout--enable-hover-tracking))

(add-hook 'pinout-mode-hook #'pinout--hide-cursor-deferred)

;;; ============================================================
;;; Entry point
;;; ============================================================

;;;###autoload
(defun pinout (&optional board)
  "Display the pinout diagram for BOARD (a key from `pinout-boards').
With no argument, uses `pinout-default-board'.  Call with prefix arg
to pick a board interactively."
  (interactive
   (list (if (or current-prefix-arg (null pinout-default-board))
             (completing-read "Board: "
                              (mapcar (lambda (e) (symbol-name (car e)))
                                      pinout-boards) nil t)
           pinout-default-board)))
  (pinout--reload-and-reset)
  (let* ((key       (intern board))
         (data      (alist-get key pinout-boards))
         (west      (pinout--west-config-value "build" "board"))
         (buf-name  (format "*pinout:%s*"
                            (if (and west (string-prefix-p board west))
                              west
                              board))))
    (unless data
      (user-error "No pinout defined for %s.  Add to `pinout-boards'" board))
    (switch-to-buffer (get-buffer-create buf-name))
    (pinout--render-board-in-buffer key)
    ;; PARKED: header-line board info — uncomment to show "vendor full_name"
    ;; banner at the top of the pinout buffer.
    ;; (when-let* ((yml      (pinout--locate-board-yml key))
    ;;              (parsed   (pinout--parse-board-yml yml))
    ;;              (rendered (pinout--format-board-info
    ;;                          parsed pinout-board-info-format)))
    ;;   (with-current-buffer buf-name
    ;;     (setq-local header-line-format (propertize rendered 'face 'bold))))
    ))

;;;###autoload
(defun pinout-board (board)
  "Switch to a different board, with live preview as you navigate.

When called from a `pinout-mode' buffer, each highlighted candidate
is rendered into that buffer in real time.  Confirming with RET
swaps to the canonical buffer for the chosen board; aborting with
C-g restores the original board.  Outside `pinout-mode', falls back
to a plain `completing-read'."
  (interactive
    (list
      (let* ((cands       (mapcar (lambda (e) (symbol-name (car e))) pinout-boards))
              (preview-buf (and (derived-mode-p 'pinout-mode) (current-buffer)))
              (original    (and preview-buf pinout--current-board)))
        (if (and preview-buf original (fboundp 'consult--read))
          (unwind-protect
            (consult--read
              cands
              :prompt        "Board: "
              :require-match t
              :category      'pinout-board
              :preview-key   'any
              :state
              (lambda (action cand)
                (when (and (eq action 'preview) (buffer-live-p preview-buf))
                  (with-current-buffer preview-buf
                    (pinout--render-board-in-buffer
                      (or (and cand (intern-soft cand)) original))))))
            (when (buffer-live-p preview-buf)
              (with-current-buffer preview-buf
                (pinout--render-board-in-buffer original))))
          (completing-read "Board: " cands nil t)))))
  (pinout board))

;;; ============================================================
;;; M-x discoverability + Doom keybinding
;;; ============================================================

(unless read-extended-command-predicate
  (setq read-extended-command-predicate #'command-completion-default-include-p))

(put 'pinout-mode 'completion-predicate #'ignore)

(with-eval-after-load 'evil
  (when (fboundp 'map!)
    (map! :leader :prefix "p" :desc "Pinout"       "n" #'pinout)
    (map! :leader :prefix "p" :desc "Switch board" "b" #'pinout-board)
    (map! :map pinout-mode-map :n "SPC p h" #'pinout-toggle-legend)))

(provide 'pinout)
;;; pinout.el ends here
