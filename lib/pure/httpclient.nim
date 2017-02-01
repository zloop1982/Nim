#
#
#            Nim's Runtime Library
#        (c) Copyright 2016 Dominik Picheta, Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a simple HTTP client that can be used to retrieve
## webpages and other data.
##
## Retrieving a website
## ====================
##
## This example uses HTTP GET to retrieve
## ``http://google.com``:
##
## .. code-block:: Nim
##   var client = newHttpClient()
##   echo client.getContent("http://google.com")
##
## The same action can also be performed asynchronously, simply use the
## ``AsyncHttpClient``:
##
## .. code-block:: Nim
##   var client = newAsyncHttpClient()
##   echo await client.getContent("http://google.com")
##
## The functionality implemented by ``HttpClient`` and ``AsyncHttpClient``
## is the same, so you can use whichever one suits you best in the examples
## shown here.
##
## **Note:** You will need to run asynchronous examples in an async proc
## otherwise you will get an ``Undeclared identifier: 'await'`` error.
##
## Using HTTP POST
## ===============
##
## This example demonstrates the usage of the W3 HTML Validator, it
## uses ``multipart/form-data`` as the ``Content-Type`` to send the HTML to be
## validated to the server.
##
## .. code-block:: Nim
##   var client = newHttpClient()
##   var data = newMultipartData()
##   data["output"] = "soap12"
##   data["uploaded_file"] = ("test.html", "text/html",
##     "<html><head></head><body><p>test</p></body></html>")
##
##   echo client.postContent("http://validator.w3.org/check", multipart=data)
##
## You can also make post requests with custom headers.
## This example sets ``Content-Type`` to ``application/json``
## and uses a json object for the body
##
## .. code-block:: Nim
##   import httpclient, json
##
##   let client = newHttpClient()
##   client.headers = newHttpHeaders({ "Content-Type": "application/json" })
##   let body = %*{
##       "data": "some text"
##   }
##   echo client.request("http://some.api", httpMethod = HttpPost, body = $body)
##
## Progress reporting
## ==================
##
## You may specify a callback procedure to be called during an HTTP request.
## This callback will be executed every second with information about the
## progress of the HTTP request.
##
## .. code-block:: Nim
##    var client = newAsyncHttpClient()
##    proc onProgressChanged(total, progress, speed: BiggestInt) {.async.} =
##      echo("Downloaded ", progress, " of ", total)
##      echo("Current rate: ", speed div 1000, "kb/s")
##    client.onProgressChanged = onProgressChanged
##    discard await client.getContent("http://speedtest-ams2.digitalocean.com/100mb.test")
##
## If you would like to remove the callback simply set it to ``nil``.
##
## .. code-block:: Nim
##   client.onProgressChanged = nil
##
## SSL/TLS support
## ===============
## This requires the OpenSSL library, fortunately it's widely used and installed
## on many operating systems. httpclient will use SSL automatically if you give
## any of the functions a url with the ``https`` schema, for example:
## ``https://github.com/``.
##
## You will also have to compile with ``ssl`` defined like so:
## ``nim c -d:ssl ...``.
##
## Timeouts
## ========
##
## Currently only the synchronous functions support a timeout.
## The timeout is
## measured in milliseconds, once it is set any call on a socket which may
## block will be susceptible to this timeout.
##
## It may be surprising but the
## function as a whole can take longer than the specified timeout, only
## individual internal calls on the socket are affected. In practice this means
## that as long as the server is sending data an exception will not be raised,
## if however data does not reach the client within the specified timeout a
## ``TimeoutError`` exception will be raised.
##
## Proxy
## =====
##
## A proxy can be specified as a param to any of the procedures defined in
## this module. To do this, use the ``newProxy`` constructor. Unfortunately,
## only basic authentication is supported at the moment.

import net, strutils, uri, parseutils, strtabs, base64, os, mimetypes,
  math, random, httpcore, times, tables
import asyncnet, asyncdispatch
import nativesockets

export httpcore except parseHeader # TODO: The ``except`` doesn't work

type
  Response* = object
    version*: string
    status*: string
    headers*: HttpHeaders
    body*: string

proc code*(response: Response): HttpCode
           {.raises: [ValueError, OverflowError].} =
  ## Retrieves the specified response's ``HttpCode``.
  ##
  ## Raises a ``ValueError`` if the response's ``status`` does not have a
  ## corresponding ``HttpCode``.
  return response.status[0 .. 2].parseInt.HttpCode

type
  Proxy* = ref object
    url*: Uri
    auth*: string

  MultipartEntries* = openarray[tuple[name, content: string]]
  MultipartData* = ref object
    content: seq[string]

  ProtocolError* = object of IOError   ## exception that is raised when server
                                       ## does not conform to the implemented
                                       ## protocol

  HttpRequestError* = object of IOError ## Thrown in the ``getContent`` proc
                                        ## and ``postContent`` proc,
                                        ## when the server returns an error

{.deprecated: [TResponse: Response, PProxy: Proxy,
  EInvalidProtocol: ProtocolError, EHttpRequestErr: HttpRequestError
].}

const defUserAgent* = "Nim httpclient/" & NimVersion

proc httpError(msg: string) =
  var e: ref ProtocolError
  new(e)
  e.msg = msg
  raise e

