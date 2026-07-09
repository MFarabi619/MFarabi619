;;; glb-mode-tests.el --- Buttercup tests for glb-mode.el  -*- lexical-binding: t; -*-

;;; Code:

(require 'buttercup)
(require 'glb-mode)

(buttercup-error-on-stale-elc)
(setq buttercup-stack-frame-style 'pretty)

(defun glb-tests--u32 (n)
  "Return N as a little-endian unsigned 32-bit unibyte string.
Encodes with the same bindat spec `glb-read-metadata' decodes with."
  (bindat-pack (bindat-type uint 32 t) n))

(defun glb-tests--make-glb (json)
  "Write a minimal version 2 .glb wrapping JSON to a temp file, return its path."
  (let* ((padded (concat json (make-string (% (- 4 (% (length json) 4)) 4) ?\s)))
         (file (make-temp-file "glb-test-" nil ".glb")))
    (with-temp-buffer
      (set-buffer-multibyte nil)
      (insert "glTF")
      (insert (glb-tests--u32 2))
      (insert (glb-tests--u32 (+ 12 8 (length padded))))
      (insert (glb-tests--u32 (length padded)))
      (insert "JSON")
      (insert padded)
      (write-region (point-min) (point-max) file nil 'nomsg))
    file))

(describe "auto-mode-alist"
  (it "routes .glb files to glb-mode"
    (expect (cdr (assoc "\\.glb\\'" auto-mode-alist)) :to-be 'glb-mode)))

(describe "glb-read-metadata"
  (it "parses the embedded glTF JSON of a version 2 glb"
    (let* ((file (glb-tests--make-glb
                  "{\"asset\":{\"version\":\"2.0\",\"generator\":\"cadrum\"},\
\"nodes\":[{\"name\":\"base\"}],\"meshes\":[{}],\"materials\":[{},{}]}"))
           (gltf (glb-read-metadata file)))
      (expect (alist-get 'generator (alist-get 'asset gltf)) :to-equal "cadrum")
      (expect (glb--count gltf 'materials) :to-equal 2)
      (expect (alist-get 'name (car (alist-get 'nodes gltf))) :to-equal "base")
      (delete-file file)))
  (it "rejects a file that is not a glb"
    (let ((file (make-temp-file "glb-test-" nil ".glb" "not a glb at all")))
      (expect (glb-read-metadata file) :to-throw 'user-error)
      (delete-file file))))

(provide 'glb-mode-tests)

;;; glb-mode-tests.el ends here
