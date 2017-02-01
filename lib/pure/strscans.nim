#
#
#            Nim's Runtime Library
#        (c) Copyright 2016 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

##[
This module contains a `scanf`:idx: macro that can be used for extracting
substrings from an input string. This is often easier than regular expressions.
Some examples as an apetizer:

.. code-block:: nim
  # check if input string matches a triple of integers:
  const input = "(1,2,4)"
  var x, y, z: int
  if scanf(input, "($i,$i,$i)", x, y, z):
    echo "matches and x is ", x, " y is ", y, " z is ", z

  # check if input string matches an ISO date followed by an identifier followed
  # by whitespace and a floating point number:
  var year, month, day: int
  var identifier: string
  var myfloat: float
  if scanf(input, "$i-$i-$i $w$s$f", year, month, day, identifier, myfloat):
    echo "yes, we have a match!"

As can be seen from the examples, strings are matched verbatim except for
substrings starting with ``$``. These constructions are available:

=================   ========================================================
``$i``              Matches an integer. This uses ``parseutils.parseInt``.
``$f``              Matches a floating pointer number. Uses ``parseFloat``.
``$w``              Matches an ASCII identifier: ``[A-Z-a-z_][A-Za-z_0-9]*``.
``$s``              Skips optional whitespace.
``$$``              Matches a single dollar sign.
``$.``              Matches if the end of the input string has been reached.
``$*``              Matches until the token following the ``$*`` was found.
                    The match is allowed to be of 0 length.
``$+``              Matches until the token following the ``$+`` was found.
                    The match must consist of at least one char.
``${foo}``          User defined matcher. Uses the proc ``foo`` to perform
                    the match. See below for more details.
``$[foo]``          Call user defined proc ``foo`` to **skip** some optional
                    parts in the input string. See below for more details.
=================   ========================================================

Even though ``$*`` and ``$+`` look similar to the regular expressions ``.*``
and ``.+`` they work quite differently, there is no non-deterministic
state machine involved and the matches are non-greedy. ``[$*]``
matches ``[xyz]`` via ``parseutils.parseUntil``.

Furthermore no backtracking is performed, if parsing fails after a value
has already been bound to a matched subexpression this value is not restored
to its original value. This rarely causes problems in practice and if it does
for you, it's easy enough to bind to a temporary variable first.


Startswith vs full match
========================

``scanf`` returns true if the input string **starts with** the specified
pattern. If instead it should only return true if theres is also nothing
left in the input, append ``$.`` to your pattern.


User definable matchers
=======================

One very nice advantage over regular expressions is that ``scanf`` is
extensible with ordinary Nim procs. The proc is either enclosed in ``${}``
or in ``$[]``. ``${}`` matches and binds the result
to a variable (that was passed to the ``scanf`` macro) while ``$[]`` merely
optional tokens.


In this example, we define a helper proc ``someSep`` that skips some separators
which we then use in our scanf pattern to help us in the matching process:

.. code-block:: nim

  proc someSep(input: string; start: int; seps: set[char] = {':','-','.'}): int =
    # Note: The parameters and return value must match to what ``scanf`` requires
    result = 0
    while input[start+result] in seps: inc result

  if scanf(input, "$w$[someSep]$w", key, value):
    ...

It also possible to pass arguments to a user definable matcher:

.. code-block:: nim

  proc ndigits(input: string; intVal: var int; start: int; n: int): int =
    # matches exactly ``n`` digits. Matchers need to return 0 if nothing
    # matched or otherwise the number of processed chars.
    var x = 0
    var i = 0
    while i < n and i+start < input.len and input[i+start] in {'0'..'9'}:
      x = x * 10 + input[i+start].ord - '0'.ord
      inc i
    # only overwrite if we had a match
    if i == n:
      result = n
      intVal = x

  # match an ISO date extracting year, month, day at the same time.
  # Also ensure the input ends after the ISO date:
  var year, month, day: int
  if scanf("2013-01-03", "${ndigits(4)}-${ndigits(2)}-${ndigits(2)}$.", year, month, day):
    ...

]##


import macros, parseutils