proc fileError(msg: string) =
  var e: ref IOError
  new(e)
  e.msg = msg
  raise e

proc parseChunks(s: Socket, timeout: int): string =
  result = ""
  var ri = 0
  while true:
    var chunkSizeStr = ""
    var chunkSize = 0
    s.readLine(chunkSizeStr, timeout)
    var i = 0
    if chunkSizeStr == "":
      httpError("Server terminated connection prematurely")
    while true:
      case chunkSizeStr[i]
      of '0'..'9':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('0'))
      of 'a'..'f':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('a') + 10)
      of 'A'..'F':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('A') + 10)
      of '\0':
        break
      of ';':
        # http://tools.ietf.org/html/rfc2616#section-3.6.1
        # We don't care about chunk-extensions.
        break
      else:
        httpError("Invalid chunk size: " & chunkSizeStr)
      inc(i)
    if chunkSize <= 0:
      s.skip(2, timeout) # Skip \c\L
      break
    result.setLen(ri+chunkSize)
    var bytesRead = 0
    while bytesRead != chunkSize:
      let ret = recv(s, addr(result[ri]), chunkSize-bytesRead, timeout)
      ri += ret
      bytesRead += ret
    s.skip(2, timeout) # Skip \c\L
    # Trailer headers will only be sent if the request specifies that we want
    # them: http://tools.ietf.org/html/rfc2616#section-3.6.1

proc parseBody(s: Socket, headers: HttpHeaders, httpVersion: string, timeout: int): string =
  result = ""
  if headers.getOrDefault"Transfer-Encoding" == "chunked":
    result = parseChunks(s, timeout)
  else:
    # -REGION- Content-Length
    # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.3
    var contentLengthHeader = headers.getOrDefault"Content-Length"
    if contentLengthHeader != "":
      var length = contentLengthHeader.parseint()
      if length > 0:
        result = newString(length)
        var received = 0
        while true:
          if received >= length: break
          let r = s.recv(addr(result[received]), length-received, timeout)
          if r == 0: break
          received += r
        if received != length:
          httpError("Got invalid content length. Expected: " & $length &
                    " got: " & $received)
    else:
      # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.4 TODO

      # -REGION- Connection: Close
      # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.5
      if headers.getOrDefault"Connection" == "close" or httpVersion == "1.0":
        var buf = ""
        while true:
          buf = newString(4000)
          let r = s.recv(addr(buf[0]), 4000, timeout)
          if r == 0: break
          buf.setLen(r)
          result.add(buf)

proc parseResponse(s: Socket, getBody: bool, timeout: int): Response =
  var parsedStatus = false
  var linei = 0
  var fullyRead = false
  var line = ""
  result.headers = newHttpHeaders()
  while true:
    line = ""
    linei = 0
    s.readLine(line, timeout)
    if line == "": break # We've been disconnected.
    if line == "\c\L":
      fullyRead = true
      break
    if not parsedStatus:
      # Parse HTTP version info and status code.
      var le = skipIgnoreCase(line, "HTTP/", linei)
      if le <= 0: httpError("invalid http version")
      inc(linei, le)
      le = skipIgnoreCase(line, "1.1", linei)
      if le > 0: result.version = "1.1"
      else:
        le = skipIgnoreCase(line, "1.0", linei)
        if le <= 0: httpError("unsupported http version")
        result.version = "1.0"
      inc(linei, le)
      # Status code
      linei.inc skipWhitespace(line, linei)
      result.status = line[linei .. ^1]
      parsedStatus = true
    else:
      # Parse headers
      var name = ""
      var le = parseUntil(line, name, ':', linei)
      if le <= 0: httpError("invalid headers")
      inc(linei, le)
      if line[linei] != ':': httpError("invalid headers")
      inc(linei) # Skip :

      result.headers[name] = line[linei.. ^1].strip()
      # Ensure the server isn't trying to DoS us.
      if result.headers.len > headerLimit:
        httpError("too many headers")

  if not fullyRead:
    httpError("Connection was closed before full request has been made")
  if getBody:
    result.body = parseBody(s, result.headers, result.version, timeout)
  else:
    result.body = ""

{.deprecated: [THttpMethod: HttpMethod].}

when not defined(ssl):
  type SSLContext = ref object
var defaultSSLContext {.threadvar.}: SSLContext
when defined(ssl):
  defaultSSLContext = newContext(verifyMode = CVerifyNone)
  when compileOption("threads"):
    onThreadCreation do ():
      defaultSSLContext = newContext(verifyMode = CVerifyNone)

proc newProxy*(url: string, auth = ""): Proxy =
  ## Constructs a new ``TProxy`` object.
  result = Proxy(url: parseUri(url), auth: auth)

proc newMultipartData*: MultipartData =
  ## Constructs a new ``MultipartData`` object.
  MultipartData(content: @[])

