REBOL [
    title: "A tiny static HTTP server"
    author: 'abolka
    date: 2009-11-04
]

;; INIT
-help: does [print {
USAGE: r3 webserver.reb [OPTIONS]
OPTIONS:
  -c N    : chunk-size: N * 1024
  -h, -help, --help : this help
  -q      : verbose: 0 (quiet)
  -v      : verbose: 2 (debug)
  INTEGER : port number [8000]
  OTHER   : web root [system/options/path]
e.g.: 8080 /my/web/root quiet
}]

chunk-size: 32
port: 8000
root: system/options/path
verbose: 1

a: system/options/args
forall a [case [
    "-c" = a/1 [
        chunk-size: to-integer a/2
        a: next a
    ]
    find ["-h" "-help" "--help"] a/1 [-help quit]
    find ["-q" "-quiet" "--quiet"] a/1 [verbose: 0]
    "-v" = a/1 [verbose: 2]
    integer? load a/1 [port: load a/1]
    true [root: to-file a/1]
]]

chunk-size: chunk-size * 1024

;; LIBS
crlf2bin: to binary! join-of crlf crlf

code-map: make map! [
    200 "OK"
    400 "Forbidden"
    404 "Not Found"
]

mime-map: make map! [
    "css" "text/css"
    "gif" "image/gif"
    "html" "text/html"
    "jpg" "image/jpeg"
    "js" "application/javascript"
    "png" "image/png"
    "r" "text/plain"
    "r3" "text/plain"
    "reb" "text/plain"
]

error-template: trim/auto copy {
    <html><head><title>$code $text</title></head><body><h1>$text</h1>
    <p>Requested URI: <code>$uri</code></p><hr><i>shttpd.r</i> on
    <a href="http://www.rebol.com/rebol3/">REBOL 3</a> $r3</body></html>
}

error-response: func [code uri <local> values] [
    values: [code (code) text (code-map/:code) uri (uri) r3 (system/version)]
    reduce [code "text/html" reword error-template compose values]
]

start-response: func [port res <local> code text type body] [
    set [code type body] res
    write port ajoin ["HTTP/1.0 " code " " code-map/:code crlf]
    write port ajoin ["Content-type: " type crlf]
    write port ajoin ["Content-length: " length? body crlf]
    write port crlf
    ;; Manual chunking is only necessary because of several bugs in R3's
    ;; networking stack (mainly cc#2098 & cc#2160; in some constellations also
    ;; cc#2103). Once those are fixed, we should directly use R3's internal
    ;; chunking instead: `write port body`.
    port/locals: copy body
]

send-chunk: func [port] [
    ;; Trying to send data >32'000 bytes at once will trigger R3's internal
    ;; chunking (which is buggy, see above). So we cannot use chunks >32'000
    ;; for our manual chunking.
    if verbose >= 2
    [ print/only [length port/locals "->"]]
    unless empty? port/locals [write port take/part port/locals chunk-size]
    if verbose >= 2
    [ print [length port/locals]]
]

html-list-dir: function [
  "Output dir contents in HTML."
  dir [file!]
  ][
  if error? try [list: read dir] [
    return _
  ]
  sort/compare list func [x y] [
    case [
      all [dir? x not dir? y] [true]
      all [not dir? x dir? y] [false]
      y > x [true]
      true [false]
    ]
  ]
  insert list %../
  data: copy {<head>
    <meta name="viewport" content="initial-scale=1.0" />
    <style> a {text-decoration: none} </style>
  </head>}
  for-each i list [
    append data ajoin [
      {<a href="} i {">}
      if dir? i ["&gt; "]
      i </a> <br/>
    ]
  ]
  data
]

handle-request: function [config req] [
    parse to-string req [copy method: "get" " " [copy uri to " "]]
    uri: default ["index.html"]
    either query: find uri "?" [
        path: copy/part uri query
        query: next query
    ][
        path: copy uri
    ]
    if verbose > 0 [
        print spaced ["======^/action:" method uri]
        print spaced ["path:  " path]
        print spaced ["query: " query]
    ]
    filetype: exists? file: config/root/:path
    unless filetype [return error-response 404 uri]
    if filetype = 'dir [
        while [#"/" = last path] [take/last path]
        append path #"/"
        if data: html-list-dir file [
            return reduce [200 "text/html" data]
        ]
        return error-response 403 uri
    ]
    split-path: split path "/"
    parse last split-path [
        some [thru "."]
        copy ext: to end
        (mime: select mime-map ext)
    ]
    mime: default ["application/octet-stream"]

    if error? try [data: read file] [return error-response 400 uri]
    reduce [200 mime data]
]

awake-client: function [event] [
    port: event/port
    switch event/type [
        read [
            either find port/data crlf2bin [
                res: handle-request port/locals/config port/data
                if error? err: trap [start-response port res][
                    if verbose >= 2 [
                        print "READ ERROR:"
                        print err
                    ]
                    close port
                ]
            ] [
                read port
            ]
        ]
        wrote [
            either empty? port/locals [
                close port
            ][
                if error? err: trap [send-chunk port][
                    if verbose >= 2 [
                        print "WRITE ERROR:"
                        print err
                    ]
                    close port
                ]
            ]
        ]
        close [close port]
    ]
]

awake-server: func [event <local> client] [
    if event/type = 'accept [
        client: first event/port
        client/awake: :awake-client
        read client
    ]
]

serve: func [web-port web-root <local> listen-port] [
    listen-port: open rejoin [tcp://: web-port]
    listen-port/locals: make object! compose/deep [config: [root: (web-root)]]
    listen-port/awake: :awake-server
    if verbose > 0 [print spaced [
        "Serving on port" web-port newline
        "with root" web-root newline
        "and chunk size" chunk-size
    ]]
    wait listen-port
]

;; START

serve port root

;; vim: set sw=4 sts=-1 expandtab:
