(import urn/tools/simple    simple)
(import urn/tools/docs      docs)
(import urn/tools/repl      repl)
(import urn/tools/run       run)

(import urn/logger logger)
(import urn/logger/term term)
(import urn/backend/lua lua)

(import extra/argparse arg)
(import lua/basic (_G))
(import lua/os os)
(import string)

(define-native lib-loader)
(define-native root-scope)
(define-native scope/child)
(define-native scope/import!)

(let* [(spec (arg/create))
       (directory (with (dir (nth arg 0))
                    ;; Strip the two possible file names
                    (set! dir (string/gsub dir "urn/cli%.lisp$" ""))
                    (set! dir (string/gsub dir "urn/cli$" ""))
                    (set! dir (string/gsub dir "tacky/cli%.lua$" ""))

                    ;; Add a trailing "/" where needed
                    (when (and (/= dir "") (/= (string/char-at dir -1) "/"))
                      (set! dir (.. dir "/")))

                    ;; Remove leading "./"s
                    (while (= (string/sub dir 1 2) "./")
                      (set! dir (string/sub dir 3)))

                    dir))
       (paths (list
                "?"
                "?/init"
                (.. directory "lib/?")
                (.. directory "lib/?/init")))

       (tasks (list
                simple/warning
                simple/optimise
                simple/emit-lisp
                simple/emit-lua
                docs/task
                run/task
                repl/task))]
  (arg/add-help! spec)

  (arg/add-argument! spec '("--explain" "-e")
    :help    "Explain error messages in more detail.")

  (arg/add-argument! spec '("--time" "-t")
    :help    "Time how long each task takes to execute.")

  (arg/add-argument! spec '("--verbose" "-v")
    :help    "Make the output more verbose. Can be used multiple times"
    :many    true
    :default 0
    :action  (lambda (arg data) (.<! data (.> arg :name) (succ (or (.> data (.> arg :name)) 0)))))

  (arg/add-argument! spec '("--include" "-i")
    :help    "Add an additional argument to the include path."
    :many    true
    :narg    1
    :default '()
    :action  arg/add-action)

  (arg/add-argument! spec '("--prelude" "-p")
    :help    "A custom prelude path to use."
    :narg    1
    :default (.. directory "lib/prelude"))

  (arg/add-argument! spec '("--output" "--out" "-o")
    :help    "The destination to output to."
    :narg    1
    :default "out")

  (arg/add-argument! spec '("input")
    :help    "The file(s) to load."
    :var     "FILE"
    :narg    "*")

  ;; Setup the arguments for each task
  (for-each task tasks ((.> task :setup) spec))

  (let* [(args (arg/parse! spec))
         (logger (term/create
              (.> args :verbose)
              (.> args :explain)))]

    ;; Process include paths
    (for-each path (.> args :include)
      (set! path (string/gsub path "\\" "/"))
      (set! path (string/gsub path "^%./" ""))

      (unless (string/find path "%?")
        (set! path (.. path (if (= (string/char-at path -1) "/") "?" "/?"))))

      (push-cdr! paths path))

    (logger/put-verbose! logger (.. "Using path: " (pretty paths)))

    (if (nil? (.> args :input))
      (.<! args :repl true)
      (.<! args :emit-lua true))

    (with (compiler (struct
                     :log       logger
                     :paths     paths

                     :libEnv    (empty-struct)
                     :libMeta   (empty-struct)
                     :libs      '()
                     :libCache  (empty-struct)

                     :rootScope root-scope

                     :variables (empty-struct)
                     :states    (empty-struct)
                     :out       '()))

      ;; Add compileState
      (.<! compiler :compileState (lua/create-state (.> compiler :libMeta)))
      (.<! compiler :compileState :count 0)
      (.<! compiler :compileState :mappings (empty-struct))

      ;; Add globals
      (.<! compiler :global (setmetatable
                              (struct :_libs (.> compiler :libEnv))
                              (struct :__index _G)))

      ;; Store all builtin vars in the lookup
      (for-pairs (_ var) (.> compiler :rootScope :variables)
        (.<! compiler :variables (tostring var) var))

      (with (start (os/clock))
        (case (list (lib-loader compiler (.> args :prelude) false))
          [(false ?error-message)
           (logger/put-error! logger error-message)
           (exit! 1)]
          [(true ?prelude-vars)
           (.<! compiler :rootScope (scope/child (.> compiler :rootScope)))
           (for-pairs (name var) prelude-vars
             (scope/import! (.> compiler :rootScope) name var))

           (for-each input (.> args :input)
             (case (list (lib-loader compiler input false))
               [(false ?error-message)
                (logger/put-error! logger error-message)
                (exit! 1)]
               [_]))])
        (when (.> args :time)
          (print! (.. "parsing took " (- (os/clock) start)))))

      (for-each task tasks
        (when ((.> task :pred) args)
          (with (start (os/clock))
            ((.> task :run) compiler args)
            (when (.> args :time)
              (print! (.. (.> task :name) " took " (- (os/clock) start))))))))))