proc add*(p: var MultipartData, name, content: string, filename: string = nil,
          contentType: string = nil) =
  ## Add a value to the multipart data. Raises a `ValueError` exception if
  ## `name`, `filename` or `contentType` contain newline characters.

  if {'\c','\L'} in name:
    raise newException(ValueError, "name contains a newline character")
  if filename != nil and {'\c','\L'} in filename:
    raise newException(ValueError, "filename contains a newline character")
  if contentType != nil and {'\c','\L'} in contentType:
    raise newException(ValueError, "contentType contains a newline character")

  var str = "Content-Disposition: form-data; name=\"" & name & "\""
  if filename != nil:
    str.add("; filename=\"" & filename & "\"")
  str.add("\c\L")
  if contentType != nil:
    str.add("Content-Type: " & contentType & "\c\L")
  str.add("\c\L" & content & "\c\L")

  p.content.add(str)

proc add*(p: var MultipartData, xs: MultipartEntries): MultipartData
         {.discardable.} =
  ## Add a list of multipart entries to the multipart data `p`. All values are
  ## added without a filename and without a content type.
  ##
  ## .. code-block:: Nim
  ##   data.add({"action": "login", "format": "json"})
  for name, content in xs.items:
    p.add(name, content)
  result = p

proc newMultipartData*(xs: MultipartEntries): MultipartData =
  ## Create a new multipart data object and fill it with the entries `xs`
  ## directly.
  ##
  ## .. code-block:: Nim
  ##   var data = newMultipartData({"action": "login", "format": "json"})
  result = MultipartData(content: @[])
  result.add(xs)

proc addFiles*(p: var MultipartData, xs: openarray[tuple[name, file: string]]):
              MultipartData {.discardable.} =
  ## Add files to a multipart data object. The file will be opened from your
  ## disk, read and sent with the automatically determined MIME type. Raises an
  ## `IOError` if the file cannot be opened or reading fails. To manually
  ## specify file content, filename and MIME type, use `[]=` instead.
  ##
  ## .. code-block:: Nim
  ##   data.addFiles({"uploaded_file": "public/test.html"})
  var m = newMimetypes()
  for name, file in xs.items:
    var contentType: string
    let (_, fName, ext) = splitFile(file)
    if ext.len > 0:
      contentType = m.getMimetype(ext[1..ext.high], nil)
    p.add(name, readFile(file), fName & ext, contentType)
  result = p

proc `[]=`*(p: var MultipartData, name, content: string) =
  ## Add a multipart entry to the multipart data `p`. The value is added
  ## without a filename and without a content type.
  ##
  ## .. code-block:: Nim
  ##   data["username"] = "NimUser"
  p.add(name, content)

proc `[]=`*(p: var MultipartData, name: string,
            file: tuple[name, contentType, content: string]) =
  ## Add a file to the multipart data `p`, specifying filename, contentType and
  ## content manually.
  ##
  ## .. code-block:: Nim
  ##   data["uploaded_file"] = ("test.html", "text/html",
  ##     "<html><head></head><body><p>test</p></body></html>")
  p.add(name, file.content, file.name, file.contentType)

proc format(p: MultipartData): tuple[header, body: string] =
  if p == nil or p.content == nil or p.content.len == 0:
    return ("", "")

  # Create boundary that is not in the data to be formatted
  var bound: string
  while true:
    bound = $random(int.high)
    var found = false
    for s in p.content:
      if bound in s:
        found = true
    if not found:
      break

  result.header = "Content-Type: multipart/form-data; boundary=" & bound & "\c\L"
  result.body = ""
  for s in p.content:
    result.body.add("--" & bound & "\c\L" & s)
  result.body.add("--" & bound & "--\c\L")

