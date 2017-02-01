#
#
#            Nim's Runtime Library
#        (c) Copyright 2015 Andreas Rumpf, Dominik Picheta
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module implements a simple high performance `JSON`:idx:
## parser. JSON (JavaScript Object Notation) is a lightweight
## data-interchange format that is easy for humans to read and write
## (unlike XML). It is easy for machines to parse and generate.
## JSON is based on a subset of the JavaScript Programming Language,
## Standard ECMA-262 3rd Edition - December 1999.
##
## Usage example:
##
## .. code-block:: nim
##  let
##    small_json = """{"test": 1.3, "key2": true}"""
##    jobj = parseJson(small_json)
##  assert (jobj.kind == JObject)\
##  jobj["test"] = newJFloat(0.7)  # create or update
##  echo($jobj["test"].fnum)
##  echo($jobj["key2"].bval)
##  echo jobj{"missing key"}.getFNum(0.1)  # read a float value using a default
##  jobj{"a", "b", "c"} = newJFloat(3.3)  # created nested keys
##
## Results in:
##
## .. code-block:: nim
##
##   1.3000000000000000e+00
##   true
##
## This module can also be used to comfortably create JSON using the `%*`
## operator:
##
## .. code-block:: nim
##
##   var hisName = "John"
##   let herAge = 31
##   var j = %*
##     [
##       {
##         "name": hisName,
##         "age": 30
##       },
##       {
##         "name": "Susan",
##         "age": herAge
##       }
##     ]
##
##    var j2 = %* {"name": "Isaac", "books": ["Robot Dreams"]}
##    j2["details"] = %* {"age":35, "pi":3.1415}
##    echo j2

import
  hashes, tables, strutils, lexbase, streams, unicode, macros

export
  tables.`$`

when defined(nimJsonGet):
  {.pragma: deprecatedGet, deprecated.}
else:
  {.pragma: deprecatedGet.}

type
  JsonEventKind* = enum  ## enumeration of all events that may occur when parsing
    jsonError,           ## an error occurred during parsing
    jsonEof,             ## end of file reached
    jsonString,          ## a string literal
    jsonInt,             ## an integer literal
    jsonFloat,           ## a float literal
    jsonTrue,            ## the value ``true``
    jsonFalse,           ## the value ``false``
    jsonNull,            ## the value ``null``
    jsonObjectStart,     ## start of an object: the ``{`` token
    jsonObjectEnd,       ## end of an object: the ``}`` token
    jsonArrayStart,      ## start of an array: the ``[`` token
    jsonArrayEnd         ## start of an array: the ``]`` token

  TokKind = enum         # must be synchronized with TJsonEventKind!
    tkError,
    tkEof,
    tkString,
    tkInt,
    tkFloat,
    tkTrue,
    tkFalse,
    tkNull,
    tkCurlyLe,
    tkCurlyRi,
    tkBracketLe,
    tkBracketRi,
    tkColon,
    tkComma

  JsonError* = enum        ## enumeration that lists all errors that can occur
    errNone,               ## no error
    errInvalidToken,       ## invalid token
    errStringExpected,     ## string expected
    errColonExpected,      ## ``:`` expected
    errCommaExpected,      ## ``,`` expected
    errBracketRiExpected,  ## ``]`` expected
    errCurlyRiExpected,    ## ``}`` expected
    errQuoteExpected,      ## ``"`` or ``'`` expected
    errEOC_Expected,       ## ``*/`` expected
    errEofExpected,        ## EOF expected
    errExprExpected        ## expr expected

  ParserState = enum
    stateEof, stateStart, stateObject, stateArray, stateExpectArrayComma,
    stateExpectObjectComma, stateExpectColon, stateExpectValue

  JsonParser* = object of BaseLexer ## the parser object.
    a: string
    tok: TokKind
    kind: JsonEventKind
    err: JsonError
    state: seq[ParserState]
    filename: string

{.deprecated: [TJsonEventKind: JsonEventKind, TJsonError: JsonError,
  TJsonParser: JsonParser, TTokKind: TokKind].}

const
  errorMessages: array[JsonError, string] = [
    "no error",
    "invalid token",
    "string expected",
    "':' expected",
    "',' expected",
    "']' expected",
    "'}' expected",
    "'\"' or \"'\" expected",
    "'*/' expected",
    "EOF expected",
    "expression expected"
  ]
  tokToStr: array[TokKind, string] = [
    "invalid token",
    "EOF",
    "string literal",
    "int literal",
    "float literal",
    "true",
    "false",
    "null",
    "{", "}", "[", "]", ":", ","
  ]

proc open*(my: var JsonParser, input: Stream, filename: string) =
  ## initializes the parser with an input stream. `Filename` is only used
  ## for nice error messages.
  lexbase.open(my, input)
  my.filename = filename
  my.state = @[stateStart]
  my.kind = jsonError
  my.a = ""

proc close*(my: var JsonParser) {.inline.} =
  ## closes the parser `my` and its associated input stream.
  lexbase.close(my)

proc str*(my: JsonParser): string {.inline.} =
  ## returns the character data for the events: ``jsonInt``, ``jsonFloat``,
  ## ``jsonString``
  assert(my.kind in {jsonInt, jsonFloat, jsonString})
  return my.a

proc getInt*(my: JsonParser): BiggestInt {.inline.} =
  ## returns the number for the event: ``jsonInt``
  assert(my.kind == jsonInt)
  return parseBiggestInt(my.a)

proc getFloat*(my: JsonParser): float {.inline.} =
  ## returns the number for the event: ``jsonFloat``
  assert(my.kind == jsonFloat)
  return parseFloat(my.a)

