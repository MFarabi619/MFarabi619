;;; west-tests.el --- Buttercup tests for west.el -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:        emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'ert-x)
(require 'west)

(buttercup-define-matcher-for-binary-function
    :to-be-file-equal file-equal-p
  :expect-match-phrase    "Expected `%A' to refer to the same file as `%B', but it was `%a'."
  :expect-mismatch-phrase "Expected `%A' not to refer to the same file as `%B', but it did.")

(describe "west-vc-root"
  (it "finds the repo when .git is present"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (make-directory ".git")
        (expect (west-vc-root) :to-be-file-equal dir))))

  (it "returns nil outside a repo"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (expect (west-vc-root) :not :to-be-truthy)))))

(describe "west-vc-in-git-repo-p"
  (it "is non-nil inside a repo"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (make-directory ".git")
        (expect (west-vc-in-git-repo-p))))))

(describe "west-projectile-root"
  (it "finds the project when .git is present"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (make-directory ".git")
        (expect (west-projectile-root) :to-be-file-equal dir))))

  (it "returns nil outside a project"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (expect (west-projectile-root) :not :to-be-truthy)))))

(describe "west-projectile-in-project-p"
  (it "is non-nil inside a project"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (make-directory ".git")
        (expect (west-projectile-in-project-p))))))

(describe "west-workspace-root"
  (it "finds the workspace when .west is present"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (make-directory ".west")
        (expect (west-workspace-root) :to-be-file-equal dir))))

  (it "returns nil outside a workspace"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (expect (west-workspace-root) :not :to-be-truthy)))))

(describe "west-in-workspace-p"
  (it "is non-nil inside a workspace"
    (ert-with-temp-directory dir
      (let ((default-directory dir))
        (make-directory ".west")
        (expect (west-in-workspace-p))))))