proc request*(url: string, httpMethod: string, extraHeaders = "",
              body = "", sslContext = defaultSSLContext, timeout = -1,
              userAgent = defUserAgent, proxy: Proxy = nil): Response
              {.deprecated.} =
  ## | Requests ``url`` with the custom method string specified by the
  ## | ``httpMethod`` parameter.
  ## | Extra headers can be specified and must be separated by ``\c\L``
  ## | An optional timeout can be specified in milliseconds, if reading from the
  ## server takes longer than specified an ETimeout exception will be raised.
  ##
  ## **Deprecated since version 0.15.0**: use ``HttpClient.request`` instead.
  var r = if proxy == nil: parseUri(url) else: proxy.url
  var hostUrl = if proxy == nil: r else: parseUri(url)
  var headers = httpMethod.toUpper()
  # TODO: Use generateHeaders further down once it supports proxies.

  var s = newSocket()
  defer: s.close()
  if s == nil: raiseOSError(osLastError())
  var port = net.Port(80)
  if r.scheme == "https":
    when defined(ssl):
      sslContext.wrapSocket(s)
      port = net.Port(443)
    else:
      raise newException(HttpRequestError,
                "SSL support is not available. Cannot connect over SSL.")
  if r.port != "":
    port = net.Port(r.port.parseInt)


  # get the socket ready. If we are connecting through a proxy to SSL,
  # send the appropriate CONNECT header. If not, simply connect to the proper
  # host (which may still be the proxy, for normal HTTP)
  if proxy != nil and hostUrl.scheme == "https":
    when defined(ssl):
      var connectHeaders = "CONNECT "
      let targetPort = if hostUrl.port == "": 443 else: hostUrl.port.parseInt
      connectHeaders.add(hostUrl.hostname)
      connectHeaders.add(":" & $targetPort)
      connectHeaders.add(" HTTP/1.1\c\L")
      connectHeaders.add("Host: " & hostUrl.hostname & ":" & $targetPort & "\c\L")
      if proxy.auth != "":
        let auth = base64.encode(proxy.auth, newline = "")
        connectHeaders.add("Proxy-Authorization: basic " & auth & "\c\L")
      connectHeaders.add("\c\L")
      if timeout == -1:
        s.connect(r.hostname, port)
      else:
        s.connect(r.hostname, port, timeout)

      s.send(connectHeaders)
      let connectResult = parseResponse(s, false, timeout)
      if not connectResult.status.startsWith("200"):
        raise newException(HttpRequestError,
                           "The proxy server rejected a CONNECT request, " &
                           "so a secure connection could not be established.")
      sslContext.wrapConnectedSocket(s, handshakeAsClient)
    else:
      raise newException(HttpRequestError, "SSL support not available. Cannot connect via proxy over SSL")
  else:
    if timeout == -1:
      s.connect(r.hostname, port)
    else:
      s.connect(r.hostname, port, timeout)


  # now that the socket is ready, prepare the headers
  if proxy == nil:
    headers.add ' '
    if r.path[0] != '/': headers.add '/'
    headers.add(r.path)
    if r.query.len > 0:
      headers.add("?" & r.query)
  else:
    headers.add(" " & url)

  headers.add(" HTTP/1.1\c\L")

  if hostUrl.port == "":
    add(headers, "Host: " & hostUrl.hostname & "\c\L")
  else:
    add(headers, "Host: " & hostUrl.hostname & ":" & hostUrl.port & "\c\L")

  if userAgent != "":
    add(headers, "User-Agent: " & userAgent & "\c\L")
  if proxy != nil and proxy.auth != "":
    let auth = base64.encode(proxy.auth, newline = "")
    add(headers, "Proxy-Authorization: basic " & auth & "\c\L")
  add(headers, extraHeaders)
  add(headers, "\c\L")

  # headers are ready. send them, await the result, and close the socket.
  s.send(headers)
  if body != "":
    s.send(body)

  result = parseResponse(s, httpMethod != "HEAD", timeout)

proc request*(url: string, httpMethod = httpGET, extraHeaders = "",
              body = "", sslContext = defaultSSLContext, timeout = -1,
              userAgent = defUserAgent, proxy: Proxy = nil): Response
              {.deprecated.} =
  ## | Requests ``url`` with the specified ``httpMethod``.
  ## | Extra headers can be specified and must be separated by ``\c\L``
  ## | An optional timeout can be specified in milliseconds, if reading from the
  ## server takes longer than specified an ETimeout exception will be raised.
  ##
  ## **Deprecated since version 0.15.0**: use ``HttpClient.request`` instead.
  result = request(url, $httpMethod, extraHeaders, body, sslContext, timeout,
                   userAgent, proxy)

proc redirection(status: string): bool =
  const redirectionNRs = ["301", "302", "303", "307"]
  for i in items(redirectionNRs):
    if status.startsWith(i):
      return true

proc getNewLocation(lastURL: string, headers: HttpHeaders): string =
  result = headers.getOrDefault"Location"
  if result == "": httpError("location header expected")
  # Relative URLs. (Not part of the spec, but soon will be.)
  let r = parseUri(result)
  if r.hostname == "" and r.path != "":
    var parsed = parseUri(lastURL)
    parsed.path = r.path
    parsed.query = r.query
    parsed.anchor = r.anchor
    result = $parsed

proc get*(url: string, extraHeaders = "", maxRedirects = 5,
          sslContext: SSLContext = defaultSSLContext,
          timeout = -1, userAgent = defUserAgent,
          proxy: Proxy = nil): Response {.deprecated.} =
  ## | GETs the ``url`` and returns a ``Response`` object
  ## | This proc also handles redirection
  ## | Extra headers can be specified and must be separated by ``\c\L``.
  ## | An optional timeout can be specified in milliseconds, if reading from the
  ## server takes longer than specified an ETimeout exception will be raised.
  ##
  ## ## **Deprecated since version 0.15.0**: use ``HttpClient.get`` instead.
  result = request(url, httpGET, extraHeaders, "", sslContext, timeout,
                   userAgent, proxy)
  var lastURL = url
  for i in 1..maxRedirects:
    if result.status.redirection():
      let redirectTo = getNewLocation(lastURL, result.headers)
      result = request(redirectTo, httpGET, extraHeaders, "", sslContext,
                       timeout, userAgent, proxy)
      lastURL = redirectTo

proc getContent*(url: string, extraHeaders = "", maxRedirects = 5,
                 sslContext: SSLContext = defaultSSLContext,
                 timeout = -1, userAgent = defUserAgent,
                 proxy: Proxy = nil): string {.deprecated.} =
  ## | GETs the body and returns it as a string.
  ## | Raises exceptions for the status codes ``4xx`` and ``5xx``
  ## | Extra headers can be specified and must be separated by ``\c\L``.
  ## | An optional timeout can be specified in milliseconds, if reading from the
  ## server takes longer than specified an ETimeout exception will be raised.
  ##
  ## **Deprecated since version 0.15.0**: use ``HttpClient.getContent`` instead.
  var r = get(url, extraHeaders, maxRedirects, sslContext, timeout, userAgent,
              proxy)
  if r.status[0] in {'4','5'}:
    raise newException(HttpRequestError, r.status)
  else:
    return r.body