proc kind*(my: JsonParser): JsonEventKind {.inline.} =
  ## returns the current event type for the JSON parser
  return my.kind

proc getColumn*(my: JsonParser): int {.inline.} =
  ## get the current column the parser has arrived at.
  result = getColNumber(my, my.bufpos)

proc getLine*(my: JsonParser): int {.inline.} =
  ## get the current line the parser has arrived at.
  result = my.lineNumber

proc getFilename*(my: JsonParser): string {.inline.} =
  ## get the filename of the file that the parser processes.
  result = my.filename

proc errorMsg*(my: JsonParser): string =
  ## returns a helpful error message for the event ``jsonError``
  assert(my.kind == jsonError)
  result = "$1($2, $3) Error: $4" % [
    my.filename, $getLine(my), $getColumn(my), errorMessages[my.err]]

proc errorMsgExpected*(my: JsonParser, e: string): string =
  ## returns an error message "`e` expected" in the same format as the
  ## other error messages
  result = "$1($2, $3) Error: $4" % [
    my.filename, $getLine(my), $getColumn(my), e & " expected"]

proc handleHexChar(c: char, x: var int): bool =
  result = true # Success
  case c
  of '0'..'9': x = (x shl 4) or (ord(c) - ord('0'))
  of 'a'..'f': x = (x shl 4) or (ord(c) - ord('a') + 10)
  of 'A'..'F': x = (x shl 4) or (ord(c) - ord('A') + 10)
  else: result = false # error

proc parseEscapedUTF16(buf: cstring, pos: var int): int =
  result = 0
  #UTF-16 escape is always 4 bytes.
  for _ in 0..3:
    if handleHexChar(buf[pos], result):
      inc(pos)
    else:
      return -1

proc parseString(my: var JsonParser): TokKind =
  result = tkString
  var pos = my.bufpos + 1
  var buf = my.buf
  while true:
    case buf[pos]
    of '\0':
      my.err = errQuoteExpected
      result = tkError
      break
    of '"':
      inc(pos)
      break
    of '\\':
      case buf[pos+1]
      of '\\', '"', '\'', '/':
        add(my.a, buf[pos+1])
        inc(pos, 2)
      of 'b':
        add(my.a, '\b')
        inc(pos, 2)
      of 'f':
        add(my.a, '\f')
        inc(pos, 2)
      of 'n':
        add(my.a, '\L')
        inc(pos, 2)
      of 'r':
        add(my.a, '\C')
        inc(pos, 2)
      of 't':
        add(my.a, '\t')
        inc(pos, 2)
      of 'u':
        inc(pos, 2)
        var r = parseEscapedUTF16(buf, pos)
        if r < 0:
          my.err = errInvalidToken
          break
        # Deal with surrogates
        if (r and 0xfc00) == 0xd800:
          if buf[pos] & buf[pos+1] != "\\u":
            my.err = errInvalidToken
            break
          inc(pos, 2)
          var s = parseEscapedUTF16(buf, pos)
          if (s and 0xfc00) == 0xdc00 and s > 0:
            r = 0x10000 + (((r - 0xd800) shl 10) or (s - 0xdc00))
          else:
            my.err = errInvalidToken
            break
        add(my.a, toUTF8(Rune(r)))
      else:
        # don't bother with the error
        add(my.a, buf[pos])
        inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
      buf = my.buf
      add(my.a, '\c')
    of '\L':
      pos = lexbase.handleLF(my, pos)
      buf = my.buf
      add(my.a, '\L')
    else:
      add(my.a, buf[pos])
      inc(pos)
  my.bufpos = pos # store back

proc skip(my: var JsonParser) =
  var pos = my.bufpos
  var buf = my.buf
  while true:
    case buf[pos]
    of '/':
      if buf[pos+1] == '/':
        # skip line comment:
        inc(pos, 2)
        while true:
          case buf[pos]
          of '\0':
            break
          of '\c':
            pos = lexbase.handleCR(my, pos)
            buf = my.buf
            break
          of '\L':
            pos = lexbase.handleLF(my, pos)
            buf = my.buf
            break
          else:
            inc(pos)
      elif buf[pos+1] == '*':
        # skip long comment:
        inc(pos, 2)
        while true:
          case buf[pos]
          of '\0':
            my.err = errEOC_Expected
            break
          of '\c':
            pos = lexbase.handleCR(my, pos)
            buf = my.buf
          of '\L':
            pos = lexbase.handleLF(my, pos)
            buf = my.buf
          of '*':
            inc(pos)
            if buf[pos] == '/':
              inc(pos)
              break
          else:
            inc(pos)
      else:
        break
    of ' ', '\t':
      inc(pos)
    of '\c':
      pos = lexbase.handleCR(my, pos)
      buf = my.buf
    of '\L':
      pos = lexbase.handleLF(my, pos)
      buf = my.buf
    else:
      break
  my.bufpos = pos

proc parseNumber(my: var JsonParser) =
  var pos = my.bufpos
  var buf = my.buf
  if buf[pos] == '-':
    add(my.a, '-')
    inc(pos)
  if buf[pos] == '.':
    add(my.a, "0.")
    inc(pos)
  else:
    while buf[pos] in Digits:
      add(my.a, buf[pos])
      inc(pos)
    if buf[pos] == '.':
      add(my.a, '.')
      inc(pos)
  # digits after the dot:
  while buf[pos] in Digits:
    add(my.a, buf[pos])
    inc(pos)
  if buf[pos] in {'E', 'e'}:
    add(my.a, buf[pos])
    inc(pos)
    if buf[pos] in {'+', '-'}:
      add(my.a, buf[pos])
      inc(pos)
    while buf[pos] in Digits:
      add(my.a, buf[pos])
      inc(pos)
  my.bufpos = pos

