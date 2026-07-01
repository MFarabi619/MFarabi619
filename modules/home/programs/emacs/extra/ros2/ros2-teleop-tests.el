;;; ros2-teleop-tests.el --- Buttercup tests for ros2-teleop.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'ros2-teleop)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(describe "ros2-teleop--cells"
  (it "is a nine-cell grid in row-major order"
    (expect (length ros2-teleop--cells) :to-equal 9))

  (it "mirrors the upstream key, glyph, and (linear . angular) weights"
    (expect (nth 1 ros2-teleop--cells) :to-equal '("i" "🢁" 1.0 0.0))
    (expect (nth 3 ros2-teleop--cells) :to-equal '("j" "🢀" 0.0 1.0))
    (expect (nth 4 ros2-teleop--cells) :to-equal '("k" "○" 0.0 0.0))
    (expect (nth 7 ros2-teleop--cells) :to-equal '("," "🢃" -1.0 0.0))))

(describe "ros2-teleop--rows"
  (it "groups the cells into three rows of three"
    (let ((rows (ros2-teleop--rows)))
      (expect (length rows) :to-equal 3)
      (expect (mapcar #'length rows) :to-equal '(3 3 3))))

  (it "keeps the row-major key order across the rows"
    (let ((rows (ros2-teleop--rows)))
      (expect (mapcar (lambda (cell) (nth 0 cell)) (nth 0 rows)) :to-equal '("u" "i" "o"))
      (expect (mapcar (lambda (cell) (nth 0 cell)) (nth 1 rows)) :to-equal '("j" "k" "l"))
      (expect (mapcar (lambda (cell) (nth 0 cell)) (nth 2 rows)) :to-equal '("m" "," ".")))))

(describe "ros2-teleop--cell-for-key"
  (it "returns the cell bound to a grid key"
    (expect (ros2-teleop--cell-for-key "i") :to-equal '("i" "🢁" 1.0 0.0))
    (expect (ros2-teleop--cell-for-key "k") :to-equal '("k" "○" 0.0 0.0)))

  (it "returns nil for a key outside the grid"
    (expect (ros2-teleop--cell-for-key "z") :not :to-be-truthy)))

(describe "ros2-teleop--cell-active-p"
  (it "is non-nil only when the cell is the engaged key"
    (let ((forward-cell '("i" "🢁" 1.0 0.0)))
      (expect (ros2-teleop--cell-active-p forward-cell "i") :to-be-truthy)
      (expect (ros2-teleop--cell-active-p forward-cell "j") :not :to-be-truthy)))

  (it "is nil when nothing is engaged"
    (expect (ros2-teleop--cell-active-p '("i" "🢁" 1.0 0.0) nil) :not :to-be-truthy)))

(describe "ros2-teleop--cell-label"
  (it "renders a single \"ARROW KEY\" line so the cell stays in one table row"
    (expect (substring-no-properties (ros2-teleop--cell-label '("i" "🢁" 1.0 0.0) nil))
      :to-equal "🢁 i"))

  (it "lights the arrow only for the engaged key"
    (expect (get-text-property 0 'face (ros2-teleop--cell-label '("i" "🢁" 1.0 0.0) "i"))
      :to-equal 'ros2-teleop-active)
    (expect (get-text-property 0 'face (ros2-teleop--cell-label '("i" "🢁" 1.0 0.0) "j"))
      :to-equal 'ros2-teleop-arrow)))

(describe "ros2-teleop--table"
  (it "builds a unicode-bordered 3x3 vui-table"
    (let ((table (ros2-teleop--table nil)))
      (expect (vui-vnode-table-p table) :to-be-truthy)
      (expect (vui-vnode-table-border table) :to-equal :unicode)
      (expect (length (vui-vnode-table-rows table)) :to-equal 3)
      (expect (mapcar #'length (vui-vnode-table-rows table)) :to-equal '(3 3 3)))))

(describe "ros2-teleop-mode-map"
  (it "binds the drive keys, the SPC e-stop, and q, local to the teleop window"
    (expect (commandp (lookup-key ros2-teleop-mode-map "i")) :to-be-truthy)
    (expect (commandp (lookup-key ros2-teleop-mode-map ".")) :to-be-truthy)
    (expect (lookup-key ros2-teleop-mode-map (kbd "SPC")) :to-equal #'ros2-teleop-stop)
    (expect (lookup-key ros2-teleop-mode-map "q") :to-equal #'quit-window))

  (it "scopes `ros2-teleop-stop' to the teleop window, hiding it from global M-x"
    (expect (command-modes 'ros2-teleop-stop) :to-equal '(ros2-teleop-mode))))

;;; ros2-teleop-tests.el ends here