proc post*(url: string, extraHeaders = "", body = "",
           maxRedirects = 5,
           sslContext: SSLContext = defaultSSLContext,
           timeout = -1, userAgent = defUserAgent,
           proxy: Proxy = nil,
           multipart: MultipartData = nil): Response {.deprecated.} =
  ## | POSTs ``body`` to the ``url`` and returns a ``Response`` object.
  ## | This proc adds the necessary Content-Length header.
  ## | This proc also handles redirection.
  ## | Extra headers can be specified and must be separated by ``\c\L``.
  ## | An optional timeout can be specified in milliseconds, if reading from the
  ## server takes longer than specified an ETimeout exception will be raised.
  ## | The optional ``multipart`` parameter can be used to create
  ## ``multipart/form-data`` POSTs comfortably.
  ##
  ## **Deprecated since version 0.15.0**: use ``HttpClient.post`` instead.
  let (mpHeaders, mpBody) = format(multipart)

  template withNewLine(x): expr =
    if x.len > 0 and not x.endsWith("\c\L"):
      x & "\c\L"
    else:
      x

  var xb = mpBody.withNewLine() & body

  var xh = extraHeaders.withNewLine() & mpHeaders.withNewLine() &
    withNewLine("Content-Length: " & $len(xb))

  result = request(url, httpPOST, xh, xb, sslContext, timeout, userAgent,
                   proxy)
  var lastURL = url
  for i in 1..maxRedirects:
    if result.status.redirection():
      let redirectTo = getNewLocation(lastURL, result.headers)
      var meth = if result.status != "307": httpGet else: httpPost
      result = request(redirectTo, meth, xh, xb, sslContext, timeout,
                       userAgent, proxy)
      lastURL = redirectTo

proc postContent*(url: string, extraHeaders = "", body = "",
                  maxRedirects = 5,
                  sslContext: SSLContext = defaultSSLContext,
                  timeout = -1, userAgent = defUserAgent,
                  proxy: Proxy = nil,
                  multipart: MultipartData = nil): string
                  {.deprecated.} =
  ## | POSTs ``body`` to ``url`` and returns the response's body as a string
  ## | Raises exceptions for the status codes ``4xx`` and ``5xx``
  ## | Extra headers can be specified and must be separated by ``\c\L``.
  ## | An optional timeout can be specified in milliseconds, if reading from the
  ## server takes longer than specified an ETimeout exception will be raised.
  ## | The optional ``multipart`` parameter can be used to create
  ## ``multipart/form-data`` POSTs comfortably.
  ##
  ## **Deprecated since version 0.15.0**: use ``HttpClient.postContent``
  ## instead.
  var r = post(url, extraHeaders, body, maxRedirects, sslContext, timeout,
               userAgent, proxy, multipart)
  if r.status[0] in {'4','5'}:
    raise newException(HttpRequestError, r.status)
  else:
    return r.body

proc downloadFile*(url: string, outputFilename: string,
                   sslContext: SSLContext = defaultSSLContext,
                   timeout = -1, userAgent = defUserAgent,
                   proxy: Proxy = nil) =
  ## | Downloads ``url`` and saves it to ``outputFilename``
  ## | An optional timeout can be specified in milliseconds, if reading from the
  ## server takes longer than specified an ETimeout exception will be raised.
  var f: File
  if open(f, outputFilename, fmWrite):
    f.write(getContent(url, sslContext = sslContext, timeout = timeout,
            userAgent = userAgent, proxy = proxy))
    f.close()
  else:
    fileError("Unable to open file")

proc generateHeaders(requestUrl: Uri, httpMethod: string,
                     headers: HttpHeaders, body: string, proxy: Proxy): string =
  # GET
  result = httpMethod.toUpper()
  result.add ' '

  if proxy.isNil:
    # /path?query
    if requestUrl.path[0] != '/': result.add '/'
    result.add(requestUrl.path)
    if requestUrl.query.len > 0:
      result.add("?" & requestUrl.query)
  else:
    # Remove the 'http://' from the URL for CONNECT requests.
    var modifiedUrl = requestUrl
    modifiedUrl.scheme = ""
    result.add($modifiedUrl)

  # HTTP/1.1\c\l
  result.add(" HTTP/1.1\c\L")

  # Host header.
  if requestUrl.port == "":
    add(result, "Host: " & requestUrl.hostname & "\c\L")
  else:
    add(result, "Host: " & requestUrl.hostname & ":" & requestUrl.port & "\c\L")

  # Connection header.
  if not headers.hasKey("Connection"):
    add(result, "Connection: Keep-Alive\c\L")

  # Content length header.
  if body.len > 0 and not headers.hasKey("Content-Length"):
    add(result, "Content-Length: " & $body.len & "\c\L")

  # Proxy auth header.
  if not proxy.isNil and proxy.auth != "":
    let auth = base64.encode(proxy.auth, newline = "")
    add(result, "Proxy-Authorization: basic " & auth & "\c\L")

  for key, val in headers:
    add(result, key & ": " & val & "\c\L")

  add(result, "\c\L")