proc parseName(my: var JsonParser) =
  var pos = my.bufpos
  var buf = my.buf
  if buf[pos] in IdentStartChars:
    while buf[pos] in IdentChars:
      add(my.a, buf[pos])
      inc(pos)
  my.bufpos = pos

proc getTok(my: var JsonParser): TokKind =
  setLen(my.a, 0)
  skip(my) # skip whitespace, comments
  case my.buf[my.bufpos]
  of '-', '.', '0'..'9':
    parseNumber(my)
    if {'.', 'e', 'E'} in my.a:
      result = tkFloat
    else:
      result = tkInt
  of '"':
    result = parseString(my)
  of '[':
    inc(my.bufpos)
    result = tkBracketLe
  of '{':
    inc(my.bufpos)
    result = tkCurlyLe
  of ']':
    inc(my.bufpos)
    result = tkBracketRi
  of '}':
    inc(my.bufpos)
    result = tkCurlyRi
  of ',':
    inc(my.bufpos)
    result = tkComma
  of ':':
    inc(my.bufpos)
    result = tkColon
  of '\0':
    result = tkEof
  of 'a'..'z', 'A'..'Z', '_':
    parseName(my)
    case my.a
    of "null": result = tkNull
    of "true": result = tkTrue
    of "false": result = tkFalse
    else: result = tkError
  else:
    inc(my.bufpos)
    result = tkError
  my.tok = result

proc next*(my: var JsonParser) =
  ## retrieves the first/next event. This controls the parser.
  var tk = getTok(my)
  var i = my.state.len-1
  # the following code is a state machine. If we had proper coroutines,
  # the code could be much simpler.
  case my.state[i]
  of stateEof:
    if tk == tkEof:
      my.kind = jsonEof
    else:
      my.kind = jsonError
      my.err = errEofExpected
  of stateStart:
    # tokens allowed?
    case tk
    of tkString, tkInt, tkFloat, tkTrue, tkFalse, tkNull:
      my.state[i] = stateEof # expect EOF next!
      my.kind = JsonEventKind(ord(tk))
    of tkBracketLe:
      my.state.add(stateArray) # we expect any
      my.kind = jsonArrayStart
    of tkCurlyLe:
      my.state.add(stateObject)
      my.kind = jsonObjectStart
    of tkEof:
      my.kind = jsonEof
    else:
      my.kind = jsonError
      my.err = errEofExpected
  of stateObject:
    case tk
    of tkString, tkInt, tkFloat, tkTrue, tkFalse, tkNull:
      my.state.add(stateExpectColon)
      my.kind = JsonEventKind(ord(tk))
    of tkBracketLe:
      my.state.add(stateExpectColon)
      my.state.add(stateArray)
      my.kind = jsonArrayStart
    of tkCurlyLe:
      my.state.add(stateExpectColon)
      my.state.add(stateObject)
      my.kind = jsonObjectStart
    of tkCurlyRi:
      my.kind = jsonObjectEnd
      discard my.state.pop()
    else:
      my.kind = jsonError
      my.err = errCurlyRiExpected
  of stateArray:
    case tk
    of tkString, tkInt, tkFloat, tkTrue, tkFalse, tkNull:
      my.state.add(stateExpectArrayComma) # expect value next!
      my.kind = JsonEventKind(ord(tk))
    of tkBracketLe:
      my.state.add(stateExpectArrayComma)
      my.state.add(stateArray)
      my.kind = jsonArrayStart
    of tkCurlyLe:
      my.state.add(stateExpectArrayComma)
      my.state.add(stateObject)
      my.kind = jsonObjectStart
    of tkBracketRi:
      my.kind = jsonArrayEnd
      discard my.state.pop()
    else:
      my.kind = jsonError
      my.err = errBracketRiExpected
  of stateExpectArrayComma:
    case tk
    of tkComma:
      discard my.state.pop()
      next(my)
    of tkBracketRi:
      my.kind = jsonArrayEnd
      discard my.state.pop() # pop stateExpectArrayComma
      discard my.state.pop() # pop stateArray
    else:
      my.kind = jsonError
      my.err = errBracketRiExpected
  of stateExpectObjectComma:
    case tk
    of tkComma:
      discard my.state.pop()
      next(my)
    of tkCurlyRi:
      my.kind = jsonObjectEnd
      discard my.state.pop() # pop stateExpectObjectComma
      discard my.state.pop() # pop stateObject
    else:
      my.kind = jsonError
      my.err = errCurlyRiExpected
  of stateExpectColon:
    case tk
    of tkColon:
      my.state[i] = stateExpectValue
      next(my)
    else:
      my.kind = jsonError
      my.err = errColonExpected
  of stateExpectValue:
    case tk
    of tkString, tkInt, tkFloat, tkTrue, tkFalse, tkNull:
      my.state[i] = stateExpectObjectComma
      my.kind = JsonEventKind(ord(tk))
    of tkBracketLe:
      my.state[i] = stateExpectObjectComma
      my.state.add(stateArray)
      my.kind = jsonArrayStart
    of tkCurlyLe:
      my.state[i] = stateExpectObjectComma
      my.state.add(stateObject)
      my.kind = jsonObjectStart
    else:
      my.kind = jsonError
      my.err = errExprExpected


# ------------- higher level interface ---------------------------------------

