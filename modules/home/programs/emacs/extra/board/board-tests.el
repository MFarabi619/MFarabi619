;;; board-tests.el --- Buttercup tests for board.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'seq)
(require 'board)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(defun board-tests--render (vnode)
  "Render VNODE into a temp buffer and return the resulting string."
  (with-temp-buffer
    (vui-render vnode)
    (buffer-string)))

(defconst board-tests--sample-pin
  '(:number 5 :labels ("ADC1/A4" "GPIO5" "RTC" "SDA1"))
  "Sample pin plist used across specs.")

(describe "board-definitions (default data)"
  (it "defines the xiao_esp32s3 board"
    (expect (alist-get 'xiao_esp32s3 board-definitions) :to-be-truthy))

  (it "has seven pins on each side"
    (let ((board (alist-get 'xiao_esp32s3 board-definitions)))
      (expect (length (board-side-pins board 'left)) :to-equal 7)
      (expect (length (board-side-pins board 'right)) :to-equal 7))))

(describe "model accessors"
  (it "reads a board's name"
    (expect (board-name '(:name "XIAO ESP32-S3")) :to-equal "XIAO ESP32-S3"))

  (it "reads a side's pins"
    (let ((board '(:sides ((left ((:number 1 :labels ("A"))))
                           (right ((:number 2 :labels ("B"))))))))
      (expect (board-pin-number (car (board-side-pins board 'right)))
        :to-equal 2)))

  (it "reads a pin's number and labels"
    (expect (board-pin-number board-tests--sample-pin) :to-equal 5)
    (expect (board-pin-labels board-tests--sample-pin)
      :to-equal '("ADC1/A4" "GPIO5" "RTC" "SDA1")))

  (it "reads a pin's pwm and touch capabilities"
    (let ((pins (board-side-pins (alist-get 'xiao_esp32s3 board-definitions) 'left)))
      (expect (board-pin-pwm-p (car pins)) :to-be-truthy)
      (expect (board-pin-touch-p (car pins)) :to-be-truthy)
      (expect (board-pin-pwm-p (nth 6 pins)) :to-be-truthy)
      (expect (board-pin-touch-p (nth 6 pins)) :to-be nil))))

(describe "board-label-role"
  (it "classifies power rails"
    (dolist (label '("VBUS" "3V3" "5V0" "3.3V-OUT"))
      (expect (board-label-role label) :to-be 'power)))

  (it "classifies ground"
    (expect (board-label-role "GND") :to-be 'ground))

  (it "classifies system pins"
    (expect (board-label-role "RTC") :to-be 'system)
    (expect (board-label-role "RST") :to-be 'system))

  (it "classifies ADC channels"
    (expect (board-label-role "ADC1/A0") :to-be 'adc)
    (expect (board-label-role "ADC2_9") :to-be 'adc))

  (it "classifies I2C signals"
    (expect (board-label-role "SDA1") :to-be 'i2c)
    (expect (board-label-role "SCL1") :to-be 'i2c))

  (it "classifies SPI signals"
    (dolist (label '("MOSI0" "MISO0" "SCK0"))
      (expect (board-label-role label) :to-be 'spi)))

  (it "classifies UART signals"
    (expect (board-label-role "TX0") :to-be 'uart)
    (expect (board-label-role "RX0") :to-be 'uart))

  (it "classifies GPIO names as pin names"
    (expect (board-label-role "GPIO43") :to-be 'pin-name))

  (it "classifies Seeed D-numbers as digital gpio"
    (expect (board-label-role "D0") :to-be 'gpio)
    (expect (board-label-role "D10") :to-be 'gpio))

  (it "falls back to gpio"
    (expect (board-label-role "WHATEVER") :to-be 'gpio)))

(describe "board--label-chip"
  (it "wraps the padded label in slanted edge glyphs"
    (expect (substring-no-properties (board--label-chip "GND"))
      :to-equal "◥ GND ◣"))

  (it "carries the role face on the body"
    (expect (get-text-property 1 'face (board--label-chip "VBUS"))
      :to-be 'board-power))

  (it "tints the edge glyphs with the role color, foreground only"
    (expect (get-text-property 0 'face (board--label-chip "VBUS"))
      :to-equal (list :foreground (face-attribute 'board-power :background nil t)))))

(describe "board--labels-cell"
  (it "renders right-side labels innermost-first"
    (expect (substring-no-properties (board--labels-cell board-tests--sample-pin 'right))
      :to-equal "◥ ADC1/A4 ◣◥ GPIO5 ◣◥ RTC ◣◥ SDA1 ◣"))

  (it "reverses left-side labels so the innermost label touches the chip"
    (expect (substring-no-properties (board--labels-cell board-tests--sample-pin 'left))
      :to-equal "◥ SDA1 ◣◥ RTC ◣◥ GPIO5 ◣◥ ADC1/A4 ◣"))

  (it "renders an absent pin as an empty cell"
    (expect (board--labels-cell nil 'left) :to-equal "")))

(describe "board--pin-primary-role"
  (it "uses the hidden :primary identity label when present"
    (expect (board--pin-primary-role '(:number 1 :primary "D0" :labels ("ADC1/A0")))
      :to-be 'gpio))

  (it "falls back to the innermost label"
    (expect (board--pin-primary-role '(:number 14 :labels ("VBUS")))
      :to-be 'power))

  (it "tints XIAO gpio leads pill-green via the D-name identity"
    (let* ((pin (car (board-side-pins (alist-get 'xiao_esp32s3 board-definitions) 'left)))
            (lead (board--lead pin 'left)))
      (expect (plist-get (get-text-property 0 'face lead) :foreground)
        :to-equal (face-attribute 'board-gpio :background nil t)))))

(describe "board--lead"
  (it "draws a straight lead for plain pins"
    (expect (substring-no-properties (board--lead '(:number 14 :labels ("VBUS")) 'right))
      :to-equal "──"))

  (it "draws a sine lead for pwm pins"
    (expect (substring-no-properties (board--lead '(:number 7 :labels ("GPIO43") :pwm t) 'left))
      :to-equal "∿∿"))

  (it "puts the touch glyph against the wall on the left side"
    (expect (substring-no-properties
              (board--lead '(:number 1 :labels ("GPIO1") :pwm t :touch t) 'left))
      :to-equal "∿󰩕"))

  (it "puts the touch glyph against the wall on the right side"
    (expect (substring-no-properties
              (board--lead '(:number 9 :labels ("GPIO7") :pwm t :touch t) 'right))
      :to-equal "󰩕∿"))

  (it "tints the touch glyph pill-green"
    (let ((lead (board--lead '(:number 1 :labels ("GPIO1") :touch t) 'left)))
      (expect (plist-get (get-text-property 1 'face lead) :foreground)
        :to-equal (face-attribute 'board-gpio :background nil t))))

  (it "renders blank margin for an absent pin"
    (expect (board--lead nil 'left) :to-equal "  ")))

(describe "board--body-cell"
  (it "is exactly the body span wide"
    (expect (length (board--body-cell board-tests--sample-pin board-tests--sample-pin))
      :to-equal (board--body-span)))

  (it "draws leads, connected walls, and pin numbers in round pills"
    (let ((cell (substring-no-properties
                  (board--body-cell '(:number 1 :labels ("A")) '(:number 14 :labels ("B"))))))
      (expect cell :to-match "\\`──┤ .1. +.14. ├──\\'")))

  (it "draws a plain wall and no lead where a side has no pin"
    (let ((cell (substring-no-properties
                  (board--body-cell nil '(:number 14 :labels ("B"))))))
      (expect cell :to-match "\\`  │ +.14. ├──\\'")))

  (it "omits the number pill on power and ground pins"
    (let ((cell (substring-no-properties
                  (board--body-cell '(:number 14 :labels ("VBUS")) '(:number 13 :labels ("GND"))))))
      (expect cell :not :to-match "1[43]")))

  (it "tints the lead and wall with the primary label's role color"
    (let* ((cell (board--body-cell '(:number 14 :labels ("VBUS")) nil))
            (power-tint (list :foreground (face-attribute 'board-power :background nil t))))
      (expect (get-text-property 0 'face cell) :to-equal power-tint)
      (expect (get-text-property board-lead-length 'face cell) :to-equal power-tint))))

(describe "board--body-top-cell and board--body-bottom-cell"
  (it "spans the body span with corners"
    (expect (length (board--body-top-cell)) :to-equal (board--body-span))
    (expect (board--body-top-cell) :to-match "\\`  ┌─+┐  \\'"))

  (it "centers the board name in the bottom edge"
    (let ((bottom (substring-no-properties (board--body-bottom-cell "XIAO"))))
      (expect (length bottom) :to-equal (board--body-span))
      (expect bottom :to-match "\\`  └─+ XIAO ─+┘  \\'"))))

(describe "board--centering-pad"
  (it "halves the leftover space, flooring"
    (expect (board--centering-pad 10 4) :to-equal 3)
    (expect (board--centering-pad 10 5) :to-equal 2))

  (it "never goes negative when content overflows"
    (expect (board--centering-pad 5 9) :to-equal 0)))

(describe "board--fit-scale"
  (it "picks the tighter of the two axes"
    (let ((board-fit-fraction 0.8)
           (board-max-scale 2.0)
           (board-min-scale 0.6))
      (expect (board--fit-scale 50 10 1000 500 10 20) :to-equal 1.6)))

  (it "caps at board-max-scale"
    (let ((board-fit-fraction 0.8)
           (board-max-scale 2.0)
           (board-min-scale 0.6))
      (expect (board--fit-scale 10 5 4000 2000 10 20) :to-equal 2.0)))

  (it "floors at board-min-scale"
    (let ((board-fit-fraction 0.8)
           (board-max-scale 2.0)
           (board-min-scale 0.6))
      (expect (board--fit-scale 500 100 400 200 10 20) :to-equal 0.6))))

(describe "board--vnode-size"
  (it "measures a single text node"
    (expect (board--vnode-size (vui-text "abc")) :to-equal '(3 . 1)))

  (it "measures multibyte box-drawing characters as single columns"
    (expect (board--vnode-size (vui-text "──┤")) :to-equal '(3 . 1)))

  (it "measures the diagram as usb row, top edge, seven pin rows, bottom edge"
    (let* ((board-row-spacing 0)
            (board-show-legend nil)
            (size (board--vnode-size
                    (board--diagram (alist-get 'xiao_esp32s3 board-definitions)))))
      (expect (cdr size) :to-equal 10)
      (expect (car size) :to-be-greater-than board-body-width))))

(describe "board-row-spacing"
  (it "interleaves spacer rows between pin rows"
    (let* ((board-row-spacing 2)
            (board-show-legend nil)
            (size (board--vnode-size
                    (board--diagram (alist-get 'xiao_esp32s3 board-definitions)))))
      (expect (cdr size) :to-equal 22)))

  (it "draws unconnected walls through spacer rows"
    (let* ((board-row-spacing 1)
            (text (board-tests--render
                    (board--diagram (alist-get 'xiao_esp32s3 board-definitions))))
            (spacer-lines (seq-filter
                            (lambda (line)
                              (and (string-match-p "│" line)
                                (not (string-match-p "┤\\|├\\|[0-9]" line))))
                            (split-string text "\n"))))
      (expect (length spacer-lines) :to-equal 6))))

(describe "board--usb-cell"
  (it "centers the connector pill within the chip span"
    (let ((cell (substring-no-properties (board--usb-cell '(:type usb-c :side top)))))
      (expect cell :to-match "\\` \\{10,\\}. USB-C .\\'")))

  (it "names the connector from its type"
    (expect (board--usb-label '(:type usb-micro)) :to-equal "uUSB")
    (expect (board--usb-label '(:type usb-c)) :to-equal "USB-C")))

(describe "board--apply-theme-colors"
  (it "syncs role backgrounds from nerd-icons foregrounds"
    (require 'nerd-icons)
    (board--apply-theme-colors)
    (dolist (pair '((board-adc . nerd-icons-orange)
                     (board-spi . nerd-icons-purple)
                     (board-system . nerd-icons-silver)))
      (expect (face-attribute (car pair) :background)
        :to-equal (face-attribute (cdr pair) :foreground))))

  (it "leaves the hardcoded power and gpio hexes alone"
    (board--apply-theme-colors)
    (expect (face-attribute 'board-power :background) :to-equal "#e57373")
    (expect (face-attribute 'board-gpio :background) :to-equal "#9ccc65")))

(describe "board--legend"
  (it "renders one chip per legend item"
    (let ((legend (substring-no-properties (board--legend))))
      (dolist (label '("SYSTEM" "POWER" "GND" "DIGITAL" "ADC INPUT"
                        "PIN NAME" "SPI" "UART" "I2C"))
        (expect legend :to-match (regexp-quote label)))))

  (it "faces each chip with its role face"
    (expect (get-text-property 1 'face (board--legend)) :to-be 'board-system)))

(describe "board--diagram usb and legend"
  :var* ((lines (let ((board-row-spacing 0))
                  (split-string
                    (board-tests--render
                      (board--diagram (alist-get 'xiao_esp32s3 board-definitions)))
                    "\n"))))

  (it "draws the usb pill in the row above the top edge"
    (let ((usb-line (cl-position-if (lambda (line) (string-match-p "USB-C" line)) lines))
           (top-line (cl-position-if (lambda (line) (string-match-p "┌" line)) lines)))
      (expect usb-line :to-equal (1- top-line))))

  (it "appends the legend below the diagram"
    (let ((legend-line (cl-position-if (lambda (line) (string-match-p "SYSTEM" line)) lines))
           (bottom-line (cl-position-if (lambda (line) (string-match-p "└" line)) lines)))
      (expect legend-line :to-be-greater-than bottom-line)))

  (it "omits the legend when board-show-legend is nil"
    (let ((board-show-legend nil))
      (expect (board-tests--render
                (board--diagram (alist-get 'xiao_esp32s3 board-definitions)))
        :not :to-match "SYSTEM"))))

(describe "board--center"
  :var* ((board (alist-get 'xiao_esp32s3 board-definitions))
          (size (let ((board-row-spacing 0)
                       (board-show-legend nil))
                  (board--vnode-size (board--diagram board))))
          (total-columns (+ (car size) 20))
          (total-rows (+ (cdr size) 10))
          (text (let ((board-row-spacing 0)
                       (board-show-legend nil))
                  (board-tests--render
                    (board--center (board--diagram board) size
                      total-columns total-rows))))
          (lines (split-string text "\n")))

  (it "pads the top so the diagram sits vertically centered"
    (let ((first-content-line (cl-position-if
                                (lambda (line) (string-match-p "┌" line))
                                lines)))
      (expect first-content-line :to-equal 6)))

  (it "indents every diagram line by the centering pad"
    (let* ((content-line-p (lambda (line) (string-match-p "│\\|┤\\|├\\|┌\\|└" line)))
            (leading-spaces (lambda (line)
                              (string-match "\\` *" line)
                              (match-end 0)))
            (content-lines (seq-filter content-line-p lines))
            (uncentered-lines (seq-filter content-line-p
                                (split-string
                                  (let ((board-row-spacing 0)
                                         (board-show-legend nil))
                                    (board-tests--render (board--diagram board)))
                                  "\n"))))
      (expect (length content-lines) :to-equal (1- (cdr size)))
      (expect (cl-loop for line in content-lines
                minimize (funcall leading-spaces line))
        :to-equal (+ 10 (cl-loop for line in uncentered-lines
                         minimize (funcall leading-spaces line))))))

  (it "keeps the chip walls aligned after indenting"
    (let ((columns (delq nil (mapcar (lambda (line) (cl-position ?┤ line)) lines))))
      (expect (length columns) :to-equal 7)
      (expect (length (seq-uniq columns)) :to-equal 1))))

(describe "board--diagram"
  :var* ((text (board-tests--render
                 (board--diagram (alist-get 'xiao_esp32s3 board-definitions))))
          (lines (split-string text "\n")))

  (it "renders the board name and pin labels"
    (dolist (expected '("XIAO ESP32-S3" "VBUS" "GND" "3.3V-OUT" "GPIO43" "ADC1/A0"))
      (expect text :to-match (regexp-quote expected))))

  (it "renders one connected left wall per left pin"
    (expect (seq-count (lambda (line) (string-match-p "┤" line)) lines)
      :to-equal 7))

  (it "aligns the chip walls into a single column across rows"
    (let ((columns (delq nil (mapcar (lambda (line) (cl-position ?┤ line)) lines))))
      (expect (length (seq-uniq columns)) :to-equal 1))))

(describe "board (entry point)"
  (it "signals a user-error for an unknown board"
    (let ((board-default-board 'no_such_board))
      (expect (board) :to-throw 'user-error))))

(provide 'board-tests)

;;; board-tests.el ends here