type
  ProgressChangedProc*[ReturnType] =
    proc (total, progress, speed: BiggestInt):
      ReturnType {.closure, gcsafe.}

  HttpClientBase*[SocketType] = ref object
    socket: SocketType
    connected: bool
    currentURL: Uri ## Where we are currently connected.
    headers*: HttpHeaders ## Headers to send in requests.
    maxRedirects: int
    userAgent: string
    timeout: int ## Only used for blocking HttpClient for now.
    proxy: Proxy
    ## ``nil`` or the callback to call when request progress changes.
    when SocketType is Socket:
      onProgressChanged*: ProgressChangedProc[void]
    else:
      onProgressChanged*: ProgressChangedProc[Future[void]]
    when defined(ssl):
      sslContext: net.SslContext
    contentTotal: BiggestInt
    contentProgress: BiggestInt
    oneSecondProgress: BiggestInt
    lastProgressReport: float

type
  HttpClient* = HttpClientBase[Socket]

proc newHttpClient*(userAgent = defUserAgent,
    maxRedirects = 5, sslContext = defaultSslContext, proxy: Proxy = nil,
    timeout = -1): HttpClient =
  ## Creates a new HttpClient instance.
  ##
  ## ``userAgent`` specifies the user agent that will be used when making
  ## requests.
  ##
  ## ``maxRedirects`` specifies the maximum amount of redirects to follow,
  ## default is 5.
  ##
  ## ``sslContext`` specifies the SSL context to use for HTTPS requests.
  ##
  ## ``proxy`` specifies an HTTP proxy to use for this HTTP client's
  ## connections.
  ##
  ## ``timeout`` specifies the number of milliseconds to allow before a
  ## ``TimeoutError`` is raised.
  new result
  result.headers = newHttpHeaders()
  result.userAgent = userAgent
  result.maxRedirects = maxRedirects
  result.proxy = proxy
  result.timeout = timeout
  result.onProgressChanged = nil
  when defined(ssl):
    result.sslContext = sslContext

type
  AsyncHttpClient* = HttpClientBase[AsyncSocket]

{.deprecated: [PAsyncHttpClient: AsyncHttpClient].}

proc newAsyncHttpClient*(userAgent = defUserAgent,
    maxRedirects = 5, sslContext = defaultSslContext,
    proxy: Proxy = nil): AsyncHttpClient =
  ## Creates a new AsyncHttpClient instance.
  ##
  ## ``userAgent`` specifies the user agent that will be used when making
  ## requests.
  ##
  ## ``maxRedirects`` specifies the maximum amount of redirects to follow,
  ## default is 5.
  ##
  ## ``sslContext`` specifies the SSL context to use for HTTPS requests.
  ##
  ## ``proxy`` specifies an HTTP proxy to use for this HTTP client's
  ## connections.
  new result
  result.headers = newHttpHeaders()
  result.userAgent = userAgent
  result.maxRedirects = maxRedirects
  result.proxy = proxy
  result.timeout = -1 # TODO
  result.onProgressChanged = nil
  when defined(ssl):
    result.sslContext = sslContext

proc close*(client: HttpClient | AsyncHttpClient) =
  ## Closes any connections held by the HTTP client.
  if client.connected:
    client.socket.close()
    client.connected = false

proc reportProgress(client: HttpClient | AsyncHttpClient,
                    progress: BiggestInt) {.multisync.} =
  client.contentProgress += progress
  client.oneSecondProgress += progress
  if epochTime() - client.lastProgressReport >= 1.0:
    if not client.onProgressChanged.isNil:
      await client.onProgressChanged(client.contentTotal,
                                     client.contentProgress,
                                     client.oneSecondProgress)
      client.oneSecondProgress = 0
      client.lastProgressReport = epochTime()

proc recvFull(client: HttpClient | AsyncHttpClient,
              size: int, timeout: int): Future[string] {.multisync.} =
  ## Ensures that all the data requested is read and returned.
  result = ""
  while true:
    if size == result.len: break

    let remainingSize = size - result.len
    let sizeToRecv = min(remainingSize, net.BufferSize)

    when client.socket is Socket:
      let data = client.socket.recv(sizeToRecv, timeout)
    else:
      let data = await client.socket.recv(sizeToRecv)
    if data == "": break # We've been disconnected.
    result.add data

    await reportProgress(client, data.len)

proc parseChunks(client: HttpClient | AsyncHttpClient): Future[string]
                 {.multisync.} =
  result = ""
  while true:
    var chunkSize = 0
    var chunkSizeStr = await client.socket.recvLine()
    var i = 0
    if chunkSizeStr == "":
      httpError("Server terminated connection prematurely")
    while true:
      case chunkSizeStr[i]
      of '0'..'9':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('0'))
      of 'a'..'f':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('a') + 10)
      of 'A'..'F':
        chunkSize = chunkSize shl 4 or (ord(chunkSizeStr[i]) - ord('A') + 10)
      of '\0':
        break
      of ';':
        # http://tools.ietf.org/html/rfc2616#section-3.6.1
        # We don't care about chunk-extensions.
        break
      else:
        httpError("Invalid chunk size: " & chunkSizeStr)
      inc(i)
    if chunkSize <= 0:
      discard await recvFull(client, 2, client.timeout) # Skip \c\L
      break
    result.add await recvFull(client, chunkSize, client.timeout)
    discard await recvFull(client, 2, client.timeout) # Skip \c\L
    # Trailer headers will only be sent if the request specifies that we want
    # them: http://tools.ietf.org/html/rfc2616#section-3.6.1