type
  JsonNodeKind* = enum ## possible JSON node types
    JNull,
    JBool,
    JInt,
    JFloat,
    JString,
    JObject,
    JArray

  JsonNode* = ref JsonNodeObj ## JSON node
  JsonNodeObj* {.acyclic.} = object
    case kind*: JsonNodeKind
    of JString:
      str*: string
    of JInt:
      num*: BiggestInt
    of JFloat:
      fnum*: float
    of JBool:
      bval*: bool
    of JNull:
      nil
    of JObject:
      fields*: OrderedTable[string, JsonNode]
    of JArray:
      elems*: seq[JsonNode]

  JsonParsingError* = object of ValueError ## is raised for a JSON error

{.deprecated: [EJsonParsingError: JsonParsingError, TJsonNode: JsonNodeObj,
    PJsonNode: JsonNode, TJsonNodeKind: JsonNodeKind].}

proc raiseParseErr*(p: JsonParser, msg: string) {.noinline, noreturn.} =
  ## raises an `EJsonParsingError` exception.
  raise newException(JsonParsingError, errorMsgExpected(p, msg))

proc newJString*(s: string): JsonNode =
  ## Creates a new `JString JsonNode`.
  new(result)
  result.kind = JString
  result.str = s

proc newJStringMove(s: string): JsonNode =
  new(result)
  result.kind = JString
  shallowCopy(result.str, s)

proc newJInt*(n: BiggestInt): JsonNode =
  ## Creates a new `JInt JsonNode`.
  new(result)
  result.kind = JInt
  result.num  = n

proc newJFloat*(n: float): JsonNode =
  ## Creates a new `JFloat JsonNode`.
  new(result)
  result.kind = JFloat
  result.fnum  = n

proc newJBool*(b: bool): JsonNode =
  ## Creates a new `JBool JsonNode`.
  new(result)
  result.kind = JBool
  result.bval = b

proc newJNull*(): JsonNode =
  ## Creates a new `JNull JsonNode`.
  new(result)

proc newJObject*(): JsonNode =
  ## Creates a new `JObject JsonNode`
  new(result)
  result.kind = JObject
  result.fields = initOrderedTable[string, JsonNode](4)

proc newJArray*(): JsonNode =
  ## Creates a new `JArray JsonNode`
  new(result)
  result.kind = JArray
  result.elems = @[]

proc getStr*(n: JsonNode, default: string = ""): string =
  ## Retrieves the string value of a `JString JsonNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``JString``, or if ``n`` is nil.
  if n.isNil or n.kind != JString: return default
  else: return n.str

proc getNum*(n: JsonNode, default: BiggestInt = 0): BiggestInt =
  ## Retrieves the int value of a `JInt JsonNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``JInt``, or if ``n`` is nil.
  if n.isNil or n.kind != JInt: return default
  else: return n.num

proc getFNum*(n: JsonNode, default: float = 0.0): float =
  ## Retrieves the float value of a `JFloat JsonNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``JFloat`` or ``JInt``, or if ``n`` is nil.
  if n.isNil: return default
  case n.kind
  of JFloat: return n.fnum
  of JInt: return float(n.num)
  else: return default

proc getBVal*(n: JsonNode, default: bool = false): bool =
  ## Retrieves the bool value of a `JBool JsonNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``JBool``, or if ``n`` is nil.
  if n.isNil or n.kind != JBool: return default
  else: return n.bval

proc getFields*(n: JsonNode,
    default = initOrderedTable[string, JsonNode](4)):
        OrderedTable[string, JsonNode] =
  ## Retrieves the key, value pairs of a `JObject JsonNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``JObject``, or if ``n`` is nil.
  if n.isNil or n.kind != JObject: return default
  else: return n.fields

proc getElems*(n: JsonNode, default: seq[JsonNode] = @[]): seq[JsonNode] =
  ## Retrieves the int value of a `JArray JsonNode`.
  ##
  ## Returns ``default`` if ``n`` is not a ``JArray``, or if ``n`` is nil.
  if n.isNil or n.kind != JArray: return default
  else: return n.elems

proc `%`*(s: string): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JString JsonNode`.
  new(result)
  if s.isNil: return
  result.kind = JString
  result.str = s

proc `%`*(n: BiggestInt): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JInt JsonNode`.
  new(result)
  result.kind = JInt
  result.num  = n

proc `%`*(n: float): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JFloat JsonNode`.
  new(result)
  result.kind = JFloat
  result.fnum  = n

proc `%`*(b: bool): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JBool JsonNode`.
  new(result)
  result.kind = JBool
  result.bval = b

proc `%`*(keyVals: openArray[tuple[key: string, val: JsonNode]]): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNode`
  if keyvals.len == 0: return newJArray()
  result = newJObject()
  for key, val in items(keyVals): result.fields[key] = val

template `%`*(j: JsonNode): JsonNode = j

proc `%`*[T](elements: openArray[T]): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JArray JsonNode`
  result = newJArray()
  for elem in elements: result.add(%elem)

