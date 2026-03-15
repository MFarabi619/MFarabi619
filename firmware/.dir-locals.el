((nil
  . ((eval
      . (progn
          ;; These methods setup and then intercept RTT data events from
          ;; probe-rs, providing Log output directly in the REPL.
          (cl-defmethod dape-handle-event (conn (_event (eql probe-rs-rtt-data)) body)
            "When Probe.rs sends RTT messages, insert them into the REPL.
              CONN is the `dape-connection'.
              BODY is the contents of the event."
            (let ((data (plist-get body :data)))
              (dape--repl-insert (format "%s\n" data))))

          (cl-defmethod dape-handle-event (conn (_event (eql probe-rs-rtt-channel-config)) body)
            "When Probe.rs sends channel config info, send a request to let it know the 'terminal window' is open.
              CONN is the `dape-connection'.
              BODY is the contents of the event."
            (dape-request conn "rttWindowOpened"
                          '((channelNumber . 0)(windowIsOpen . t))))

          (setq dape-request-timeout 60
                target-root
                (or (locate-dominating-file default-directory ".dir-locals.el")
                    default-directory)
                target-binary "blinky"
                target-chip "esp32s3"
                target-architecture-triple "xtensa-esp32s3-none-elf"
                target-chip-svd-path (expand-file-name "esp32s3.svd"
                                                       target-root)
                target-binary-path (expand-file-name
                                    (format "target/%s/debug/examples/%s"
                                            target-architecture-triple
                                            target-binary)
                                    target-root))

          (add-to-list 'dape-configs
                       '(probe-rs modes (rust-mode)
                         port :autoport
                         host "localhost"
                         :chip target-chip
                         command "probe-rs"
                         :request "launch"
                         :type "probe-rs-debug"
                         :consoleLogLevel "Console"
                         :flashingConfig (:flashingEnabled t)
                         compile "cargo build -r --example=blinky"
                         command-args ("dap-server" "--port" :autoport)
                         :coreConfigs [(
                                        :coreIndex 0
                                        :rttEnabled t
                                        :programBinary target-binary-path
                                        :svdFile target-chip-svd-path
                                        :rttChannelFormats [(:channelNumber 0 :dataFormat "String" :showTimestamps t)])])))))))