proc parseBody(client: HttpClient | AsyncHttpClient,
               headers: HttpHeaders,
               httpVersion: string): Future[string] {.multisync.} =
  result = ""
  # Reset progress from previous requests.
  client.contentTotal = 0
  client.contentProgress = 0
  client.oneSecondProgress = 0
  client.lastProgressReport = 0

  if headers.getOrDefault"Transfer-Encoding" == "chunked":
    result = await parseChunks(client)
  else:
    # -REGION- Content-Length
    # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.3
    var contentLengthHeader = headers.getOrDefault"Content-Length"
    if contentLengthHeader != "":
      var length = contentLengthHeader.parseint()
      client.contentTotal = length
      if length > 0:
        result = await client.recvFull(length, client.timeout)
        if result == "":
          httpError("Got disconnected while trying to read body.")
        if result.len != length:
          httpError("Received length doesn't match expected length. Wanted " &
                    $length & " got " & $result.len)
    else:
      # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.4 TODO

      # -REGION- Connection: Close
      # (http://tools.ietf.org/html/rfc2616#section-4.4) NR.5
      if headers.getOrDefault"Connection" == "close" or httpVersion == "1.0":
        var buf = ""
        while true:
          buf = await client.recvFull(4000, client.timeout)
          if buf == "": break
          result.add(buf)

proc parseResponse(client: HttpClient | AsyncHttpClient,
                   getBody: bool): Future[Response] {.multisync.} =
  var parsedStatus = false
  var linei = 0
  var fullyRead = false
  var line = ""
  result.headers = newHttpHeaders()
  while true:
    linei = 0
    when client is HttpClient:
      line = await client.socket.recvLine(client.timeout)
    else:
      line = await client.socket.recvLine()
    if line == "": break # We've been disconnected.
    if line == "\c\L":
      fullyRead = true
      break
    if not parsedStatus:
      # Parse HTTP version info and status code.
      var le = skipIgnoreCase(line, "HTTP/", linei)
      if le <= 0:
        httpError("invalid http version, " & line.repr)
      inc(linei, le)
      le = skipIgnoreCase(line, "1.1", linei)
      if le > 0: result.version = "1.1"
      else:
        le = skipIgnoreCase(line, "1.0", linei)
        if le <= 0: httpError("unsupported http version")
        result.version = "1.0"
      inc(linei, le)
      # Status code
      linei.inc skipWhitespace(line, linei)
      result.status = line[linei .. ^1]
      parsedStatus = true
    else:
      # Parse headers
      var name = ""
      var le = parseUntil(line, name, ':', linei)
      if le <= 0: httpError("invalid headers")
      inc(linei, le)
      if line[linei] != ':': httpError("invalid headers")
      inc(linei) # Skip :

      result.headers[name] = line[linei.. ^1].strip()
      if result.headers.len > headerLimit:
        httpError("too many headers")

  if not fullyRead:
    httpError("Connection was closed before full request has been made")
  if getBody:
    result.body = await parseBody(client, result.headers, result.version)
  else:
    result.body = ""

proc newConnection(client: HttpClient | AsyncHttpClient,
                   url: Uri) {.multisync.} =
  if client.currentURL.hostname != url.hostname or
      client.currentURL.scheme != url.scheme or
      client.currentURL.port != url.port:
    if client.connected:
      client.close()

    when client is HttpClient:
      client.socket = newSocket()
    elif client is AsyncHttpClient:
      client.socket = newAsyncSocket()
    else: {.fatal: "Unsupported client type".}

    # TODO: I should be able to write 'net.Port' here...
    let port =
      if url.port == "":
        if url.scheme.toLower() == "https":
          nativesockets.Port(443)
        else:
          nativesockets.Port(80)
      else: nativesockets.Port(url.port.parseInt)

    if url.scheme.toLower() == "https":
      when defined(ssl):
        client.sslContext.wrapSocket(client.socket)
      else:
        raise newException(HttpRequestError,
                  "SSL support is not available. Cannot connect over SSL.")

    await client.socket.connect(url.hostname, port)
    client.currentURL = url
    client.connected = true

proc override(fallback, override: HttpHeaders): HttpHeaders =
  # Right-biased map union for `HttpHeaders`
  if override.isNil:
    return fallback

  result = newHttpHeaders()
  # Copy by value
  result.table[] = fallback.table[]
  for k, vs in override.table:
    result[k] = vs