proc `%`*(o: object): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNode`
  result = newJObject()
  for k, v in o.fieldPairs: result[k] = %v

proc `%`*(o: ref object): JsonNode =
  ## Generic constructor for JSON data. Creates a new `JObject JsonNode`
  if o.isNil:
    result = newJNull()
  else:
    result = %(o[])

proc toJson(x: NimNode): NimNode {.compiletime.} =
  case x.kind
  of nnkBracket: # array
    result = newNimNode(nnkBracket)
    for i in 0 .. <x.len:
      result.add(toJson(x[i]))

  of nnkTableConstr: # object
    result = newNimNode(nnkTableConstr)
    for i in 0 .. <x.len:
      x[i].expectKind nnkExprColonExpr
      result.add(newNimNode(nnkExprColonExpr).add(x[i][0]).add(toJson(x[i][1])))

  of nnkCurly: # empty object
    result = newNimNode(nnkTableConstr)
    x.expectLen(0)

  of nnkNilLit:
    result = newCall("newJNull")

  else:
    result = x

  result = prefix(result, "%")

macro `%*`*(x: untyped): untyped =
  ## Convert an expression to a JsonNode directly, without having to specify
  ## `%` for every element.
  result = toJson(x)

proc `==`* (a, b: JsonNode): bool =
  ## Check two nodes for equality
  if a.isNil:
    if b.isNil: return true
    return false
  elif b.isNil or a.kind != b.kind:
    return false
  else:
    case a.kind
    of JString:
      result = a.str == b.str
    of JInt:
      result = a.num == b.num
    of JFloat:
      result = a.fnum == b.fnum
    of JBool:
      result = a.bval == b.bval
    of JNull:
      result = true
    of JArray:
      result = a.elems == b.elems
    of JObject:
     # we cannot use OrderedTable's equality here as
     # the order does not matter for equality here.
     if a.fields.len != b.fields.len: return false
     for key, val in a.fields:
       if not b.fields.hasKey(key): return false
       if b.fields[key] != val: return false
     result = true

proc hash*(n: OrderedTable[string, JsonNode]): Hash {.noSideEffect.}

proc hash*(n: JsonNode): Hash =
  ## Compute the hash for a JSON node
  case n.kind
  of JArray:
    result = hash(n.elems)
  of JObject:
    result = hash(n.fields)
  of JInt:
    result = hash(n.num)
  of JFloat:
    result = hash(n.fnum)
  of JBool:
    result = hash(n.bval.int)
  of JString:
    result = hash(n.str)
  of JNull:
    result = Hash(0)

proc hash*(n: OrderedTable[string, JsonNode]): Hash =
  for key, val in n:
    result = result xor (hash(key) !& hash(val))
  result = !$result

proc len*(n: JsonNode): int =
  ## If `n` is a `JArray`, it returns the number of elements.
  ## If `n` is a `JObject`, it returns the number of pairs.
  ## Else it returns 0.
  case n.kind
  of JArray: result = n.elems.len
  of JObject: result = n.fields.len
  else: discard

proc `[]`*(node: JsonNode, name: string): JsonNode {.inline, deprecatedGet.} =
  ## Gets a field from a `JObject`, which must not be nil.
  ## If the value at `name` does not exist, raises KeyError.
  ##
  ## **Note:** The behaviour of this procedure changed in version 0.14.0. To
  ## get a list of usages and to restore the old behaviour of this procedure,
  ## compile with the ``-d:nimJsonGet`` flag.
  assert(not isNil(node))
  assert(node.kind == JObject)
  when defined(nimJsonGet):
    if not node.fields.hasKey(name): return nil
  result = node.fields[name]

proc `[]`*(node: JsonNode, index: int): JsonNode {.inline.} =
  ## Gets the node at `index` in an Array. Result is undefined if `index`
  ## is out of bounds, but as long as array bound checks are enabled it will
  ## result in an exception.
  assert(not isNil(node))
  assert(node.kind == JArray)
  return node.elems[index]

proc hasKey*(node: JsonNode, key: string): bool =
  ## Checks if `key` exists in `node`.
  assert(node.kind == JObject)
  result = node.fields.hasKey(key)

proc contains*(node: JsonNode, key: string): bool =
  ## Checks if `key` exists in `node`.
  assert(node.kind == JObject)
  node.fields.hasKey(key)

proc contains*(node: JsonNode, val: JsonNode): bool =
  ## Checks if `val` exists in array `node`.
  assert(node.kind == JArray)
  find(node.elems, val) >= 0

proc existsKey*(node: JsonNode, key: string): bool {.deprecated.} = node.hasKey(key)
  ## Deprecated for `hasKey`

proc add*(father, child: JsonNode) =
  ## Adds `child` to a JArray node `father`.
  assert father.kind == JArray
  father.elems.add(child)

proc add*(obj: JsonNode, key: string, val: JsonNode) =
  ## Sets a field from a `JObject`.
  assert obj.kind == JObject
  obj.fields[key] = val

proc `[]=`*(obj: JsonNode, key: string, val: JsonNode) {.inline.} =
  ## Sets a field from a `JObject`.
  assert(obj.kind == JObject)
  obj.fields[key] = val

proc `{}`*(node: JsonNode, keys: varargs[string]): JsonNode =
  ## Traverses the node and gets the given value. If any of the
  ## keys do not exist, returns ``nil``. Also returns ``nil`` if one of the
  ## intermediate data structures is not an object.
  result = node
  for key in keys:
    if isNil(result) or result.kind != JObject:
      return nil
    result = result.fields.getOrDefault(key)

proc getOrDefault*(node: JsonNode, key: string): JsonNode =
  ## Gets a field from a `node`. If `node` is nil or not an object or
  ## value at `key` does not exist, returns nil
  if not isNil(node) and node.kind == JObject:
    result = node.fields.getOrDefault(key)

template simpleGetOrDefault*{`{}`(node, [key])}(node: JsonNode, key: string): JsonNode = node.getOrDefault(key)

proc `{}=`*(node: JsonNode, keys: varargs[string], value: JsonNode) =
  ## Traverses the node and tries to set the value at the given location
  ## to ``value``. If any of the keys are missing, they are added.
  var node = node
  for i in 0..(keys.len-2):
    if not node.hasKey(keys[i]):
      node[keys[i]] = newJObject()
    node = node[keys[i]]
  node[keys[keys.len-1]] = value

proc delete*(obj: JsonNode, key: string) =
  ## Deletes ``obj[key]``.
  assert(obj.kind == JObject)
  if not obj.fields.hasKey(key):
    raise newException(IndexError, "key not in object")
  obj.fields.del(key)

proc copy*(p: JsonNode): JsonNode =
  ## Performs a deep copy of `a`.
  case p.kind
  of JString:
    result = newJString(p.str)
  of JInt:
    result = newJInt(p.num)
  of JFloat:
    result = newJFloat(p.fnum)
  of JBool:
    result = newJBool(p.bval)
  of JNull:
    result = newJNull()
  of JObject:
    result = newJObject()
    for key, val in pairs(p.fields):
      result.fields[key] = copy(val)
  of JArray:
    result = newJArray()
    for i in items(p.elems):
      result.elems.add(copy(i))

# ------------- pretty printing ----------------------------------------------

proc indent(s: var string, i: int) =
  s.add(spaces(i))

proc newIndent(curr, indent: int, ml: bool): int =
  if ml: return curr + indent
  else: return indent

proc nl(s: var string, ml: bool) =
  if ml: s.add("\n")

proc escapeJson*(s: string; result: var string) =
  ## Converts a string `s` to its JSON representation.
  ## Appends to ``result``.
  const
    HexChars = "0123456789ABCDEF"
  result.add("\"")
  for x in runes(s):
    var r = int(x)
    if r >= 32 and r <= 127:
      var c = chr(r)
      case c
      of '"': result.add("\\\"")
      of '\\': result.add("\\\\")
      else: result.add(c)
    else:
      # toHex inlined for more speed (saves stupid string allocations):
      result.add("\\u0000")
      let start = result.len - 4
      for j in countdown(3, 0):
        result[j+start] = HexChars[r and 0xF]
        r = r shr 4
  result.add("\"")

proc escapeJson*(s: string): string =
  ## Converts a string `s` to its JSON representation.
  result = newStringOfCap(s.len + s.len shr 3)
  escapeJson(s, result)

proc toPretty(result: var string, node: JsonNode, indent = 2, ml = true,
              lstArr = false, currIndent = 0) =
  case node.kind
  of JObject:
    if currIndent != 0 and not lstArr: result.nl(ml)
    result.indent(currIndent) # Indentation
    if node.fields.len > 0:
      result.add("{")
      result.nl(ml) # New line
      var i = 0
      for key, val in pairs(node.fields):
        if i > 0:
          result.add(", ")
          result.nl(ml) # New Line
        inc i
        # Need to indent more than {
        result.indent(newIndent(currIndent, indent, ml))
        escapeJson(key, result)
        result.add(": ")
        toPretty(result, val, indent, ml, false,
                 newIndent(currIndent, indent, ml))
      result.nl(ml)
      result.indent(currIndent) # indent the same as {
      result.add("}")
    else:
      result.add("{}")
  of JString:
    if lstArr: result.indent(currIndent)
    escapeJson(node.str, result)
  of JInt:
    if lstArr: result.indent(currIndent)
    when defined(js): result.add($node.num)
    else: result.add(node.num)
  of JFloat:
    if lstArr: result.indent(currIndent)
    # Fixme: implement new system.add ops for the JS target
    when defined(js): result.add($node.fnum)
    else: result.add(node.fnum)
  of JBool:
    if lstArr: result.indent(currIndent)
    result.add(if node.bval: "true" else: "false")
  of JArray:
    if lstArr: result.indent(currIndent)
    if len(node.elems) != 0:
      result.add("[")
      result.nl(ml)
      for i in 0..len(node.elems)-1:
        if i > 0:
          result.add(", ")
          result.nl(ml) # New Line
        toPretty(result, node.elems[i], indent, ml,
            true, newIndent(currIndent, indent, ml))
      result.nl(ml)
      result.indent(currIndent)
      result.add("]")
    else: result.add("[]")
  of JNull:
    if lstArr: result.indent(currIndent)
    result.add("null")

proc pretty*(node: JsonNode, indent = 2): string =
  ## Returns a JSON Representation of `node`, with indentation and
  ## on multiple lines.
  result = ""
  toPretty(result, node, indent)

proc toUgly*(result: var string, node: JsonNode) =
  ## Converts `node` to its JSON Representation, without
  ## regard for human readability. Meant to improve ``$`` string
  ## conversion performance.
  ##
  ## JSON representation is stored in the passed `result`
  ##
  ## This provides higher efficiency than the ``pretty`` procedure as it
  ## does **not** attempt to format the resulting JSON to make it human readable.
  var comma = false
  case node.kind:
  of JArray:
    result.add "["
    for child in node.elems:
      if comma: result.add ","
      else:     comma = true
      result.toUgly child
    result.add "]"
  of JObject:
    result.add "{"
    for key, value in pairs(node.fields):
      if comma: result.add ","
      else:     comma = true
      key.escapeJson(result)
      result.add ":"
      result.toUgly value
    result.add "}"
  of JString:
    node.str.escapeJson(result)
  of JInt:
    when defined(js): result.add($node.num)
    else: result.add(node.num)
  of JFloat:
    when defined(js): result.add($node.fnum)
    else: result.add(node.fnum)
  of JBool:
    result.add(if node.bval: "true" else: "false")
  of JNull:
    result.add "null"

proc `$`*(node: JsonNode): string =
  ## Converts `node` to its JSON Representation on one line.
  result = newStringOfCap(node.len shl 1)
  toUgly(result, node)

iterator items*(node: JsonNode): JsonNode =
  ## Iterator for the items of `node`. `node` has to be a JArray.
  assert node.kind == JArray
  for i in items(node.elems):
    yield i

iterator mitems*(node: var JsonNode): var JsonNode =
  ## Iterator for the items of `node`. `node` has to be a JArray. Items can be
  ## modified.
  assert node.kind == JArray
  for i in mitems(node.elems):
    yield i

iterator pairs*(node: JsonNode): tuple[key: string, val: JsonNode] =
  ## Iterator for the child elements of `node`. `node` has to be a JObject.
  assert node.kind == JObject
  for key, val in pairs(node.fields):
    yield (key, val)

iterator mpairs*(node: var JsonNode): tuple[key: string, val: var JsonNode] =
  ## Iterator for the child elements of `node`. `node` has to be a JObject.
  ## Values can be modified
  assert node.kind == JObject
  for key, val in mpairs(node.fields):
    yield (key, val)

proc eat(p: var JsonParser, tok: TokKind) =
  if p.tok == tok: discard getTok(p)
  else: raiseParseErr(p, tokToStr[tok])

proc parseJson(p: var JsonParser): JsonNode =
  ## Parses JSON from a JSON Parser `p`.
  case p.tok
  of tkString:
    # we capture 'p.a' here, so we need to give it a fresh buffer afterwards:
    result = newJStringMove(p.a)
    p.a = ""
    discard getTok(p)
  of tkInt:
    result = newJInt(parseBiggestInt(p.a))
    discard getTok(p)
  of tkFloat:
    result = newJFloat(parseFloat(p.a))
    discard getTok(p)
  of tkTrue:
    result = newJBool(true)
    discard getTok(p)
  of tkFalse:
    result = newJBool(false)
    discard getTok(p)
  of tkNull:
    result = newJNull()
    discard getTok(p)
  of tkCurlyLe:
    result = newJObject()
    discard getTok(p)
    while p.tok != tkCurlyRi:
      if p.tok != tkString:
        raiseParseErr(p, "string literal as key")
      var key = p.a
      discard getTok(p)
      eat(p, tkColon)
      var val = parseJson(p)
      result[key] = val
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkCurlyRi)
  of tkBracketLe:
    result = newJArray()
    discard getTok(p)
    while p.tok != tkBracketRi:
      result.add(parseJson(p))
      if p.tok != tkComma: break
      discard getTok(p)
    eat(p, tkBracketRi)
  of tkError, tkCurlyRi, tkBracketRi, tkColon, tkComma, tkEof:
    raiseParseErr(p, "{")

when not defined(js):
  proc parseJson*(s: Stream, filename: string): JsonNode =
    ## Parses from a stream `s` into a `JsonNode`. `filename` is only needed
    ## for nice error messages.
    ## If `s` contains extra data, it will raising `JsonParsingError`.
    var p: JsonParser
    p.open(s, filename)
    defer: p.close()
    discard getTok(p) # read first token
    result = p.parseJson()
    eat(p, tkEof) # check there are no exstra data

  proc parseJson*(buffer: string): JsonNode =
    ## Parses JSON from `buffer`.
    ## If `buffer` contains extra data, it will raising `JsonParsingError`.
    result = parseJson(newStringStream(buffer), "input")

  proc parseFile*(filename: string): JsonNode =
    ## Parses `file` into a `JsonNode`.
    ## If `file` contains extra data, it will raising `JsonParsingError`.
    var stream = newFileStream(filename, fmRead)
    if stream == nil:
      raise newException(IOError, "cannot read from file: " & filename)
    result = parseJson(stream, filename)
else:
  from math import `mod`
  type
    JSObject = object
  {.deprecated: [TJSObject: JSObject].}

  proc parseNativeJson(x: cstring): JSObject {.importc: "JSON.parse".}

  proc getVarType(x: JSObject): JsonNodeKind =
    result = JNull
    proc getProtoName(y: JSObject): cstring
      {.importc: "Object.prototype.toString.call".}
    case $getProtoName(x) # TODO: Implicit returns fail here.
    of "[object Array]": return JArray
    of "[object Object]": return JObject
    of "[object Number]":
      if cast[float](x) mod 1.0 == 0:
        return JInt
      else:
        return JFloat
    of "[object Boolean]": return JBool
    of "[object Null]": return JNull
    of "[object String]": return JString
    else: assert false

  proc len(x: JSObject): int =
    assert x.getVarType == JArray
    asm """
      `result` = `x`.length;
    """

  proc `[]`(x: JSObject, y: string): JSObject =
    assert x.getVarType == JObject
    asm """
      `result` = `x`[`y`];
    """

  proc `[]`(x: JSObject, y: int): JSObject =
    assert x.getVarType == JArray
    asm """
      `result` = `x`[`y`];
    """

  proc convertObject(x: JSObject): JsonNode =
    case getVarType(x)
    of JArray:
      result = newJArray()
      for i in 0 .. <x.len:
        result.add(x[i].convertObject())
    of JObject:
      result = newJObject()
      asm """for (property in `x`) {
        if (`x`.hasOwnProperty(property)) {
      """
      var nimProperty: cstring
      var nimValue: JSObject
      asm "`nimProperty` = property; `nimValue` = `x`[property];"
      result[$nimProperty] = nimValue.convertObject()
      asm "}}"
    of JInt:
      result = newJInt(cast[int](x))
    of JFloat:
      result = newJFloat(cast[float](x))
    of JString:
      result = newJString($cast[cstring](x))
    of JBool:
      result = newJBool(cast[bool](x))
    of JNull:
      result = newJNull()

  proc parseJson*(buffer: string): JsonNode =
    return parseNativeJson(buffer).convertObject()

when false:
  import os
  var s = newFileStream(paramStr(1), fmRead)
  if s == nil: quit("cannot open the file" & paramStr(1))
  var x: JsonParser
  open(x, s, paramStr(1))
  while true:
    next(x)
    case x.kind
    of jsonError:
      Echo(x.errorMsg())
      break
    of jsonEof: break
    of jsonString, jsonInt, jsonFloat: echo(x.str)
    of jsonTrue: echo("!TRUE")
    of jsonFalse: echo("!FALSE")
    of jsonNull: echo("!NULL")
    of jsonObjectStart: echo("{")
    of jsonObjectEnd: echo("}")
    of jsonArrayStart: echo("[")
    of jsonArrayEnd: echo("]")

  close(x)

# { "json": 5 }
# To get that we shall use, obj["json"]

when isMainModule:

  let testJson = parseJson"""{ "a": [1, 2, 3, 4], "b": "asd", "c": "\ud83c\udf83", "d": "\u00E6"}"""
  # nil passthrough
  doAssert(testJson{"doesnt_exist"}{"anything"}.isNil)
  testJson{["e", "f"]} = %true
  doAssert(testJson["e"]["f"].bval)

  # make sure UTF-16 decoding works.
  when not defined(js): # TODO: The following line asserts in JS
    doAssert(testJson["c"].str == "🎃")
  doAssert(testJson["d"].str == "æ")

  # make sure no memory leek when parsing invalid string
  let startMemory = getOccupiedMem()
  for i in 0 .. 10000:
    try:
      discard parseJson"""{ invalid"""
    except:
      discard
  # memory diff should less than 2M
  doAssert(abs(getOccupiedMem() - startMemory) < 2 * 1024 * 1024)


  # test `$`
  let stringified = $testJson
  let parsedAgain = parseJson(stringified)
  doAssert(parsedAgain["b"].str == "asd")

  parsedAgain["abc"] = %5
  doAssert parsedAgain["abc"].num == 5

  # Bounds checking
  try:
    let a = testJson["a"][9]
    doAssert(false, "EInvalidIndex not thrown")
  except IndexError:
    discard
  try:
    let a = testJson["a"][-1]
    doAssert(false, "EInvalidIndex not thrown")
  except IndexError:
    discard
  try:
    doAssert(testJson["a"][0].num == 1, "Index doesn't correspond to its value")
  except:
    doAssert(false, "EInvalidIndex thrown for valid index")

  doAssert(testJson{"b"}.str=="asd", "Couldn't fetch a singly nested key with {}")
  doAssert(isNil(testJson{"nonexistent"}), "Non-existent keys should return nil")
  doAssert(isNil(testJson{"a", "b"}), "Indexing through a list should return nil")
  doAssert(isNil(testJson{"a", "b"}), "Indexing through a list should return nil")
  doAssert(testJson{"a"}==parseJson"[1, 2, 3, 4]", "Didn't return a non-JObject when there was one to be found")
  doAssert(isNil(parseJson("[1, 2, 3]"){"foo"}), "Indexing directly into a list should return nil")

  # Generator:
  var j = %* [{"name": "John", "age": 30}, {"name": "Susan", "age": 31}]
  doAssert j == %[%{"name": %"John", "age": %30}, %{"name": %"Susan", "age": %31}]

  var j2 = %*
    [
      {
        "name": "John",
        "age": 30
      },
      {
        "name": "Susan",
        "age": 31
      }
    ]
  doAssert j2 == %[%{"name": %"John", "age": %30}, %{"name": %"Susan", "age": %31}]

  var name = "John"
  let herAge = 30
  const hisAge = 31

  var j3 = %*
    [ { "name": "John"
      , "age": herAge
      }
    , { "name": "Susan"
      , "age": hisAge
      }
    ]
  doAssert j3 == %[%{"name": %"John", "age": %30}, %{"name": %"Susan", "age": %31}]

  var j4 = %*{"test": nil}
  doAssert j4 == %{"test": newJNull()}

  let seqOfNodes = @[%1, %2]
  let jSeqOfNodes = %seqOfNodes
  doAssert(jSeqOfNodes[1].num == 2)

  type MyObj = object
    a, b: int
    s: string
    f32: float32
    f64: float64
    next: ref MyObj
  var m: MyObj
  m.s = "hi"
  m.a = 5
  let jMyObj = %m
  doAssert(jMyObj["a"].num == 5)
  doAssert(jMyObj["s"].str == "hi")

  # Test loading of file.
  when not defined(js):
    echo("99% of tests finished. Going to try loading file.")
    var parsed = parseFile("tests/testdata/jsontest.json")

    try:
      discard parsed["key2"][12123]
      doAssert(false)
    except IndexError: doAssert(true)

    var parsed2 = parseFile("tests/testdata/jsontest2.json")
    doAssert(parsed2{"repository", "description"}.str=="IRC Library for Haskell", "Couldn't fetch via multiply nested key using {}")

  doAssert escapeJson("\10FoobarÄ") == "\"\\u000AFoobar\\u00C4\""

  # Test with extra data
  when not defined(js):
    try:
      discard parseJson("123 456")
      doAssert(false)
    except JsonParsingError:
      doAssert getCurrentExceptionMsg().contains(errorMessages[errEofExpected])

    try:
      discard parseFile("tests/testdata/jsonwithextradata.json")
      doAssert(false)
    except JsonParsingError:
      doAssert getCurrentExceptionMsg().contains(errorMessages[errEofExpected])

  echo("Tests succeeded!")
