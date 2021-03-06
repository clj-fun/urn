(import urn/analysis/nodes (builtins fast-any))
(import urn/analysis/pass (run-pass))
(import urn/analysis/tag/categories cat)
(import urn/backend/lua/escape ())
(import urn/backend/writer w)

(import string)

(defun truthy? (node)
  "Determine whether NODE is true. A more comprehensive implementation exists in the optimiser"
  :hidden
  (and (symbol? node) (= (.> builtins :true) (.> node :var))))

(define boring-categories
  "A lookup of all 'boring' which we will not emit node information for."
  { ;; Constant nodes
    :const true :quote true
    ;; Branch nodes
    :not true :cond true })

(defun compile-native (out meta)
  (with (ty (type meta))
    (cond
      [(= ty "var")
       ;; Create an alias to a variable
       (w/append! out (.> meta :contents))]

      [(or (= ty "expr") (= ty "stmt"))
       ;; Generate a custom function wrapper
       (w/append! out "function(")
       (for i 1 (.> meta :count) 1
         (unless (= i 1) (w/append! out ", "))
         (w/append! out (.. "v" (string->number i))))

       (when (.> meta :fold) (w/append! out ", ..."))
       (w/append! out ") ")

       ;; Return the value if required
       (cond
         [(= (.> meta :tag) "stmt")]
         [(.> meta :fold) (w/append! out "local t = ")]
         [true (w/append! out "return ")])

       ;; And create the template
       (for-each entry (.> meta :contents)
         (if (number? entry)
           (w/append! out (.. "v" (string->number entry)))
           (w/append! out entry)))

       (case (.> meta :fold)
         [nil]
         ["l"
          (w/append! out " for i = 1, _select('#', ...) do t = ")
          (for-each node (.> meta :contents)
            (case node
              [1 (w/append! out "t")]
              [2 (w/append! out "_select(i, ...)")]
              [string? (w/append! out node)]))
          (w/append! out " end return t")]
         ["r"
          (w/append! out " for i = _select('#', ...), 1, -1 do t = ")
          (for-each node (.> meta :contents)
            (case node
              [1 (w/append! out "_select(i, ...)")]
              [2 (w/append! out "t")]
              [string? (w/append! out node)]))
          (w/append! out " end return t")])

       (w/append! out " end")])))