proc requestAux(client: HttpClient | AsyncHttpClient, url: string,
              httpMethod: string, body = "",
              headers: HttpHeaders = nil): Future[Response] {.multisync.} =
  # Helper that actually makes the request. Does not handle redirects.
  let connectionUrl =
    if client.proxy.isNil: parseUri(url) else: client.proxy.url
  let requestUrl = parseUri(url)

  let savedProxy = client.proxy # client's proxy may be overwritten.

  if requestUrl.scheme == "https" and not client.proxy.isNil:
    when defined(ssl):
      client.proxy.url = connectionUrl
      var connectUrl = requestUrl
      connectUrl.scheme = "http"
      connectUrl.port = "443"
      let proxyResp = await requestAux(client, $connectUrl, $HttpConnect)

      if not proxyResp.status.startsWith("200"):
        raise newException(HttpRequestError,
                           "The proxy server rejected a CONNECT request, " &
                           "so a secure connection could not be established.")
      client.sslContext.wrapConnectedSocket(client.socket, handshakeAsClient)
      client.proxy = nil
    else:
      raise newException(HttpRequestError,
          "SSL support not available. Cannot connect to https site over proxy.")
  else:
    await newConnection(client, connectionUrl)

  let effectiveHeaders = client.headers.override(headers)

  if not effectiveHeaders.hasKey("user-agent") and client.userAgent != "":
    effectiveHeaders["User-Agent"] = client.userAgent

  var headersString = generateHeaders(requestUrl, httpMethod,
                                      effectiveHeaders, body, client.proxy)

  await client.socket.send(headersString)
  if body != "":
    await client.socket.send(body)

  result = await parseResponse(client,
                               httpMethod.toLower() notin ["head", "connect"])

  # Restore the clients proxy in case it was overwritten.
  client.proxy = savedProxy


proc request*(client: HttpClient | AsyncHttpClient, url: string,
              httpMethod: string, body = "",
              headers: HttpHeaders = nil): Future[Response] {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a request
  ## using the custom method string specified by ``httpMethod``.
  ##
  ## Connection will kept alive. Further requests on the same ``client`` to
  ## the same hostname will not require a new connection to be made. The
  ## connection can be closed by using the ``close`` procedure.
  ##
  ## This procedure will follow redirects up to a maximum number of redirects
  ## specified in ``client.maxRedirects``.
  result = await client.requestAux(url, httpMethod, body, headers)

  var lastURL = url
  for i in 1..client.maxRedirects:
    if result.status.redirection():
      let redirectTo = getNewLocation(lastURL, result.headers)
      result = await client.request(redirectTo, httpMethod, body, headers)
      lastURL = redirectTo


proc request*(client: HttpClient | AsyncHttpClient, url: string,
              httpMethod = HttpGET, body = "",
              headers: HttpHeaders = nil): Future[Response] {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a request
  ## using the method specified.
  ##
  ## Connection will be kept alive. Further requests on the same ``client`` to
  ## the same hostname will not require a new connection to be made. The
  ## connection can be closed by using the ``close`` procedure.
  ##
  ## When a request is made to a different hostname, the current connection will
  ## be closed.
  result = await request(client, url, $httpMethod, body,
                         headers = headers)

proc get*(client: HttpClient | AsyncHttpClient,
          url: string): Future[Response] {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a GET request.
  ##
  ## This procedure will follow redirects up to a maximum number of redirects
  ## specified in ``client.maxRedirects``.
  result = await client.request(url, HttpGET)

proc getContent*(client: HttpClient | AsyncHttpClient,
                 url: string): Future[string] {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a GET request.
  ##
  ## This procedure will follow redirects up to a maximum number of redirects
  ## specified in ``client.maxRedirects``.
  ##
  ## A ``HttpRequestError`` will be raised if the server responds with a
  ## client error (status code 4xx) or a server error (status code 5xx).
  let resp = await get(client, url)
  if resp.code.is4xx or resp.code.is5xx:
    raise newException(HttpRequestError, resp.status)
  else:
    return resp.body

proc post*(client: HttpClient | AsyncHttpClient, url: string, body = "",
           multipart: MultipartData = nil): Future[Response] {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a POST request.
  ##
  ## This procedure will follow redirects up to a maximum number of redirects
  ## specified in ``client.maxRedirects``.
  let (mpHeader, mpBody) = format(multipart)

  template withNewLine(x): expr =
    if x.len > 0 and not x.endsWith("\c\L"):
      x & "\c\L"
    else:
      x
  var xb = mpBody.withNewLine() & body

  var headers = newHttpHeaders()
  if multipart != nil:
    headers["Content-Type"] = mpHeader.split(": ")[1]
  headers["Content-Length"] = $len(xb)

  result = await client.requestAux(url, $HttpPOST, xb,
                                headers = headers)
  # Handle redirects.
  var lastURL = url
  for i in 1..client.maxRedirects:
    if result.status.redirection():
      let redirectTo = getNewLocation(lastURL, result.headers)
      var meth = if result.status != "307": HttpGet else: HttpPost
      result = await client.requestAux(redirectTo, $meth, xb,
                                    headers = headers)
      lastURL = redirectTo

proc postContent*(client: HttpClient | AsyncHttpClient, url: string,
                  body = "",
                  multipart: MultipartData = nil): Future[string]
                  {.multisync.} =
  ## Connects to the hostname specified by the URL and performs a POST request.
  ##
  ## This procedure will follow redirects up to a maximum number of redirects
  ## specified in ``client.maxRedirects``.
  ##
  ## A ``HttpRequestError`` will be raised if the server responds with a
  ## client error (status code 4xx) or a server error (status code 5xx).
  let resp = await post(client, url, body, multipart)
  if resp.code.is4xx or resp.code.is5xx:
    raise newException(HttpRequestError, resp.status)
  else:
    return resp.body