proc conditionsToIfChain(n, idx, res: NimNode; start: int): NimNode =
  assert n.kind == nnkStmtList
  if start >= n.len: return newAssignment(res, newLit true)
  var ifs: NimNode = nil
  if n[start+1].kind == nnkEmpty:
    ifs = conditionsToIfChain(n, idx, res, start+3)
  else:
    ifs = newIfStmt((n[start+1],
                    newTree(nnkStmtList, newCall(bindSym"inc", idx, n[start+2]),
                                     conditionsToIfChain(n, idx, res, start+3))))
  result = newTree(nnkStmtList, n[start], ifs)

proc notZero(x: NimNode): NimNode = newCall(bindSym"!=", x, newLit 0)

proc buildUserCall(x: string; args: varargs[NimNode]): NimNode =
  let y = parseExpr(x)
  result = newTree(nnkCall)
  if y.kind in nnkCallKinds: result.add y[0]
  else: result.add y
  for a in args: result.add a
  if y.kind in nnkCallKinds:
    for i in 1..<y.len: result.add y[i]

macro scanf*(input: string; pattern: static[string]; results: varargs[typed]): bool =
  ## See top level documentation of his module of how ``scanf`` works.
  template matchBind(parser) {.dirty.} =
    var resLen = genSym(nskLet, "resLen")
    conds.add newLetStmt(resLen, newCall(bindSym(parser), input, results[i], idx))
    conds.add resLen.notZero
    conds.add resLen

  var i = 0
  var p = 0
  var idx = genSym(nskVar, "idx")
  var res = genSym(nskVar, "res")
  result = newTree(nnkStmtListExpr, newVarStmt(idx, newLit 0), newVarStmt(res, newLit false))
  var conds = newTree(nnkStmtList)
  var fullMatch = false
  while p < pattern.len:
    if pattern[p] == '$':
      inc p
      case pattern[p]
      of '$':
        var resLen = genSym(nskLet, "resLen")
        conds.add newLetStmt(resLen, newCall(bindSym"skip", input, newLit($pattern[p]), idx))
        conds.add resLen.notZero
        conds.add resLen
      of 'w':
        if i < results.len or getType(results[i]).typeKind != ntyString:
          matchBind "parseIdent"
        else:
          error("no string var given for $w")
        inc i
      of 'i':
        if i < results.len or getType(results[i]).typeKind != ntyInt:
          matchBind "parseInt"
        else:
          error("no int var given for $d")
        inc i
      of 'f':
        if i < results.len or getType(results[i]).typeKind != ntyFloat:
          matchBind "parseFloat"
        else:
          error("no float var given for $f")
        inc i
      of 's':
        conds.add newCall(bindSym"inc", idx, newCall(bindSym"skipWhitespace", input, idx))
        conds.add newEmptyNode()
        conds.add newEmptyNode()
      of '.':
        if p == pattern.len-1:
          fullMatch = true
        else:
          error("invalid format string")
      of '*', '+':
        if i < results.len or getType(results[i]).typeKind != ntyString:
          var min = ord(pattern[p] == '+')
          var q=p+1
          var token = ""
          while q < pattern.len and pattern[q] != '$':
            token.add pattern[q]
            inc q
          var resLen = genSym(nskLet, "resLen")
          conds.add newLetStmt(resLen, newCall(bindSym"parseUntil", input, results[i], newLit(token), idx))
          conds.add newCall(bindSym"!=", resLen, newLit min)
          conds.add resLen
        else:
          error("no string var given for $" & pattern[p])
        inc i
      of '{':
        inc p
        var nesting = 0
        let start = p
        while true:
          case pattern[p]
          of '{': inc nesting
          of '}':
            if nesting == 0: break
            dec nesting
          of '\0': error("expected closing '}'")
          else: discard
          inc p
        let expr = pattern.substr(start, p-1)
        if i < results.len:
          var resLen = genSym(nskLet, "resLen")
          conds.add newLetStmt(resLen, buildUserCall(expr, input, results[i], idx))
          conds.add newCall(bindSym"!=", resLen, newLit 0)
          conds.add resLen
        else:
          error("no var given for $" & expr)
        inc i
      of '[':
        inc p
        var nesting = 0
        let start = p
        while true:
          case pattern[p]
          of '[': inc nesting
          of ']':
            if nesting == 0: break
            dec nesting
          of '\0': error("expected closing ']'")
          else: discard
          inc p
        let expr = pattern.substr(start, p-1)
        conds.add newCall(bindSym"inc", idx, buildUserCall(expr, input, idx))
        conds.add newEmptyNode()
        conds.add newEmptyNode()
      else: error("invalid format string")
      inc p
    else:
      var token = ""
      while p < pattern.len and pattern[p] != '$':
        token.add pattern[p]
        inc p
      var resLen = genSym(nskLet, "resLen")
      conds.add newLetStmt(resLen, newCall(bindSym"skip", input, newLit(token), idx))
      conds.add resLen.notZero
      conds.add resLen
  result.add conditionsToIfChain(conds, idx, res, 0)
  if fullMatch:
    result.add newCall(bindSym"and", res,
      newCall(bindSym">=", idx, newCall(bindSym"len", input)))
  else:
    result.add res

