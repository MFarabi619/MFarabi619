;;; board-tests.el --- Buttercup tests for board.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'cl-lib)
(require 'seq)
(require 'board)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(defconst board-tests--fixtures
  (expand-file-name "fixtures"
    (file-name-directory (or load-file-name buffer-file-name)))
  "Fixture mirrors of the upstream source trees.")

(setq board-zephyr-root (expand-file-name "zephyr" board-tests--fixtures)
  board-hal-espressif-root (expand-file-name "hal_espressif"
                             board-tests--fixtures)
  board-arduino-variants-root
  (expand-file-name "framework-arduinoespressif32/variants"
    board-tests--fixtures))

(defun board-tests--render (vnode)
  "Render VNODE into a temp buffer and return the resulting string."
  (with-temp-buffer
    (vui-render vnode)
    (buffer-string)))

(defconst board-tests--sample-pin
  '(:number 5 :labels ("ADC1/A4" "GPIO5" "RTC" "SDA1"))
  "Sample pin plist used across specs.")

(describe "board sources"
  :var* ((xiao-directory (board--zephyr-board-directory "seeed/xiao_esp32s3")))

  (it "reads the board name and chip from board.yml"
    (expect (board--board-yml xiao-directory)
      :to-equal '(:full-name "XIAO ESP32S3" :chip "esp32s3")))

  (it "decodes the connector map across gpio ports"
    (let ((connector (board--connector-gpios xiao-directory)))
      (expect (alist-get 0 connector) :to-equal 1)
      (expect (alist-get 6 connector) :to-equal 43)
      (expect (alist-get 10 connector) :to-equal 9)))

  (it "collects each GPIO's pinmux signals"
    (let ((signals (board--pinctrl-signals xiao-directory)))
      (expect (alist-get 43 signals) :to-equal '("UART0_TX"))
      (expect (alist-get 5 signals) :to-equal '("I2C0_SDA"))
      (expect (alist-get 3 signals) :to-equal '("TWAI_TX"))))

  (it "maps GPIOs to ADC channels from the silicon table"
    (let ((adc (board--adc-labels "esp32s3")))
      (expect (alist-get 1 adc) :to-equal "ADC1_0")
      (expect (alist-get 19 adc) :to-equal "ADC2_8")))

  (it "lists the RTC-domain GPIOs"
    (let ((rtc (board--rtc-gpios "esp32s3")))
      (expect (memq 21 rtc) :to-be-truthy)
      (expect (memq 22 rtc) :to-be nil)))

  (it "reads touch pads from the Arduino variant"
    (expect (board--arduino-touch-gpios "XIAO_ESP32S3")
      :to-equal '(1 2 3 4 5 6 7 8 9)))

  (it "keeps Zephyr signal names for known buses and silences the rest"
    (expect (board--signal-chip-label "UART0_TX") :to-equal "UART0_TX")
    (expect (board--signal-chip-label "SPIM2_SCLK") :to-equal "SPIM2_SCLK")
    (expect (board--signal-chip-label "LCD_CAM_CAM_CLK") :to-be nil))

  (it "renders Arduino short forms under that label style"
    (let ((board-label-style 'arduino))
      (expect (board--signal-chip-label "UART0_TX") :to-equal "TX0")
      (expect (board--signal-chip-label "SPIM2_SCLK") :to-equal "SCK2")
      (expect (board--signal-chip-label "TWAI_RX") :to-equal "CAN_RX"))))

(describe "board--resolve"
  :var* ((xiao (board--lookup 'xiao_esp32s3)))

  (it "names the board from board.yml"
    (expect (board-name xiao) :to-equal "XIAO ESP32S3"))

  (it "resolves a connector pin with its full capability chain"
    (expect (car (board-side-pins xiao 'left))
      :to-equal '(:number 1 :primary "D0"
                   :labels ("GPIO1" "RTC" "ADC1_0") :pwm t :touch t)))

  (it "resolves bus roles from the board pinctrl"
    (expect (plist-get (nth 4 (board-side-pins xiao 'left)) :labels)
      :to-equal '("GPIO5" "I2C0_SDA" "RTC" "ADC1_4")))

  (it "resolves each label style separately through the cache"
    (let* ((board-label-style 'arduino)
            (arduino-pin (nth 4 (board-side-pins
                                  (board--lookup 'xiao_esp32s3) 'left))))
      (expect (plist-get arduino-pin :labels)
        :to-equal '("GPIO5" "SDA0" "RTC" "ADC1_4"))))

  (it "numbers the right side counterclockwise from the total"
    (expect (car (board-side-pins xiao 'right))
      :to-equal '(:number 14 :labels ("VBUS"))))

  (it "resolves plain GPIO keys without a vendor primary"
    (let ((uart-pin (nth 1 (board-side-pins
                             (board--lookup 'esp32s3_devkitc1) 'right))))
      (expect (plist-get uart-pin :primary) :to-be nil)
      (expect (plist-get uart-pin :labels) :to-equal '("GPIO43" "UART0_TX")))))

(describe "board-definitions (default data)"
  (it "defines the xiao_esp32s3 board"
    (expect (board--lookup 'xiao_esp32s3) :to-be-truthy))

  (it "has seven pins on each side"
    (let ((board (board--lookup 'xiao_esp32s3)))
      (expect (length (board-side-pins board 'left)) :to-equal 7)
      (expect (length (board-side-pins board 'right)) :to-equal 7)))

  (it "defines the esp32s3_devkitc1 board with all 44 header pins"
    (let ((board (board--lookup 'esp32s3_devkitc1)))
      (expect board :to-be-truthy)
      (expect (length (board-side-pins board 'left)) :to-equal 22)
      (expect (length (board-side-pins board 'right)) :to-equal 22)))

  (it "gives the devkit a micro-usb connector on the bottom"
    (expect (board-usb (board--lookup 'esp32s3_devkitc1))
      :to-equal '(:type usb-micro :side bottom))))

(describe "board--row-spacing"
  (it "uses the board's own :row-spacing override"
    (expect (board--row-spacing (board--lookup 'esp32s3_devkitc1))
      :to-equal 1))

  (it "falls back to board-row-spacing"
    (expect (board--row-spacing (board--lookup 'xiao_esp32s3))
      :to-equal board-row-spacing)))

(describe "board-side-pins"
  (it "unwraps the side's extra list nesting"
    (let ((board '(:sides ((left ((:number 1 :labels ("A"))))
                           (right ((:number 2 :labels ("B"))))))))
      (expect (board-pin-number (car (board-side-pins board 'right)))
        :to-equal 2))))

(describe "board-label-role"
  (it "classifies power rails"
    (dolist (label '("VBUS" "3V3" "5V0" "3V3-OUT"))
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

  (it "classifies silicon UART pad names"
    (expect (board-label-role "U0TXD") :to-be 'uart)
    (expect (board-label-role "U0RXD") :to-be 'uart))

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
    (expect (board--labels-cell nil 'left) :to-equal ""))

  (it "carries the pin and the chip keymap on every chip"
    (let ((cell (board--labels-cell board-tests--sample-pin 'right)))
      (expect (get-text-property 0 'board-pin cell) :to-be board-tests--sample-pin)
      (expect (get-text-property (1- (length cell)) 'board-pin cell)
        :to-be board-tests--sample-pin)
      (expect (get-text-property 0 'keymap cell) :to-be board-chip-map)))

  (it "gives adjacent chips distinct help-echo runs"
    (let* ((cell (board--labels-cell board-tests--sample-pin 'right))
            (second-chip (next-single-property-change 0 'help-echo cell)))
      (expect second-chip :to-equal 11)
      (expect (eq (get-text-property 0 'help-echo cell)
                (get-text-property second-chip 'help-echo cell))
        :to-be nil)))

  (it "describes pin, label, and role in each chip's help echo"
    (let ((cell (board--labels-cell board-tests--sample-pin 'right)))
      (expect (get-text-property 0 'help-echo cell)
        :to-equal "Pin 5 · ADC1/A4 · adc"))))

(describe "board--pin-primary-role"
  (it "uses the hidden :primary identity label when present"
    (expect (board--pin-primary-role '(:number 1 :primary "D0" :labels ("ADC1/A0")))
      :to-be 'gpio))

  (it "falls back to the innermost label"
    (expect (board--pin-primary-role '(:number 14 :labels ("VBUS")))
      :to-be 'power))

  (it "tints XIAO gpio leads pill-green via the D-name identity"
    (let* ((pin (car (board-side-pins (board--lookup 'xiao_esp32s3) 'left)))
            (lead (board--lead pin 'left)))
      (expect (plist-get (get-text-property 0 'face lead) :foreground)
        :to-equal (face-attribute 'board-gpio :background nil t)))))

(describe "board--lead"
  (it "draws a full-width straight lead for plain pins"
    (expect (substring-no-properties (board--lead '(:number 14 :labels ("VBUS")) 'right))
      :to-equal "───"))

  (it "draws a full-width sine lead for pwm pins"
    (expect (substring-no-properties (board--lead '(:number 7 :labels ("GPIO43") :pwm t) 'left))
      :to-equal "∿∿∿"))

  (it "adds the touch glyph beside the wall without shortening the lead, left side"
    (expect (substring-no-properties
              (board--lead '(:number 1 :labels ("GPIO1") :pwm t :touch t) 'left))
      :to-equal "∿∿󰩕"))

  (it "adds the touch glyph beside the wall without shortening the lead, right side"
    (expect (substring-no-properties
              (board--lead '(:number 9 :labels ("GPIO7") :pwm t :touch t) 'right))
      :to-equal "󰩕∿∿"))

  (it "tints the touch glyph pill-green"
    (let ((lead (board--lead '(:number 1 :labels ("GPIO1") :touch t) 'left)))
      (expect (plist-get (get-text-property 2 'face lead) :foreground)
        :to-equal (face-attribute 'board-gpio :background nil t))))

  (it "renders blank margin for an absent pin"
    (expect (board--lead nil 'left) :to-equal "   ")))

(describe "board--body-cell"
  (it "is exactly the body span wide"
    (expect (length (board--body-cell board-tests--sample-pin board-tests--sample-pin))
      :to-equal (board--body-span)))

  (it "draws leads, connected walls, and pin numbers in round pills"
    (let ((cell (substring-no-properties
                  (board--body-cell '(:number 1 :labels ("A")) '(:number 14 :labels ("B"))))))
      (expect cell :to-match "\\`───┤ .1. +.14. ├───\\'")))

  (it "draws a plain wall and no lead where a side has no pin"
    (let ((cell (substring-no-properties
                  (board--body-cell nil '(:number 14 :labels ("B"))))))
      (expect cell :to-match "\\`   │ +.14. ├───\\'")))

  (it "omits the number pill on power and ground pins"
    (let ((cell (substring-no-properties
                  (board--body-cell '(:number 14 :labels ("VBUS")) '(:number 13 :labels ("GND"))))))
      (expect cell :not :to-match "1[43]")))

  (it "tints the lead and wall with the primary label's role color"
    (let* ((cell (board--body-cell '(:number 14 :labels ("VBUS")) nil))
            (power-tint (list :foreground (face-attribute 'board-power :background nil t))))
      (expect (get-text-property 1 'face cell) :to-equal power-tint)
      (expect (get-text-property (board--lead-width) 'face cell) :to-equal power-tint))))

(describe "board--body-top-cell and board--body-bottom-cell"
  (it "spans the body span with corners"
    (expect (length (board--body-top-cell)) :to-equal (board--body-span))
    (expect (board--body-top-cell) :to-match "\\`   ┌─+┐   \\'"))

  (it "centers the board name in the bottom edge"
    (let ((bottom (substring-no-properties (board--body-bottom-cell "XIAO"))))
      (expect (length bottom) :to-equal (board--body-span))
      (expect bottom :to-match "\\`   └─+ XIAO ─+┘   \\'"))))

(describe "board--centering-pad"
  (it "halves the leftover space, flooring"
    (expect (board--centering-pad 10 4) :to-equal 3)
    (expect (board--centering-pad 10 5) :to-equal 2))

  (it "never goes negative when content overflows"
    (expect (board--centering-pad 5 9) :to-equal 0)))

(describe "board--vnode-size"
  (it "measures a single text node"
    (expect (board--vnode-size (vui-text "abc")) :to-equal '(3 . 1)))

  (it "measures multibyte box-drawing characters as single columns"
    (expect (board--vnode-size (vui-text "──┤")) :to-equal '(3 . 1)))

  (it "measures the diagram as usb row, top edge, seven pin rows, bottom edge"
    (let* ((board-row-spacing 0)
            (board-show-legend nil)
            (size (board--vnode-size
                    (board--diagram (board--lookup 'xiao_esp32s3)))))
      (expect (cdr size) :to-equal 10)
      (expect (car size) :to-be-greater-than board-body-width))))

(describe "board-row-spacing"
  (it "interleaves spacer rows between pin rows"
    (let* ((board-row-spacing 2)
            (board-show-legend nil)
            (size (board--vnode-size
                    (board--diagram (board--lookup 'xiao_esp32s3)))))
      (expect (cdr size) :to-equal 22)))

  (it "draws unconnected walls through spacer rows"
    (let* ((board-row-spacing 1)
            (text (board-tests--render
                    (board--diagram (board--lookup 'xiao_esp32s3))))
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
                      (board--diagram (board--lookup 'xiao_esp32s3)))
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
                (board--diagram (board--lookup 'xiao_esp32s3)))
        :not :to-match "SYSTEM"))))

(describe "board--layout"
  (it "keeps the preferred spacing when it fits"
    (pcase-let* ((board (board--lookup 'xiao_esp32s3))
                  (`(,_ . ,canvas-size) (board--layout board 4000)))
      (expect (cdr canvas-size)
        :to-equal (cdr (board--vnode-size (board--diagram board))))))

  (it "compresses the gaps between pins when the window is short"
    (pcase-let* ((board (board--lookup 'xiao_esp32s3))
                  (`(,_ . ,canvas-size) (board--layout board 20)))
      (expect (cdr canvas-size)
        :to-be-less-than (cdr (board--vnode-size (board--diagram board))))
      (expect (cdr canvas-size) :to-be-weakly-less-than 20)))

  (it "spends exactly the spare rows when a full spacing level cannot fit"
    (pcase-let* ((board (board--lookup 'esp32s3_devkitc1))
                  (dense-rows (cdr (board--vnode-size (board--diagram board 0))))
                  (`(,_ . ,canvas-size)
                    (board--layout board (+ dense-rows 5))))
      (expect (cdr canvas-size) :to-equal (+ dense-rows 5))))

  (it "gives content every last row: margins are only leftovers"
    (pcase-let* ((board (board--lookup 'esp32s3_devkitc1))
                  (rows-with-gaps (cdr (board--vnode-size
                                         (board--diagram board 1))))
                  (`(,_ . ,canvas-size)
                    (board--layout board rows-with-gaps)))
      (expect (cdr canvas-size) :to-equal rows-with-gaps)))

  (it "fits whenever fitting is possible; the dense diagram is the floor"
    (dolist (key '(xiao_esp32s3 esp32s3_devkitc1))
      (dolist (window-rows '(20 50 110 400))
        (pcase-let* ((board (board--lookup key))
                      (dense-rows (cdr (board--vnode-size
                                         (board--diagram board 0))))
                      (`(,_ . ,canvas-size) (board--layout board window-rows)))
          (expect (cdr canvas-size)
            :to-be-weakly-less-than (max window-rows dense-rows)))))))

(describe "board--center"
  :var* ((board (board--lookup 'xiao_esp32s3))
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
                 (board--diagram (board--lookup 'xiao_esp32s3))))
          (lines (split-string text "\n")))

  (it "renders the board name and pin labels"
    (dolist (expected '("XIAO ESP32S3" "VBUS" "GND" "3V3-OUT" "GPIO43" "ADC1_0"))
      (expect text :to-match (regexp-quote expected))))

  (it "renders one connected left wall per left pin"
    (expect (seq-count (lambda (line) (string-match-p "┤" line)) lines)
      :to-equal 7))

  (it "aligns the chip walls into a single column across rows"
    (let ((columns (delq nil (mapcar (lambda (line) (cl-position ?┤ line)) lines))))
      (expect (length (seq-uniq columns)) :to-equal 1))))

(describe "a mounted board buffer"
  (before-each
    (board-show (board--lookup 'xiao_esp32s3)))

  (after-each
    (when-let* ((buffer (get-buffer board-buffer-name)))
      (kill-buffer buffer)))

  (it "re-displays a buried board in the invoking window instead of splitting"
    (delete-other-windows)
    (set-window-buffer (selected-window) (get-buffer-create "*scratch*"))
    (board-show (board--lookup 'esp32s3_devkitc1))
    (expect (get-buffer-window board-buffer-name t) :to-be (selected-window))
    (expect (length (window-list)) :to-equal 1))

  (it "is displayed in a window with the board rendered"
    (expect (get-buffer-window board-buffer-name) :to-be-truthy)
    (with-current-buffer board-buffer-name
      (expect board--current
        :to-be (board--lookup 'xiao_esp32s3))
      (expect (buffer-string) :to-match "XIAO ESP32S3")))

  (it "highlights the chip under a synthetic mouse event and clears off-chip"
    (let* ((window (get-buffer-window board-buffer-name))
            (chip-position
              (with-current-buffer board-buffer-name
                (goto-char (point-min))
                (prop-match-beginning
                  (text-property-search-forward 'help-echo nil
                    (lambda (_ value) value))))))
      (board-follow-mouse
        (list 'mouse-movement (list window chip-position '(0 . 0) 0)))
      (with-current-buffer board-buffer-name
        (expect (length board--hover-overlays) :to-equal 3))
      (board-follow-mouse
        (list 'mouse-movement (list window 1 '(0 . 0) 0)))
      (with-current-buffer board-buffer-name
        (expect board--hover-overlays :to-be nil))))

  (it "swaps boards in place through board-switch"
    (board-switch 'esp32s3_devkitc1)
    (with-current-buffer board-buffer-name
      (expect (board-name board--current) :to-equal "ESP32-S3-DevKitC-1")))

  (it "names the current board in the mode line"
    (with-current-buffer board-buffer-name
      (expect mode-name :to-equal "board[XIAO ESP32S3]"))))

(describe "board--refit-if-window-changed"
  (it "refreshes once when the window changed since the layout"
    (with-temp-buffer
      (spy-on 'vui-refresh)
      (setq-local board--layout-window-cells '(1 . 1))
      (cl-letf (((symbol-function 'get-buffer-window)
                  (lambda (&rest _) (selected-window))))
        (board--refit-if-window-changed))
      (expect 'vui-refresh :to-have-been-called)))

  (it "stays quiet while the geometry still matches"
    (with-temp-buffer
      (spy-on 'vui-refresh)
      (let ((window (selected-window)))
        (cl-letf (((symbol-function 'get-buffer-window)
                    (lambda (&rest _) window)))
          (setq-local board--layout-window-cells
            (cons (window-body-width window t)
              (window-body-height window t)))
          (board--refit-if-window-changed)))
      (expect 'vui-refresh :not :to-have-been-called))))

(describe "board (entry point)"
  (it "signals a user-error for an unknown board"
    (let ((board-default-board 'no_such_board))
      (expect (board) :to-throw 'user-error)))

  (it "shows the board in exactly one window and selects it"
    (unwind-protect
      (progn
        (board)
        (expect (length (get-buffer-window-list board-buffer-name nil t))
          :to-equal 1)
        (expect (window-buffer (selected-window))
          :to-be (get-buffer board-buffer-name)))
      (when-let* ((buffer (get-buffer board-buffer-name)))
        (kill-buffer buffer)))))

(describe "board hover engine"
  (it "finds the chip bounds around a position"
    (with-temp-buffer
      (insert (board--labels-cell board-tests--sample-pin 'right))
      (expect (board--chip-bounds 3) :to-equal '(1 . 12))
      (expect (board--chip-bounds 12) :to-equal '(12 . 21))))

  (it "returns nil away from any chip"
    (with-temp-buffer
      (insert "  ")
      (expect (board--chip-bounds 1) :to-be nil)))

  (it "paints the body background and the edge foregrounds"
    (with-temp-buffer
      (insert (board--labels-cell board-tests--sample-pin 'right))
      (board--apply-hover 1 12)
      (let ((hover-color (face-attribute 'board-hover :background nil t)))
        (expect (mapcar (lambda (overlay) (overlay-get overlay 'face))
                  board--hover-overlays)
          :to-equal (list (list :background hover-color)
                      (list :foreground hover-color)
                      (list :foreground hover-color))))
      (board--clear-hover)
      (expect board--hover-overlays :to-be nil)))

  (it "binds mouse movement in board-mode"
    (expect (keymap-lookup board-mode-map "<mouse-movement>")
      :to-be #'board-follow-mouse)))

(describe "pin interaction"
  (it "navigates forward and backward between chips"
    (with-temp-buffer
      (insert (board--labels-cell board-tests--sample-pin 'right))
      (goto-char (point-min))
      (board-next-chip)
      (expect (point) :to-equal 12)
      (board-next-chip)
      (expect (point) :to-equal 21)
      (board-previous-chip)
      (expect (point) :to-equal 12)))

  (it "highlights the chip reached by navigation"
    (with-temp-buffer
      (insert (board--labels-cell board-tests--sample-pin 'right))
      (goto-char (point-min))
      (board-next-chip)
      (expect (length board--hover-overlays) :to-equal 3)))

  (it "echoes the chip description at point"
    (with-temp-buffer
      (insert (board--labels-cell board-tests--sample-pin 'right))
      (goto-char (+ (point-min) 2))
      (spy-on 'message)
      (board-describe-pin)
      (expect 'message :to-have-been-called-with "%s" "Pin 5 · ADC1/A4 · adc")))

  (it "describes the chip at point for eldoc"
    (with-temp-buffer
      (insert (board--labels-cell board-tests--sample-pin 'right))
      (goto-char (+ (point-min) 2))
      (let (told)
        (board--eldoc-at-point (lambda (text) (setq told text)))
        (expect told :to-equal "Pin 5 · ADC1/A4 · adc"))))

  (it "indexes one imenu entry per pin"
    (with-temp-buffer
      (insert (board--labels-cell board-tests--sample-pin 'right) " "
        (board--labels-cell '(:number 14 :labels ("VBUS")) 'right))
      (expect (board--imenu-create-index)
        :to-equal '(("Pin 5 (ADC1/A4)" . 1) ("Pin 14 (VBUS)" . 37)))))

  (it "binds chip and mode keys"
    (expect (keymap-lookup board-chip-map "RET") :to-be #'board-describe-pin)
    (expect (keymap-lookup board-chip-map "<mouse-1>") :to-be #'board-describe-pin)
    (expect (keymap-lookup board-mode-map "TAB") :to-be #'board-next-chip)
    (expect (keymap-lookup board-mode-map "<backtab>") :to-be #'board-previous-chip)))

(describe "M-x visibility"
  (it "hides the mode command from M-x"
    (expect (get 'board-mode 'completion-predicate) :to-be #'ignore))

  (it "restricts buffer commands to board-mode"
    (dolist (command '(board-switch board-describe-pin
                        board-next-chip board-previous-chip board-follow-mouse))
      (expect (command-modes command) :to-equal '(board-mode)))))

(describe "board-mode"
  (it "hides the cursor"
    (with-temp-buffer
      (board-mode)
      (expect cursor-type :to-be nil)
      (expect cursor-in-non-selected-windows :to-be nil)))

  (it "keeps the display geometry honest: no wrapping, no extra line pixels"
    (with-temp-buffer
      (board-mode)
      (expect truncate-lines :to-be-truthy)
      (expect line-spacing :to-equal 0)))

  (it "refits when the window configuration changes"
    (with-temp-buffer
      (board-mode)
      (expect (memq #'board--refit-if-window-changed
                window-configuration-change-hook)
        :to-be-truthy))))

(describe "board--display-window"
  (it "searches every frame, so a selected child frame cannot hijack layout"
    (spy-on 'get-buffer-window :and-call-through)
    (board--display-window)
    (expect 'get-buffer-window
      :to-have-been-called-with board-buffer-name t)))

(describe "board-switch"
  (it "signals a user-error for an unknown board"
    (expect (board-switch 'no_such_board) :to-throw 'user-error))

  (it "is bound to / in board-mode"
    (expect (keymap-lookup board-mode-map "/") :to-be #'board-switch)))

(describe "board--label-chip"
  (it "keeps slant edges even at zero spacing"
    (let ((rendered (with-temp-buffer
                      (vui-render (board--diagram
                                    (board--lookup 'xiao_esp32s3)
                                    0)
                        (current-buffer))
                      (buffer-string))))
      (expect (string-search "◥" rendered) :to-be-truthy))))

(describe "board--distribute"
  (it "spends the whole budget when it fits under the cap"
    (let ((gaps (board--distribute 27 30 4)))
      (expect (apply #'+ gaps) :to-equal 27)
      (expect (length gaps) :to-equal 30)
      (expect (seq-max gaps) :to-equal 1)))

  (it "sinks the short-changed pairs to the bottom of the board"
    (let ((gaps (board--distribute 27 30 4)))
      (expect (seq-take gaps 27) :to-equal (make-list 27 1))
      (expect (seq-drop gaps 27) :to-equal '(0 0 0))))

  (it "caps every gap at the preferred spacing"
    (expect (board--distribute 100 6 4) :to-equal '(4 4 4 4 4 4)))

  (it "spreads a partial remainder evenly instead of piling it up"
    (let ((gaps (board--distribute 8 6 4)))
      (expect (apply #'+ gaps) :to-equal 8)
      (expect (- (seq-max gaps) (seq-min gaps)) :to-equal 1)))

  (it "returns nil for a single-pin board with no gaps"
    (expect (board--distribute 5 0 4) :to-be nil)))

(describe "board-debug"
  (it "reports the window size and every spacing candidate's verdict"
    (with-temp-buffer
      (setq-local board--current (board--lookup 'xiao_esp32s3))
      (cl-letf (((symbol-function 'get-buffer-window)
                  (lambda (&rest _) (selected-window))))
        (let ((report (board-debug)))
          (expect report :to-match "window [0-9]+×[0-9]+")
          (expect report :to-match "dense [0-9]+×[0-9]+")
          (expect report :to-match "spare")
          (expect report :to-match "fits\\|OVER"))))))

(describe "board-toggle-label-style"
  (it "flips the style and re-shows the current board"
    (spy-on 'board-show)
    (let ((board-label-style 'zephyr)
           (board--current-key 'xiao_esp32s3))
      (board-toggle-label-style)
      (expect board-label-style :to-be 'arduino)
      (expect 'board-show :to-have-been-called))))

(describe "board-toggle-legend"
  (it "toggles the legend and refreshes"
    (spy-on 'vui-refresh)
    (let ((board-show-legend t))
      (board-toggle-legend)
      (expect board-show-legend :to-be nil)
      (expect 'vui-refresh :to-have-been-called))))

(provide 'board-tests)

;;; board-tests.el ends here
