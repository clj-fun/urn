(import extra/argparse arg)
(import lua/io io)
(import string)

(import urn/backend/markdown markdown)
(import urn/backend/writer writer)
(import urn/logger logger)

(defun docs (compiler args)
  (when (empty? (.> args :input))
    (logger/put-error! (.> compiler :log) "No inputs to generate documentation for.")
    (exit! 1))

  (for-each path (.> args :input)
    (when (= (string/sub path -5) ".lisp") (set! path (string/sub path 1 -6)))

    (let* [(lib (.> compiler :libCache path))
           (writer (writer/create))]
      (markdown/exported writer (.> lib :name) (.> lib :docs) (.> lib :scope :exported) (.> lib :scope))

      (with (handle (io/open (.. (.> args :docs) "/" (string/gsub path "/" ".") ".md") "w"))
        (self handle :write (writer/->string writer))
        (self handle :close)))))

(define task
  { :name "docs"
    :setup (lambda (spec)
             (arg/add-argument! spec '("--docs")
               :help    "Specify the folder to emit documentation to."
               :default nil
               :narg    1))
    :pred  (lambda (args) (/= nil (.> args :docs)))
    :run   docs })