(describe "west-topdir"
  (it "returns the path from west topdir's stdout"
    (spy-on 'process-lines :and-return-value '("/some/workspace"))
    (expect (west-topdir) :to-equal "/some/workspace"))

  (it "invokes west with the topdir subcommand"
    (spy-on 'process-lines :and-return-value '("/x"))
    (west-topdir)
    (expect 'process-lines :to-have-been-called-with "west" "topdir")))

(describe "west--parse-config-line"
  (it "splits on the first equals sign, preserving subsequent equals signs in the value"
    (expect (west--parse-config-line "manifest.path=.")
            :to-equal '("manifest.path" . "."))
    (expect (west--parse-config-line "alias.menuconfig=build -p=never")
            :to-equal '("alias.menuconfig" . "build -p=never"))))

(describe "west-config"
  (it "returns parsed config from west config -l"
    (spy-on 'process-lines :and-return-value
            '("manifest.path=." "zephyr.base=zephyrproject/zephyr"))
    (expect (west-config) :to-equal
            '(("manifest.path" . ".")
              ("zephyr.base" . "zephyrproject/zephyr"))))

  (it "invokes west with config -l"
    (spy-on 'process-lines :and-return-value '("x=y"))
    (west-config)
    (expect 'process-lines :to-have-been-called-with "west" "config" "-l")))

(describe "west--parse-list-line"
  (it "parses a tab-separated project record into a plist"
    (expect (west--parse-list-line "zephyr\tzephyrproject/zephyr\t5c5f97c\thttps://x/y")
            :to-equal '(:name "zephyr"
                        :path "zephyrproject/zephyr"
                        :revision "5c5f97c"
                        :url "https://x/y"))))

(describe "west-list"
  (it "returns a list of parsed project records"
    (spy-on 'process-lines :and-return-value
            '("a\tb\tc\td" "e\tf\tg\th"))
    (expect (west-list) :to-equal
            '((:name "a" :path "b" :revision "c" :url "d")
              (:name "e" :path "f" :revision "g" :url "h"))))

  (it "invokes west list with a tab-separated format string"
    (spy-on 'process-lines :and-return-value '())
    (west-list)
    (expect 'process-lines :to-have-been-called-with
            "west" "list" "-f" "{name}\t{path}\t{revision}\t{url}")))

(describe "west--parse-version"
  (it "strips the \"West version: \" prefix when present, returns the line unchanged when absent"
    (expect (west--parse-version "West version: v1.5.0") :to-equal "v1.5.0")
    (expect (west--parse-version "v1.5.0") :to-equal "v1.5.0")))

(describe "west-version"
  (it "returns the parsed version from west --version"
    (spy-on 'process-lines :and-return-value '("West version: v1.5.0"))
    (expect (west-version) :to-equal "v1.5.0"))

  (it "invokes west with --version"
    (spy-on 'process-lines :and-return-value '("West version: v1.0"))
    (west-version)
    (expect 'process-lines :to-have-been-called-with "west" "--version")))

(describe "west-boards"
  (it "returns the list of board names from west boards"
    (spy-on 'process-lines :and-return-value '("walter" "xiao_esp32s3" "qemu_riscv32"))
    (expect (west-boards) :to-equal '("walter" "xiao_esp32s3" "qemu_riscv32")))

  (it "invokes west with boards"
    (spy-on 'process-lines :and-return-value '())
    (west-boards)
    (expect 'process-lines :to-have-been-called-with "west" "boards")))

(describe "west-update"
  (it "compiles `west update'"
    (spy-on 'compile)
    (west-update)
    (expect 'compile :to-have-been-called-with "west update"))

  (it "isolates output into a `*west:update*' buffer"
    (let (captured)
      (spy-on 'compile :and-call-fake
              (lambda (&rest _)
                (setq captured (funcall compilation-buffer-name-function nil))))
      (west-update)
      (expect captured :to-equal "*west:update*"))))

(describe "west-manifest-path"
  (it "defaults to <workspace>/west.yml when neither manifest.path nor manifest.file is set"
    (spy-on 'west-config :and-return-value nil)
    (expect (west-manifest-path "/some/ws/") :to-equal "/some/ws/west.yml"))

  (it "honors a configured manifest.file"
    (spy-on 'west-config :and-return-value
            '(("manifest.file" . "manifest.yml")))
    (expect (west-manifest-path "/some/ws/") :to-equal "/some/ws/manifest.yml"))

  (it "joins manifest.path and manifest.file when both are set"
    (spy-on 'west-config :and-return-value
            '(("manifest.path" . "manifests")
              ("manifest.file" . "my.yml")))
    (expect (west-manifest-path "/some/ws/")
            :to-equal "/some/ws/manifests/my.yml"))

  (it "returns nil when no workspace is detected"
    (spy-on 'west-config :and-return-value nil)
    (spy-on 'west-workspace-root :and-return-value nil)
    (expect (west-manifest-path) :not :to-be-truthy)))

(describe "west-manifest"
  (it "parses a manifest file into a hash table"
    (ert-with-temp-directory dir
      (let ((manifest (expand-file-name "manifest.yml" dir)))
        (write-region "manifest:\n  self:\n    import:\n      - apps/firmware/west.yml\n      - apps/nuttx-zig/west.yml\n"
                      nil manifest)
        (let ((parsed (west-manifest manifest)))
          (expect (hash-table-p parsed))
          (expect (gethash 'manifest parsed))))))

  (it "returns nil when the manifest file does not exist"
    (expect (west-manifest "/does/not/exist.yml") :not :to-be-truthy)))

(describe "west-manifest-self-imports"
  (it "returns the list of import paths under manifest.self.import"
    (ert-with-temp-directory dir
      (let ((manifest (expand-file-name "manifest.yml" dir)))
        (write-region "manifest:\n  self:\n    import:\n      - apps/firmware/west.yml\n      - apps/nuttx-zig/west.yml\n"
                      nil manifest)
        (expect (west-manifest-self-imports (west-manifest manifest))
                :to-equal '("apps/firmware/west.yml" "apps/nuttx-zig/west.yml")))))

  (it "wraps a single string import in a list"
    (ert-with-temp-directory dir
      (let ((manifest (expand-file-name "manifest.yml" dir)))
        (write-region "manifest:\n  self:\n    import: apps/firmware/west.yml\n" nil manifest)
        (expect (west-manifest-self-imports (west-manifest manifest))
                :to-equal '("apps/firmware/west.yml")))))

  (it "returns nil when self.import is absent"
    (ert-with-temp-directory dir
      (let ((manifest (expand-file-name "manifest.yml" dir)))
        (write-region "manifest:\n  projects: []\n" nil manifest)
        (expect (west-manifest-self-imports (west-manifest manifest)) :not :to-be-truthy)))))

(describe "west-manifest-projects"
  (it "returns a list of project plists with name/path/revision/url"
    (ert-with-temp-directory dir
      (let ((manifest (expand-file-name "manifest.yml" dir)))
        (write-region "manifest:\n  projects:\n    - name: zephyr\n      path: zephyrproject/zephyr\n      revision: 5c5f97c\n      url: https://github.com/zephyrproject-rtos/zephyr\n    - name: zephyr-lang-rust\n      path: zephyrproject/modules/lang/rust\n      revision: abc123\n      remote: zephyrproject\n"
                      nil manifest)
        (let ((projects (west-manifest-projects (west-manifest manifest))))
          (expect (length projects) :to-equal 2)
          (expect (plist-get (nth 0 projects) :name) :to-equal "zephyr")
          (expect (plist-get (nth 0 projects) :path) :to-equal "zephyrproject/zephyr")
          (expect (plist-get (nth 1 projects) :remote) :to-equal "zephyrproject"))))))

(describe "west-manifest-apps"
  :var (dir manifest)
  (before-each
    (spy-on 'west-config :and-return-value nil)
    (setq dir (make-temp-file "west-test-" t))
    (setq manifest (expand-file-name "west.yml" dir))
    (make-directory (expand-file-name ".west" dir))
    (write-region "manifest:\n  self:\n    import:\n      - apps/firmware/west.yml\n      - apps/nuttx-zig/west.yml\n"
                  nil manifest))
  (after-each (delete-directory dir t))

  (it "derives app name and path from each self.import entry"
    (let ((apps (west-manifest-apps dir)))
      (expect (length apps) :to-equal 2)
      (expect (plist-get (nth 0 apps) :name) :to-equal "firmware")
      (expect (plist-get (nth 1 apps) :name) :to-equal "nuttx-zig")
      (expect (plist-get (nth 0 apps) :path) :to-equal
              (expand-file-name "apps/firmware/" dir))
      (expect (plist-get (nth 0 apps) :manifest) :to-equal
              (expand-file-name "apps/firmware/west.yml" dir))))

  (it "returns nil when the workspace has no manifest"
    (delete-file manifest)
    (expect (west-manifest-apps dir) :not :to-be-truthy))

  (it "resolves self.import paths relative to the manifest repository directory"
    (delete-file manifest)
    (let* ((repo-dir (expand-file-name "manifests/" dir))
           (repo-manifest (expand-file-name "west.yml" repo-dir)))
      (make-directory repo-dir)
      (write-region "manifest:\n  self:\n    import:\n      - ../apps/firmware/west.yml\n"
                    nil repo-manifest)
      (spy-on 'west-config :and-return-value
              '(("manifest.path" . "manifests")
                ("manifest.file" . "west.yml")))
      (let ((apps (west-manifest-apps dir)))
        (expect (length apps) :to-equal 1)
        (expect (plist-get (car apps) :path) :to-equal
                (expand-file-name "apps/firmware/" dir))
        (expect (plist-get (car apps) :manifest) :to-equal
                (expand-file-name "apps/firmware/west.yml" dir))))))

(describe "against example-application (real-world integration)"
  :var (example)
  (before-each
    (setq example (expand-file-name "~/workspace/example-application/"))
    (assume (file-directory-p example)
            "example-application not cloned at ~/workspace/example-application/"))

  (it "parses west.yml into a manifest hash table"
    (let ((parsed (west-manifest (concat example "west.yml"))))
      (expect (hash-table-p parsed))
      (expect (gethash 'manifest parsed))))

  (it "returns nil for self.import (workspace-IS-module pattern, no self.import declared)"
    (expect (west-manifest-self-imports
             (west-manifest (concat example "west.yml")))
            :not :to-be-truthy))

  (it "declares one top-level project (zephyr) in the manifest"
    (expect (length (west-manifest-projects
                     (west-manifest (concat example "west.yml"))))
            :to-equal 1)))

;;; west-tests.el ends here
