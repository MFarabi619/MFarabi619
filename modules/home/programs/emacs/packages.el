;; -*- no-byte-compile: t; -*-
;;; $DOOMDIR/packages.el

;; To install a package with Doom you must declare them here and run 'doom sync'
;; on the command line, then restart Emacs for the changes to take effect -- or
;; use 'M-x doom/reload'.

;; To install SOME-PACKAGE from MELPA, ELPA or emacsmirror:
;; (package! some-package)

;; To install a package directly from a remote git repo, you must specify a
;; `:recipe'. You'll find documentation on what `:recipe' accepts here:
;; https://github.com/radian-software/straight.el#the-recipe-format
;; (package! another-package
;;   :recipe (:host github :repo "username/repo"))

;; If the package you are trying to install does not contain a PACKAGENAME.el
;; file, or is located in a subdirectory of the repo, you'll need to specify
;; `:files' in the `:recipe':
;; (package! this-package
;;   :recipe (:host github :repo "username/repo"
;;            :files ("some-file.el" "src/lisp/*.el")))

;; If you'd like to disable a package included with Doom, you can do so here
;; with the `:disable' property:
;; (package! builtin-package :disable t)

;; You can override the recipe of a built in package without having to specify
;; all the properties for `:recipe'. These will inherit the rest of its recipe
;; from Doom or MELPA/ELPA/Emacsmirror:
;; (package! builtin-package :recipe (:nonrecursive t))
;; (package! builtin-package-2 :recipe (:repo "myfork/package"))

;; Specify a `:branch' to install a package from a particular branch or tag.
;; This is required for some packages whose default branch isn't 'master' (which
;; our package manager can't deal with; see radian-software/straight.el#279)
;; (package! builtin-package :recipe (:branch "develop"))

;; Use `:pin' to specify a particular commit to install.
;; (package! builtin-package :pin "1a2b3c4d5e")

;; Doom's packages are pinned to a specific commit and updated from release to
;; release. The `unpin!' macro allows you to unpin single packages...
;; (unpin! pinned-package)
;; ...or multiple packages
;; (unpin! pinned-package another-pinned-package)
;; ...Or *all* packages (NOT RECOMMENDED; will likely break things)
;; (unpin! t)

;; (package! org-pandoc-import
;;   :recipe (:host github
;;            :repo "tecosaur/org-pandoc-import"
;;            :files ("*.el" "filters" "preprocessors")))

;; (package! org-gcal)
;; (package! consult-gh)
;; (package! magit-todos)
;; (package! gptel :recipe (:nonrecursive t)) ;; on non-nix

;; (package! eee
;;   :recipe (:host github
;;            :repo "eval-exec/eee.el"
;;            :branch "main"
;;            :files (:defaults "*.el" "*.sh"))
;;   :pin "91f2c21b7730caa55a6277ae1240328d9b8a0657")

(package! kbd-mode
  :recipe (:host github
           :repo "kmonad/kbd-mode")
  :pin "f8951b2efc5c29954b0105a9e57e973515125b0d")

(package! llm-tool-collection
  :recipe (:host github
           :repo "skissue/llm-tool-collection")
  :pin "6d2765a16dc10af2e1d1911bcabf6d7f287e0434")

(package! ob-duckdb
  :recipe (:host github
           :repo "gggion/ob-duckdb"
           :files ("*.el"))
  :pin "d5b6df504e63f635512a57b23afd9a37683fca40")

;; FIXME: Cannot open load file: No such file or directory, hydra
;; https://github.com/l3kn/org-fc/issues/67
;; (package! org-fc
;;   :recipe (:host sourcehut
;;            :repo "l3kn/org-fc"
;;            :files (:defaults "awk" "demo.org"))
;;   :pin "22144b4c0714544e8415585a4eecd1b1b370ce22")