(defun compile-expression (node out state ret)
  :hidden
  (let* [(cat-lookup (.> state :cat-lookup))
         (cat (.> cat-lookup node))
         (_ (unless cat
              (import urn/range r)
              (print! "Cannot find" (pretty node) (r/format-node node))))
         (cat-tag (.> cat :category))]
    (unless (.> boring-categories cat-tag) (w/push-node! out node))
    (case cat-tag
      ["const" (unless (= ret "")
                 (when ret (w/append! out ret))
                 (cond
                   [(symbol? node) (w/append! out (escape-var (.> node :var) state))]
                   [(string? node) (w/append! out (string/quoted (.> node :value)))]
                   [(number? node) (w/append! out (number->string (.> node :value)))]
                   [(key? node) (w/append! out (string/quoted (.> node :value)))] ;; TODO: Should this be a table instead? If so, can we make this more efficient?
                   [true (error! (.. "Unknown type: " (type node)))]))]

      ["lambda"
       (unless (= ret "")
         (when ret (w/append! out ret))
         (let* [(args (nth node 2))
                (variadic nil)
                (i 1)]

           ;; Build the argument list, looking for variadic arguments.
           ;; We stop when we find one: after all, we can't emit successive args
           (w/append! out "(function(")
           (while (and (<= i (# args)) (! variadic))
             (when (> i 1) (w/append! out ", "))
             (with (var (.> args i :var))
               (if (.> var :isVariadic)
                 (progn
                   (w/append! out "...")
                   (set! variadic i))
                 (w/append! out (escape-var var state))))
             (inc! i))
           (w/begin-block! out ")")

           (when variadic
             (with (args-var (escape-var (.> args variadic :var) state))
               (if (= variadic (# args))
                 ;; If it is the last argument then just pack it up into a list
                 (w/line! out (string/.. "local " args-var " = _pack(...) " args-var ".tag = \"list\""))
                 (with (remaining (- (# args) variadic))
                   ;; Otherwise everything is a tad more complicated. We first store the number
                   ;; of arguments to add to our variadic, as well as predeclaring all args
                   (w/line! out (.. "local _n = _select(\"#\", ...) - " (number->string remaining)))

                   (w/append! out (.. "local " args-var))
                   (for i (succ variadic) (# args) 1
                     (w/append! out ", ")
                     (w/append! out (escape-var (.> args i :var) state)))
                   (w/line! out)

                   (w/begin-block! out "if _n > 0 then")
                   ;; If we have something to insert into the variadic area then we pack and unpack
                   ;; the section. It might be more efficient to pack it and append/assign to the various
                   ;; regions, but that can be profiled later.
                   (w/append! out args-var)
                   (w/line! out " = { tag=\"list\", n=_n, _unpack(_pack(...), 1, _n)}")

                   (for i (succ variadic) (# args) 1
                     (w/append! out (escape-var (.> args i :var) state))
                     (when (< i (# args)) (w/append! out ", ")))
                   (w/line! out " = select(_n + 1, ...)")

                   (w/next-block! out "else")
                   ;; Otherwise we'll just assign an empt list to the variadic and pass the ... to the
                   ;; remaining args
                   (w/append! out args-var)
                   (w/line! out " = { tag=\"list\", n=0}")

                   (for i (succ variadic) (# args) 1
                     (w/append! out (escape-var (.> args i :var) state))
                     (when (< i (# args)) (w/append! out ", ")))
                   (w/line! out " = ...")

                   (w/end-block! out "end")))))

           (when (.> cat :recur) (w/begin-block! out "while true do"))
           (compile-block node out state 3 "return ")
           (when (.> cat :recur) (w/end-block! out "end"))
           (w/unindent! out)
           (w/append! out "end)")))]

      ["cond"
       (let [(closure (! ret))
             (had-final false)
             (ends 1)]

         ;; If we're being used as an expression then we have to wrap as a closure.
         (when closure
           (w/begin-block! out "(function()")
           (set! ret "return "))

         (with (i 2)
           (while (and (! had-final) (<= i (# node)))
             (let* [(item (nth node i))
                    (case (nth item 1))
                    (is-final (truthy? case))]

               ;; If we're the last block and there isn't anything here, then don't emit an
               ;; else
               (when (and (> i 2) (or (! is-final) (/= ret "") (/= (# item) 1)))
                 (w/append! out "else"))

               ;; We stop iterating after a branch marked "true" and just invoke the code.
               (cond
                 [is-final (when (= i 2) (w/append! out "do"))] ;; TODO: Could we dec! the ends variable instead?
                 [(.> cat-lookup case :stmt)
                  ;; We flatten if statements branching on an if by declaring a temp variable
                  ;; and assigning the branch result to it.
                  ;; If we're not the first condition then we also have to indent everything once.
                  ;; A further enhancement would be to detect or and and patterns and convert them
                  ;; to the relevant expression.
                  (when (> i 2)
                    (w/indent! out)
                    (w/line! out)
                    (inc! ends))
                  (with (tmp (escape-var { :name "temp" } state))
                    (w/line! out (.. "local " tmp))
                    (compile-expression case out state (.. tmp " = "))
                    (w/line! out)
                    (w/line! out (.. "if " tmp " then")))]
                 [true
                   (w/append! out "if ")
                   (compile-expression case out state)
                   (w/append! out " then")])

               (w/indent! out) (w/line! out)
               (compile-block item out state 2 ret)
               (w/unindent! out)

               (when is-final
                 (set! had-final true))
               (inc! i))))

         ;; If we didn't hit a true branch then we should error at runtime
         (unless had-final
           (w/append! out "else")
           (w/indent! out) (w/line! out)
           (w/append! out "_error(\"unmatched item\")")
           (w/unindent! out) (w/line! out))

         ;; End each nested block
         (for i 1 ends 1
           (w/append! out "end")
           (when (< i ends) (w/unindent! out) (w/line! out)))

         ;; And finish of the closure if required
         (when closure
           (w/line! out)
           (w/end-block! out "end)()")))]

      ["not"
       (if ret
         (set! ret (.. ret "not "))
         (w/append! out "not "))

       (compile-expression (car (nth node 2)) out state ret)]

      ["or"
       (when ret (w/append! out ret))
       (w/append! out "(")
       (with (len (# node))
         (for i 2 len 1
           (when (> i 2) (w/append! out " or "))
           (compile-expression (nth (nth node i) (if (= i len) 2 1)) out state)))
       (w/append! out ")")]

      ["or-lambda"
       (when ret (w/append! out ret))
       (w/append! out "(")
       (compile-expression (nth node 2) out state)
       (let* [(branch (.> (nth (car node) 3)))
              (len (# branch))]
         (for i 3 len 1
           (w/append! out " or ")
           (compile-expression (nth (nth branch i) (if (= i len) 2 1)) out state)))
       (w/append! out ")")]

      ["and"
       (when ret (w/append! out ret))
       (w/append! out "(")
       (compile-expression (nth (nth node 2) 1) out state)
       (w/append! out " and ")
       (compile-expression (nth (nth node 2) 2) out state)
       (w/append! out ")")]

      ["and-lambda"
       (when ret (w/append! out ret))
       (w/append! out "(")
       (compile-expression (nth node 2) out state)
       (w/append! out " and ")
       (compile-expression (nth (nth (nth (car node) 3) 2) 2) out state)
       (w/append! out ")")]

      ["set!"
       (compile-expression (nth node 3) out state (.. (escape-var (.> node 2 :var) state) " = "))
       (when (and ret (/= ret ""))
         (w/line! out)
         (w/append! out ret)
         (w/append! out "nil"))]

      ["struct-literal"
       (cond
         [(= ret "") (w/append! out "local _ = ")]
         [ret (w/append! out ret)]
         [true])
       (w/append! out "({")
       (for i 2 (# node) 2
         (when (> i 2) (w/append! out ","))
         (w/append! out "[")
         (compile-expression (nth node i) out state)
         (w/append! out "]=")
         (compile-expression (nth node (succ i)) out state))
       (w/append! out "})")]

      ["define"
       (compile-expression (nth node (# node)) out state (.. (escape-var (.> node :defVar) state) " = "))]

      ["define-native"
       (with (meta (.> state :meta (.> node :defVar :fullName)))
         (if (= meta nil)
            ;; Just copy it from the library table value
            (w/append! out (string/format "%s = _libs[%q]" (escape-var (.> node :defVar) state) (.> node :defVar :fullName)))
            (progn
              ;; Generate an accessor for it.
              (w/append! out (string/format "%s = " (escape-var (.> node :defVar) state)))
              (compile-native out meta))))]

      ["quote"
       ;; Quotations are "pure" so we don't have to emit anything
       (unless (= ret "")
         (when ret (w/append! out ret))
         (compile-expression (nth node 2) out state))]

      ["quote-const" (unless (= ret "")
                       (when ret (w/append! out ret))
                       (case (type node)
                         ["string" (w/append! out (string/quoted (.> node :value)))]
                         ["number" (w/append! out (number->string (.> node :value)))]
                         ["symbol"
                          (w/append! out (.. "({ tag=\"symbol\", contents=" (string/quoted (.> node :contents))))
                          (when (.> node :var)
                            (w/append! out (.. ", var=" (string/quoted(number->string (.> node :var))))))
                          (w/append! out "})")]
                         ["key" (w/append! out (string/.. "({tag=\"key\", value=" (string/quoted (.> node :value)) "})"))]))]

      ["quote-list"
       (when ret (w/append! out ret))
       (w/append! out (.. "({tag = \"list\", n = " (number->string (# node))))
       (for-each sub node
         (w/append! out ", ")
         (compile-expression sub out state))
       (w/append! out "})")]

      ["quote-splice"
       (unless ret (w/begin-block! out "(function()"))
       (w/line! out "local _offset, _result, _temp = 0, {tag=\"list\",n=0}")
       (with (offset 0)
         (for i 1 (# node) 1
           (let* [(sub (nth node i))
                  (cat (.> state :cat-lookup sub))]
             (unless cat
               (import urn/range r)
               (print! "Cannot find" (pretty sub) (r/format-node sub)))

             (if (= (.> cat :category) "unquote-splice")
               (progn
                 ;; Every unquote-splice subtracts one from the offset position
                 (inc! offset)

                 (w/append! out "_temp = ")
                 (compile-expression (nth sub 2) out state)
                 (w/line! out)

                 (w/line! out (string/.. "for _c = 1, _temp.n do _result[" (number->string (- i offset)) " + _c + _offset] = _temp[_c] end"))
                 (w/line! out "_offset = _offset + _temp.n"))
               (progn
                 (w/append! out (string/.. "_result[" (number->string (- i offset)) " + _offset] = "))
                 (compile-expression sub out state)
                 (w/line! out)))))
         (w/line! out (.. "_result.n = _offset + " (number->string (- (# node) offset)))))
       (cond
         [(= ret "")]
         [ret (w/append! out (.. ret "_result"))]
         [true
          (w/line! out "return _result")
          (w/end-block! out "end)()")])]

      ["syntax-quote" (compile-expression (nth node 2) out state ret)]
      ["unquote" (compile-expression (nth node 2) out state ret)]
      ["unquote-splice" (fail! "Should neve have explicit unquote-splice")]

      ["import"
       ;; Imports don't do anything at all (and should have be stripped by the optimiser)
       ;; so we handle the return expression if required.
       (cond
         [(= ret nil) (w/append! out "nil")]
         [(/= ret "")
          (w/append! out ret)
          (w/append! out "nil")]
         [true])]

      ["call-symbol"
       (with (head (car node))
         ;; As we're invoking a known symbol here, we can do some fancy stuff. In this case, we just
         ;; "inline" anything defined in library meta data (such as arithmetic operators).
         (let* [(meta (and (symbol? head) (= (.> head :var :tag) "native") (.> state :meta (.> head :var :fullName))))
                (meta-ty (type meta))]
           ;; Obviously metadata only exists for native expressions. We can only emit it if
           ;; we're in the right context (statements cannot be emitted when we require an expression) and
           ;; we've passed in the correct number of arguments.
           (cond
             [(= meta-ty "nil")]
             [(= meta-ty "boolean")]
             [(= meta-ty "expr")]
             [(= meta-ty "stmt")
              ;; Cannot use statements if we're in an expression
              (unless ret (set! meta nil))]
             [(= meta-ty "var")
              ;; We'll have cached the global lookup above
              (set! meta nil)])

           (cond
             [(and meta (if (.> meta :fold)
                          (>= (pred (# node)) (.> meta :count))
                          (= (pred (# node)) (.> meta :count))))
              ;; If we're dealing with an expression then we emit the returner first. Statements just
              ;; return nil.
              (when (= (.> meta :tag) "expr")
                (cond
                  [(= ret "") (w/append! out "local _ = ")]
                  [ret (w/append! out ret)]
                  [true]))

              ;; Emit all entries. Numbers represent an argument, everything else is just
              ;; appended directly.
              (let* [(contents (.> meta :contents))
                     (fold (.> meta :fold))
                     (count (.> meta :count))
                     (stack nil)]
                (letrec [(build (lambda (start end)
                                  (for-each entry contents
                                    (cond
                                      [(string? entry) (w/append! out entry)]
                                      [(and (= fold "l") (= entry 1) (< start end)) (build start (pred end)) (set! start end)]
                                      [(and (= fold "r") (= entry 2) (< start end)) (build (succ start) end)]
                                      [true (compile-expression (nth node (+ entry start)) out state)]))))]
                  (build 1 (- (# node) count))))

              ;; If we're dealing with a statement then return nil.
              (when (and (/= (.> meta :tag) "expr") (/= ret ""))
                (w/line! out)
                (w/append! out ret)
                (w/append! out "nil")
                (w/line! out))]
             [(.> cat :recur)
              (let* [(head (.> cat :recur :def))
                     (args (nth head 2))]

                (if (> (# args) 0)
                  ;; If we have some arguments, then set all of them in one go
                  (with (pack-name nil)

                    ;; First emit a series of variables we're going to set
                    (let* [(offset 1)
                           (done false)]
                      (for i 1 (# args) 1
                        (with (var (.> args i :var))
                          (if (.> var :isVariadic)
                            ;; If we're variadic then create a list of each sub expression
                            (with (count (- (# node) (# args)))
                              (when (< count 0) (set! count 0))
                              (if done (w/append! out ", ") (set! done true))
                              (w/append! out (escape-var var state))
                              (set! offset count))
                            (with (expr (nth node (+ i offset)))
                              (when (and expr (or (! (symbol? expr)) (/= (.> expr :var) var)))
                                (if done (w/append! out ", ") (set! done true))
                                (w/append! out (escape-var var state))))))))

                    (w/append! out " = ")

                    (let* [(offset 1)
                           (done false)]
                      (for i 1 (# args) 1
                        (with (var (.> args i :var))
                          (if (.> var :isVariadic)
                            ;; If we're variadic then create a list of each sub expression
                            (with (count (- (# node) (# args)))
                              (when (< count 0) (set! count 0))
                              (if done (w/append! out ", ") (set! done true))
                              (when (compile-pack node out state i count)
                                (set! pack-name (escape-var var state)))
                              (set! offset count))
                            (with (expr (nth node (+ i offset)))
                              (when (and expr (or (! (symbol? expr)) (/= (.> expr :var) var)))
                                (if done (w/append! out ", ") (set! done true))
                                (compile-expression (nth node (+ i offset)) out state))))))

                      ;; Emit all arguments which haven't been used anywhere
                      (for i (+ (# args) (+ offset 1)) (# node) 1
                        (when (> i 1) (w/append! out ", "))
                        (compile-expression (nth node i) out state)))

                    (w/line! out)
                    (when pack-name (w/line! (.. pack-name ".tag = \"list\""))))

                  ;; Otherwise just emit each expression in turn.
                  (for i 1 (# node) 1
                    (when (> i 1) (w/append! out ", "))
                    (compile-expression (nth node i) out state "")
                    (w/line! out))))]
             [true
              ;; Alas, just emit as normal
              (when ret (w/append! out ret))
              (compile-expression head out state)
              (w/append! out "(")
              (for i 2 (# node) 1
                (when (> i 2) (w/append! out ", "))
                (compile-expression (nth node i) out state))
              (w/append! out ")")])))]

      ["wrap-value"
       (when ret (w/append! out ret))
       (w/append! out "(")
       (compile-expression (nth node 2) out state)
       (w/append! out ")")]

      ["call-lambda"
       ;; If we have a direction invokation of a function then inline it
       (when (= ret nil)
         (print! (pretty node) " marked as call-lambda for " ret))
       (let* [(head (car node))
              (args (nth head 2))
              (offset 1)]
         (for i 1 (# args) 1
           (let* [(var (.> args i :var))
                  (esc (escape-var var state))]
             (w/append! out (.. "local " esc))
             (if (.> var :isVariadic)
               ;; If we're variadic then create a list of each sub expression
               (with (count (- (# node) (# args)))
                 (when (< count 0) (set! count 0))
                 (w/append! out " = ")
                 (when (compile-pack node out state i count)
                   (w/append! out (.. " " esc ".tag = \"list\"")))
                 (w/line! out)
                 (set! offset count))
               (let* [(expr (nth node (+ i offset)))
                      (name (escape-var var state))
                      (ret nil)]
                 (if expr
                   (progn
                     (if (.> cat-lookup expr :stmt)
                       (progn
                         (set! ret (.. name " = "))
                         (w/line! out))
                       (w/append! out " = "))
                     (compile-expression expr out state ret)
                     (w/line! out))
                   (w/line! out))))))

         ;; Emit all arguments which haven't been used anywhere
         (for i (+ (# args) (+ offset 1)) (# node) 1
              (compile-expression (nth node i) out state "")
              (w/line! out))

         (compile-block head out state 3 ret))]
      ["call-literal"
       ;; Just invoke the expression as normal
       (when ret (w/append! out ret))
       ;; If we're invoking false or something then we need to wrap it in parens.
       ;; We'll just error anyway, but I can live with that.
       (w/append! out "(")
       (compile-expression (car node) out state)
       (w/append! out ")(")
       (for i 2 (# node) 1
         (when (> i 2) (w/append! out ", "))
         (compile-expression (nth node i) out state))
       (w/append! out ")")]

      ["call"
       ;; Just invoke the expression as normal
       (when ret (w/append! out ret))
       (compile-expression (car node) out state)
       (w/append! out "(")
       (for i 2 (# node) 1
         (when (> i 2) (w/append! out ", "))
         (compile-expression (nth node i) out state))
       (w/append! out ")")])

    (unless (.> boring-categories cat-tag) (w/pop-node! out node))))

(defun compile-pack (node out state start count)
  "Compile the code required to pack a set of arguments into a list.
   This will pack elements START to START + COUNT in NODE into a list stored
   in NAME."
  :hidden
  (if (or (<= count 0) (atom? (nth node (+ start count))))
    (progn
      ;; Emit each expression into the list.
      ;; A future enhancement might be to check if these are statements and, if so, push it
      (w/append! out "{ tag=\"list\", n=")
      (w/append! out (number->string count))

      (for j 1 count 1
        (w/append! out ", ")
        (compile-expression (nth node (+ start j)) out state))
      (w/append! out "}")
      false)
    (progn
      ;; Emit eaach element into a call of table.pack
      (w/append! out " _pack(")
      (for j 1 count 1
        (when (> j 1) (w/append! out ", "))
        (compile-expression (nth node (+ start j)) out state))
      (w/append! out ")")
      true)))

(defun compile-block (nodes out state start ret)
  "Compile a block of expressions."
  :hidden
  (for i start (# nodes) 1
    (with (ret' (if (= i (# nodes)) ret ""))
      (compile-expression (nth nodes i) out state ret'))
    (w/line! out))
  (when (and (< (# nodes) start) ret (/= ret ""))
    (w/append! out ret)
    (w/line! out "nil")))

(defun prelude (out)
  "Various code to emit before everything else.

   This includes multi-version compatibility and caches some commonly used globals the compiled code will use."
  ;; Add some compat stuff
  (w/line! out "if not table.pack then table.pack = function(...) return { n = select(\"#\", ...), ... } end end")
  (w/line! out "if not table.unpack then table.unpack = unpack end")
  (w/line! out "local load = load if _VERSION:find(\"5.1\") then load = function(x, n, _, env) local f, e = loadstring(x, n) if not f then error(e, 2) end if env then setfenv(f, env) end return f end end")

  ;; And cache some useful globals
  (w/line! out "local _select, _unpack, _pack, _error = select, table.unpack, table.pack, error"))

(defun expression (node out state ret)
  "Tag NODE and compile it."
  (run-pass cat/categorise-node state nil node (.> state :cat-lookup) (/= ret nil))
  (compile-expression node out state ret))

(defun block (nodes out state start ret)
  "Tag all NODES and compile them."
  (run-pass cat/categorise-nodes state nil nodes (.> state :cat-lookup))
  (compile-block nodes out state start ret))
