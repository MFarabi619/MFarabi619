;;; zephyr-test.el --- Buttercup tests for zephyr.el  -*- lexical-binding: t; -*-

;;; Commentary:
;; Run from CLI:        emacs --batch -L . -l buttercup -f buttercup-run-discover

;;; Code:

(require 'buttercup)
(require 'ert-x)
(require 'zephyr)

(buttercup-define-matcher-for-binary-function
    :to-be-file-equal file-equal-p
  :expect-match-phrase    "Expected `%A' to refer to the same file as `%B', but it was `%a'."
  :expect-mismatch-phrase "Expected `%A' not to refer to the same file as `%B', but it did.")

(describe "zephyr-base"
  (it "honors ZEPHYR_BASE env var when set"
    (with-environment-variables (("ZEPHYR_BASE" "/explicit/zephyr"))
      (expect (zephyr-base) :to-equal "/explicit/zephyr")))

  (it "falls back to <workspace>/zephyrproject/zephyr/ when env var is unset"
    (with-environment-variables (("ZEPHYR_BASE" nil))
      (expect (zephyr-base "/some/ws/") :to-equal "/some/ws/zephyrproject/zephyr/")))

  (it "returns nil when no workspace exists and env var is unset"
    (with-environment-variables (("ZEPHYR_BASE" nil))
      (let ((default-directory "/"))
        (expect (zephyr-base) :not :to-be-truthy)))))

(describe "zephyr-version"
  (it "reads and trims the VERSION file"
    (ert-with-temp-directory dir
      (write-region "v1.5.0\n" nil (expand-file-name "VERSION" dir))
      (expect (zephyr-version dir) :to-equal "v1.5.0")))

  (it "returns nil when no VERSION file exists"
    (ert-with-temp-directory dir
      (expect (zephyr-version dir) :not :to-be-truthy))))

(describe "zephyr--cache-load and zephyr--cache-save"
  (it "round-trips a Lisp value through the disk cache"
    (ert-with-temp-directory dir
      (let ((zephyr-cache-dir dir)
            (data (list :version "v1.0" :data '((:id "a") (:id "b")))))
        (zephyr--cache-save "thing" data)
        (expect (zephyr--cache-load "thing") :to-equal data))))

  (it "returns nil when the cache file does not exist"
    (ert-with-temp-directory dir
      (let ((zephyr-cache-dir dir))
        (expect (zephyr--cache-load "missing") :not :to-be-truthy)))))

(describe "zephyr-boards"
  :var (base)
  (before-each
    (setq base (file-name-as-directory (make-temp-file "zephyr-test-" t)))
    (make-directory (expand-file-name "boards/vendor1/board1" base) t)
    (make-directory (expand-file-name "boards/vendor1/board2" base) t)
    (write-region "identifier: board1/socA/core1\nname: Board One\narch: arm\nvendor: vendor1\n"
                  nil (expand-file-name "boards/vendor1/board1/board1.yaml" base))
    (write-region "identifier: board2/socB/core1\nname: Board Two\narch: riscv\nvendor: vendor1\n"
                  nil (expand-file-name "boards/vendor1/board2/board2.yaml" base))
    (write-region "foo: bar\n"
                  nil (expand-file-name "boards/vendor1/board1/notes.yaml" base)))
  (after-each (delete-directory base t))

  (it "parses every board YAML under the boards/ tree"
    (expect (length (zephyr-boards base)) :to-equal 2))

  (it "exposes :id :name :arch :vendor for each board"
    (let* ((boards (zephyr-boards base))
           (by-id (sort boards (lambda (a b) (string< (plist-get a :id)
                                                       (plist-get b :id))))))
      (expect (plist-get (nth 0 by-id) :id)     :to-equal "board1/socA/core1")
      (expect (plist-get (nth 0 by-id) :name)   :to-equal "Board One")
      (expect (plist-get (nth 0 by-id) :arch)   :to-equal "arm")
      (expect (plist-get (nth 0 by-id) :vendor) :to-equal "vendor1")
      (expect (plist-get (nth 1 by-id) :arch)   :to-equal "riscv")))

  (it "filters out YAML files that lack an identifier field"
    (expect (seq-every-p (lambda (b) (plist-get b :id)) (zephyr-boards base))))

  (it "returns nil when no boards/ directory exists"
    (ert-with-temp-directory empty
      (expect (zephyr-boards empty) :not :to-be-truthy))))

(describe "zephyr-sdk-path"
  :var (dir sdk)
  (before-each
    (setq dir (make-temp-file "zephyr-test-" t))
    (setq sdk (expand-file-name "zephyr-sdk-1.5.0" dir))
    (make-directory sdk)
    (write-region "1.5.0" nil (expand-file-name "sdk_version" sdk)))
  (after-each (delete-directory dir t))

  (it "returns ZEPHYR_SDK_INSTALL_DIR when set"
    (with-environment-variables (("ZEPHYR_SDK_INSTALL_DIR" "/explicit/sdk"))
      (expect (zephyr-sdk-path) :to-equal "/explicit/sdk")))

  (it "discovers an SDK via search paths when the env var is unset"
    (with-environment-variables (("ZEPHYR_SDK_INSTALL_DIR" nil))
      (let ((zephyr-sdk-search-paths (list (concat dir "/zephyr-sdk-*"))))
        (expect (zephyr-sdk-path) :to-be-file-equal sdk))))

  (it "returns nil when no SDK is found anywhere"
    (with-environment-variables (("ZEPHYR_SDK_INSTALL_DIR" nil))
      (let ((zephyr-sdk-search-paths nil))
        (expect (zephyr-sdk-path) :not :to-be-truthy))))

  (it "prefers the highest version when multiple SDKs are found"
    (let ((sdk-old (expand-file-name "zephyr-sdk-0.16.5" dir))
          (sdk-new (expand-file-name "zephyr-sdk-2.0.0" dir)))
      (make-directory sdk-old)
      (make-directory sdk-new)
      (write-region "0.16.5" nil (expand-file-name "sdk_version" sdk-old))
      (write-region "2.0.0"  nil (expand-file-name "sdk_version" sdk-new))
      (with-environment-variables (("ZEPHYR_SDK_INSTALL_DIR" nil))
        (let ((zephyr-sdk-search-paths (list (concat dir "/zephyr-sdk-*"))))
          (expect (zephyr-sdk-path) :to-be-file-equal sdk-new))))))

(describe "zephyr-sdk-version"
  (it "reads and trims the sdk_version file at the given path"
    (ert-with-temp-directory dir
      (write-region "1.5.0\n" nil (expand-file-name "sdk_version" dir))
      (expect (zephyr-sdk-version dir) :to-equal "1.5.0")))

  (it "returns nil when no sdk_version file exists"
    (ert-with-temp-directory dir
      (expect (zephyr-sdk-version dir) :not :to-be-truthy))))

(describe "zephyr-sdk-toolchains"
  (it "returns toolchain subdirectory names from the given SDK path"
    (ert-with-temp-directory dir
      (make-directory (expand-file-name "arm-zephyr-eabi" dir))
      (make-directory (expand-file-name "riscv64-zephyr-elf" dir))
      (make-directory (expand-file-name "xtensa-espressif_esp32s3_zephyr-elf" dir))
      (expect (zephyr-sdk-toolchains dir)
              :to-have-same-items-as
              '("arm-zephyr-eabi"
                "riscv64-zephyr-elf"
                "xtensa-espressif_esp32s3_zephyr-elf"))))

  (it "excludes non-toolchain subdirectories"
    (ert-with-temp-directory dir
      (make-directory (expand-file-name "arm-zephyr-eabi" dir))
      (make-directory (expand-file-name "cmake" dir))
      (make-directory (expand-file-name "hosttools" dir))
      (expect (zephyr-sdk-toolchains dir) :not :to-contain "cmake")
      (expect (zephyr-sdk-toolchains dir) :not :to-contain "hosttools"))))

(describe "zephyr-toolchain-variant"
  (it "honors ZEPHYR_TOOLCHAIN_VARIANT env var when set"
    (with-environment-variables (("ZEPHYR_TOOLCHAIN_VARIANT" "gnuarmemb"))
      (expect (zephyr-toolchain-variant) :to-equal "gnuarmemb")))

  (it "defaults to \"zephyr\" when the env var is unset"
    (with-environment-variables (("ZEPHYR_TOOLCHAIN_VARIANT" nil))
      (expect (zephyr-toolchain-variant) :to-equal "zephyr"))))

(describe "zephyr-board"
  (it "honors BOARD env var when set"
    (with-environment-variables (("BOARD" "walter/esp32s3/procpu"))
      (expect (zephyr-board) :to-equal "walter/esp32s3/procpu")))

  (it "falls back to .west/config build.board when env is unset"
    (with-environment-variables (("BOARD" nil))
      (spy-on 'west-config :and-return-value
              '(("manifest.path" . ".") ("build.board" . "qemu_riscv32")))
      (expect (zephyr-board) :to-equal "qemu_riscv32")))

  (it "returns nil when neither env nor config provide a value"
    (with-environment-variables (("BOARD" nil))
      (spy-on 'west-config :and-return-value '(("manifest.path" . ".")))
      (expect (zephyr-board) :not :to-be-truthy))))

(describe "zephyr-shield"
  (it "returns nil when SHIELD env is unset"
    (with-environment-variables (("SHIELD" nil))
      (expect (zephyr-shield) :not :to-be-truthy)))

  (it "splits a semicolon-separated SHIELD value into a list"
    (with-environment-variables (("SHIELD" "x_nucleo_iks01a3;adafruit_winc1500"))
      (expect (zephyr-shield)
              :to-equal '("x_nucleo_iks01a3" "adafruit_winc1500"))))

  (it "returns a single-element list for a single SHIELD value"
    (with-environment-variables (("SHIELD" "x_nucleo_iks01a3"))
      (expect (zephyr-shield) :to-equal '("x_nucleo_iks01a3"))))

  (it "returns nil when SHIELD is empty or whitespace"
    (with-environment-variables (("SHIELD" ""))
      (expect (zephyr-shield) :not :to-be-truthy))))

(describe "zephyr-snippet"
  (it "returns nil when SNIPPET env is unset"
    (with-environment-variables (("SNIPPET" nil))
      (expect (zephyr-snippet) :not :to-be-truthy)))

  (it "splits a semicolon-separated SNIPPET value into a list"
    (with-environment-variables (("SNIPPET" "cdc-acm-console;rtt-console"))
      (expect (zephyr-snippet) :to-equal '("cdc-acm-console" "rtt-console")))))

(describe "named *-roots accessors"
  (it "zephyr-board-roots reads BOARD_ROOT (env-only, no implicit base)"
    (with-environment-variables (("BOARD_ROOT" (mapconcat #'identity '("/x" "/y") path-separator)))
      (expect (zephyr-board-roots) :to-equal '("/x" "/y"))))

  (it "zephyr-soc-roots reads SOC_ROOT"
    (with-environment-variables (("SOC_ROOT" "/x"))
      (expect (zephyr-soc-roots) :to-equal '("/x"))))

  (it "zephyr-snippet-roots reads SNIPPET_ROOT"
    (with-environment-variables (("SNIPPET_ROOT" "/x"))
      (expect (zephyr-snippet-roots) :to-equal '("/x"))))

  (it "returns nil when the env var is unset"
    (with-environment-variables (("BOARD_ROOT" nil))
      (expect (zephyr-board-roots) :not :to-be-truthy))))

(describe "zephyr-modules"
  (it "splits ZEPHYR_MODULES into a list of paths"
    (with-environment-variables (("ZEPHYR_MODULES" (mapconcat #'identity '("/m1" "/m2") path-separator)))
      (expect (zephyr-modules) :to-equal '("/m1" "/m2"))))

  (it "returns nil when unset"
    (with-environment-variables (("ZEPHYR_MODULES" nil))
      (expect (zephyr-modules) :not :to-be-truthy))))

(describe "zephyr-extra-modules"
  (it "splits EXTRA_ZEPHYR_MODULES into a list of paths"
    (with-environment-variables (("EXTRA_ZEPHYR_MODULES" (mapconcat #'identity '("/e1" "/e2") path-separator)))
      (expect (zephyr-extra-modules) :to-equal '("/e1" "/e2"))))

  (it "returns nil when unset"
    (with-environment-variables (("EXTRA_ZEPHYR_MODULES" nil))
      (expect (zephyr-extra-modules) :not :to-be-truthy))))

(describe "zephyr--cmake-arg"
  (it "returns nil when value is nil"
    (expect (zephyr--cmake-arg "BOARD" nil) :not :to-be-truthy))

  (it "formats a single string value"
    (expect (zephyr--cmake-arg "BOARD" "walter/esp32s3/procpu")
            :to-equal "-DBOARD=walter/esp32s3/procpu"))

  (it "joins list values with semicolons (CMake list syntax)"
    (expect (zephyr--cmake-arg "BOARD_ROOT" '("/x" "/y" "/z"))
            :to-equal "-DBOARD_ROOT=/x;/y;/z")))

(describe "zephyr-cmake-args"
  (before-each
    (spy-on 'zephyr-board             :and-return-value nil)
    (spy-on 'zephyr-shield            :and-return-value nil)
    (spy-on 'zephyr-snippet           :and-return-value nil)
    (spy-on 'zephyr-toolchain-variant :and-return-value nil)
    (spy-on 'zephyr-sdk-path          :and-return-value nil)
    (spy-on 'zephyr-board-roots       :and-return-value nil)
    (spy-on 'zephyr-shield-roots      :and-return-value nil)
    (spy-on 'zephyr-snippet-roots     :and-return-value nil)
    (spy-on 'zephyr-soc-roots         :and-return-value nil)
    (spy-on 'zephyr-arch-roots        :and-return-value nil)
    (spy-on 'zephyr-dts-roots         :and-return-value nil)
    (spy-on 'zephyr-modules           :and-return-value nil)
    (spy-on 'zephyr-extra-modules     :and-return-value nil))

  (it "returns nil when nothing is set anywhere"
    (expect (zephyr-cmake-args) :not :to-be-truthy))

  (it "emits -DBOARD from the :board override"
    (expect (zephyr-cmake-args '(:board "walter/esp32s3/procpu"))
            :to-equal '("-DBOARD=walter/esp32s3/procpu")))

  (it "emits -DSHIELD with semicolon-joined list"
    (expect (zephyr-cmake-args '(:shield ("x_nucleo_iks01a3" "adafruit_winc1500")))
            :to-equal '("-DSHIELD=x_nucleo_iks01a3;adafruit_winc1500")))

  (it "emits -DBOARD_ROOT with semicolon-joined list"
    (expect (zephyr-cmake-args '(:board-roots ("/extra/boards" "/other/boards")))
            :to-equal '("-DBOARD_ROOT=/extra/boards;/other/boards")))

  (it "emits multiple args in deterministic order"
    (expect (zephyr-cmake-args
             '(:board "walter/esp32s3/procpu"
               :sdk-path "/opt/zephyr-sdk"
               :board-roots ("/extra/boards")))
            :to-equal '("-DBOARD=walter/esp32s3/procpu"
                        "-DZEPHYR_SDK_INSTALL_DIR=/opt/zephyr-sdk"
                        "-DBOARD_ROOT=/extra/boards")))

  (it "uses env-derived values when no override is given"
    (spy-on 'zephyr-board :and-return-value "qemu_riscv32")
    (expect (zephyr-cmake-args)
            :to-equal '("-DBOARD=qemu_riscv32")))

  (it "lets an explicit override win over the env-derived value"
    (spy-on 'zephyr-board :and-return-value "qemu_riscv32")
    (expect (zephyr-cmake-args '(:board "walter/esp32s3/procpu"))
            :to-equal '("-DBOARD=walter/esp32s3/procpu")))

  (it "honors the toolchain-variant override"
    (expect (zephyr-cmake-args '(:toolchain-variant "gnuarmemb"))
            :to-equal '("-DZEPHYR_TOOLCHAIN_VARIANT=gnuarmemb"))))

(describe "zephyr-apps"
  :var (dir manifest fw-dir other-dir)
  (before-each
    (setq dir (make-temp-file "zephyr-test-" t))
    (setq manifest (expand-file-name "manifest.yml" dir))
    (setq fw-dir (expand-file-name "apps/firmware/" dir))
    (setq other-dir (expand-file-name "apps/other/" dir))
    (make-directory (expand-file-name ".west" dir))
    (make-directory fw-dir t)
    (make-directory other-dir t)
    (make-directory (expand-file-name "boards" fw-dir))
    (write-region "manifest:\n  self:\n    import:\n      - apps/firmware/west.yml\n      - apps/other/west.yml\n"
                  nil manifest)
    (write-region "" nil (expand-file-name "west.yml" fw-dir))
    (write-region "" nil (expand-file-name "west.yml" other-dir))
    (write-region "find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})\nproject(my_fw)\n"
                  nil (expand-file-name "CMakeLists.txt" fw-dir))
    (write-region "find_package(SomethingElse)\nproject(other)\n"
                  nil (expand-file-name "CMakeLists.txt" other-dir))
    (write-region "" nil (expand-file-name "boards/walter_procpu.conf" fw-dir))
    (write-region "" nil (expand-file-name "boards/qemu_riscv32.conf" fw-dir)))
  (after-each (delete-directory dir t))

  (it "filters out apps whose CMakeLists is not a Zephyr app"
    (let ((apps (zephyr-apps dir)))
      (expect (length apps) :to-equal 1)))

  (it "uses the project() name from CMakeLists.txt"
    (let ((apps (zephyr-apps dir)))
      (expect (plist-get (car apps) :name) :to-equal "my_fw")))

  (it "includes :path and :manifest from the workspace manifest"
    (let ((apps (zephyr-apps dir)))
      (expect (plist-get (car apps) :path)     :to-equal fw-dir)
      (expect (plist-get (car apps) :manifest) :to-equal
              (expand-file-name "west.yml" fw-dir))))

  (it "includes boards discovered from the app's boards/ directory"
    (let ((apps (zephyr-apps dir)))
      (expect (plist-get (car apps) :boards)
              :to-have-same-items-as '("walter_procpu" "qemu_riscv32"))))

  (it "returns nil when no workspace exists"
    (ert-with-temp-directory empty
      (expect (zephyr-apps empty) :not :to-be-truthy))))

;;; zephyr-test.el ends here