template atom*(input: string; idx: int; c: char): bool =
  ## Used in scanp for the matching of atoms (usually chars).
  input[idx] == c

template atom*(input: string; idx: int; s: set[char]): bool =
  input[idx] in s

#template prepare*(input: string): int = 0
template success*(x: int): bool = x != 0

template nxt*(input: string; idx, step: int = 1) = inc(idx, step)

macro scanp*(input, idx: typed; pattern: varargs[untyped]): bool =
  ## See top level documentation of his module of how ``scanp`` works.
  type StmtTriple = tuple[init, cond, action: NimNode]

  template interf(x): untyped = bindSym(x, brForceOpen)

  proc toIfChain(n: seq[StmtTriple]; idx, res: NimNode; start: int): NimNode =
    if start >= n.len: return newAssignment(res, newLit true)
    var ifs: NimNode = nil
    if n[start].cond.kind == nnkEmpty:
      ifs = toIfChain(n, idx, res, start+1)
    else:
      ifs = newIfStmt((n[start].cond,
                      newTree(nnkStmtList, n[start].action,
                              toIfChain(n, idx, res, start+1))))
    result = newTree(nnkStmtList, n[start].init, ifs)

  proc attach(x, attached: NimNode): NimNode =
    if attached == nil: x
    else: newStmtList(attached, x)

  proc placeholder(n, x, j: NimNode): NimNode =
    if n.kind == nnkPrefix and n[0].eqIdent("$"):
      let n1 = n[1]
      if n1.eqIdent"_" or n1.eqIdent"current":
        result = newTree(nnkBracketExpr, x, j)
      elif n1.eqIdent"input":
        result = x
      elif n1.eqIdent"i" or n1.eqIdent"index":
        result = j
      else:
        error("unknown pattern " & repr(n))
    else:
      result = copyNimNode(n)
      for i in 0 ..< n.len:
        result.add placeholder(n[i], x, j)

  proc atm(it, input, idx, attached: NimNode): StmtTriple =
    template `!!`(x): untyped = attach(x, attached)
    case it.kind
    of nnkIdent:
      var resLen = genSym(nskLet, "resLen")
      result = (newLetStmt(resLen, newCall(it, input, idx)),
                newCall(interf"success", resLen),
                !!newCall(interf"nxt", input, idx, resLen))
    of nnkCallKinds:
      # *{'A'..'Z'} !! s.add(!_)
      template buildWhile(init, cond, action): untyped =
        while true:
          init
          if not cond: break
          action

      # (x) a  # bind action a to (x)
      if it[0].kind == nnkPar and it.len == 2:
        result = atm(it[0], input, idx, placeholder(it[1], input, idx))
      elif it.kind == nnkInfix and it[0].eqIdent"->":
        # bind matching to some action:
        result = atm(it[1], input, idx, placeholder(it[2], input, idx))
      elif it.kind == nnkInfix and it[0].eqIdent"as":
        let cond = if it[1].kind in nnkCallKinds: placeholder(it[1], input, idx)
                   else: newCall(it[1], input, idx)
        result = (newLetStmt(it[2], cond),
                  newCall(interf"success", it[2]),
                  !!newCall(interf"nxt", input, idx, it[2]))
      elif it.kind == nnkPrefix and it[0].eqIdent"*":
        let (init, cond, action) = atm(it[1], input, idx, attached)
        result = (getAst(buildWhile(init, cond, action)),
                  newEmptyNode(), newEmptyNode())
      elif it.kind == nnkPrefix and it[0].eqIdent"+":
        # x+  is the same as  xx*
        result = atm(newTree(nnkPar, it[1], newTree(nnkPrefix, ident"*", it[1])),
                      input, idx, attached)
      elif it.kind == nnkPrefix and it[0].eqIdent"?":
        # optional.
        let (init, cond, action) = atm(it[1], input, idx, attached)
        if cond.kind == nnkEmpty:
          error("'?' operator applied to a non-condition")
        else:
          result = (newTree(nnkStmtList, init, newIfStmt((cond, action))),
                    newEmptyNode(), newEmptyNode())
      elif it.kind == nnkPrefix and it[0].eqIdent"~":
        # not operator
        let (init, cond, action) = atm(it[1], input, idx, attached)
        if cond.kind == nnkEmpty:
          error("'~' operator applied to a non-condition")
        else:
          result = (init, newCall(bindSym"not", cond), action)
      elif it.kind == nnkInfix and it[0].eqIdent"|":
        let a = atm(it[1], input, idx, attached)
        let b = atm(it[2], input, idx, attached)
        if a.cond.kind == nnkEmpty or b.cond.kind == nnkEmpty:
          error("'|' operator applied to a non-condition")
        else:
          result = (newStmtList(a.init,
                newIfStmt((a.cond, a.action), (newTree(nnkStmtListExpr, b.init, b.cond), b.action))),
              newEmptyNode(), newEmptyNode())
      elif it.kind == nnkInfix and it[0].eqIdent"^*":
        # a ^* b  is rewritten to:  (a *(b a))?
        #exprList = expr ^+ comma
        template tmp(a, b): untyped = ?(a, *(b, a))
        result = atm(getAst(tmp(it[1], it[2])), input, idx, attached)

      elif it.kind == nnkInfix and it[0].eqIdent"^+":
        # a ^* b  is rewritten to:  (a +(b a))?
        template tmp(a, b): untyped = (a, *(b, a))
        result = atm(getAst(tmp(it[1], it[2])), input, idx, attached)
      elif it.kind == nnkCommand and it.len == 2 and it[0].eqIdent"pred":
        # enforce that the wrapped call is interpreted as a predicate, not a non-terminal:
        result = (newEmptyNode(), placeholder(it[1], input, idx), newEmptyNode())
      else:
        var resLen = genSym(nskLet, "resLen")
        result = (newLetStmt(resLen, placeholder(it, input, idx)),
                  newCall(interf"success", resLen), !!newCall(interf"nxt", input, idx, resLen))
    of nnkStrLit..nnkTripleStrLit:
      var resLen = genSym(nskLet, "resLen")
      result = (newLetStmt(resLen, newCall(interf"skip", input, it, idx)),
                newCall(interf"success", resLen), !!newCall(interf"nxt", input, idx, resLen))
    of nnkCurly, nnkAccQuoted, nnkCharLit:
      result = (newEmptyNode(), newCall(interf"atom", input, idx, it), !!newCall(interf"nxt", input, idx))
    of nnkCurlyExpr:
      if it.len == 3 and it[1].kind == nnkIntLit and it[2].kind == nnkIntLit:
        var h = newTree(nnkPar, it[0])
        for count in 2..it[1].intVal: h.add(it[0])
        for count in it[1].intVal .. it[2].intVal-1: h.add(newTree(nnkPrefix, ident"?", it[0]))
        result = atm(h, input, idx, attached)
      elif it.len == 2 and it[1].kind == nnkIntLit:
        var h = newTree(nnkPar, it[0])
        for count in 2..it[1].intVal: h.add(it[0])
        result = atm(h, input, idx, attached)
      else:
        error("invalid pattern")
    of nnkPar:
      if it.len == 1:
        result = atm(it[0], input, idx, attached)
      else:
        # concatenation:
        var conds: seq[StmtTriple] = @[]
        for x in it: conds.add atm(x, input, idx, attached)
        var res = genSym(nskVar, "res")
        result = (newStmtList(newVarStmt(res, newLit false),
            toIfChain(conds, idx, res, 0)), res, newEmptyNode())
    else:
      error("invalid pattern")

  #var idx = genSym(nskVar, "idx")
  var res = genSym(nskVar, "res")
  result = newTree(nnkStmtListExpr, #newVarStmt(idx, newCall(interf"prepare", input)),
                                    newVarStmt(res, newLit false))
  var conds: seq[StmtTriple] = @[]
  for it in pattern:
    conds.add atm(it, input, idx, nil)
  result.add toIfChain(conds, idx, res, 0)
  result.add res
  when defined(debugScanp):
    echo repr result


when isMainModule:
  proc twoDigits(input: string; x: var int; start: int): int =
    if input[start] == '0' and input[start+1] == '0':
      result = 2
      x = 13
    else:
      result = 0

  proc someSep(input: string; start: int; seps: set[char] = {';',',','-','.'}): int =
    result = 0
    while input[start+result] in seps: inc result

  proc demangle(s: string; res: var string; start: int): int =
    while s[result+start] in {'_', '@'}: inc result
    res = ""
    while result+start < s.len and s[result+start] > ' ' and s[result+start] != '_':
      res.add s[result+start]
      inc result
    while result+start < s.len and s[result+start] > ' ':
      inc result

  proc parseGDB(resp: string): seq[string] =
    const
      digits = {'0'..'9'}
      hexdigits = digits + {'a'..'f', 'A'..'F'}
      whites = {' ', '\t', '\C', '\L'}
    result = @[]
    var idx = 0
    while true:
      var prc = ""
      var info = ""
      if scanp(resp, idx, *`whites`, '#', *`digits`, +`whites`, ?("0x", *`hexdigits`, " in "),
               demangle($input, prc, $index), *`whites`, '(', * ~ ')', ')',
                *`whites`, "at ", +(~{'\C', '\L', '\0'} -> info.add($_)) ):
        result.add prc & " " & info
      else:
        break

  var key, val: string
  var intval: int
  var floatval: float
  doAssert scanf("abc:: xyz 89  33.25", "$w$s::$s$w$s$i  $f", key, val, intval, floatVal)
  doAssert key == "abc"
  doAssert val == "xyz"
  doAssert intval == 89
  doAssert floatVal == 33.25

  let xx = scanf("$abc", "$$$i", intval)
  doAssert xx == false


  let xx2 = scanf("$1234", "$$$i", intval)
  doAssert xx2

  let yy = scanf(";.--Breakpoint00 [output]", "$[someSep]Breakpoint${twoDigits}$[someSep({';','.','-'})] [$+]$.", intVal, key)
  doAssert yy
  doAssert key == "output"
  doAssert intVal == 13

  var ident = ""
  var idx = 0
  let zz = scanp("foobar x x  x   xWZ", idx, +{'a'..'z'} -> add(ident, $_), *(*{' ', '\t'}, "x"), ~'U', "Z")
  doAssert zz
  doAssert ident == "foobar"

  const digits = {'0'..'9'}
  var year = 0
  var idx2 = 0
  if scanp("201655-8-9", idx2, `digits`{4,6} -> (year = year * 10 + ord($_) - ord('0')), "-8", "-9"):
    doAssert year == 201655

  const gdbOut = """
      #0  @foo_96013_1208911747@8 (x0=...)
          at c:/users/anwender/projects/nim/temp.nim:11
      #1  0x00417754 in tempInit000 () at c:/users/anwender/projects/nim/temp.nim:13
      #2  0x0041768d in NimMainInner ()
          at c:/users/anwender/projects/nim/lib/system.nim:2605
      #3  0x004176b1 in NimMain ()
          at c:/users/anwender/projects/nim/lib/system.nim:2613
      #4  0x004176db in main (argc=1, args=0x712cc8, env=0x711ca8)
          at c:/users/anwender/projects/nim/lib/system.nim:2620"""
  const result = @["foo c:/users/anwender/projects/nim/temp.nim:11",
          "tempInit000 c:/users/anwender/projects/nim/temp.nim:13",
          "NimMainInner c:/users/anwender/projects/nim/lib/system.nim:2605",
          "NimMain c:/users/anwender/projects/nim/lib/system.nim:2613",
          "main c:/users/anwender/projects/nim/lib/system.nim:2620"]
  doAssert parseGDB(gdbOut) == result
