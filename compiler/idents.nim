#
#
#           The Nim Compiler
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

# Identifier handling
# An identifier is a shared immutable string that can be compared by its
# id. This module is essential for the compiler's performance.

import
  hashes, strutils, etcpriv, wordrecg

type
  TIdObj* = object of RootObj
    id*: int # unique id; use this for comparisons and not the pointers

  PIdObj* = ref TIdObj
  PIdent* = ref TIdent
  TIdent*{.acyclic.} = object of TIdObj
    s*: string
    next*: PIdent             # for hash-table chaining
    h*: Hash                 # hash value of s

  IdentCache* = ref object
    buckets: array[0..4096 * 2 - 1, PIdent]
    wordCounter: int
    idAnon*, idDelegator*, emptyIdent*: PIdent

var
  legacy: IdentCache

proc resetIdentCache*() =
  for i in low(legacy.buckets)..high(legacy.buckets):
    legacy.buckets[i] = nil

proc cmpIgnoreStyle(a, b: cstring, blen: int): int =
  if a[0] != b[0]: return 1
  var i = 0
  var j = 0
  result = 1
  while j < blen:
    while a[i] == '_': inc(i)
    while b[j] == '_': inc(j)
    while isMagicIdentSeparatorRune(a, i): inc(i, magicIdentSeparatorRuneByteWidth)
    while isMagicIdentSeparatorRune(b, j): inc(j, magicIdentSeparatorRuneByteWidth)
    # tolower inlined:
    var aa = a[i]
    var bb = b[j]
    if aa >= 'A' and aa <= 'Z': aa = chr(ord(aa) + (ord('a') - ord('A')))
    if bb >= 'A' and bb <= 'Z': bb = chr(ord(bb) + (ord('a') - ord('A')))
    result = ord(aa) - ord(bb)
    if (result != 0) or (aa == '\0'): break
    inc(i)
    inc(j)
  if result == 0:
    if a[i] != '\0': result = 1

proc cmpExact(a, b: cstring, blen: int): int =
  var i = 0
  var j = 0
  result = 1
  while j < blen:
    var aa = a[i]
    var bb = b[j]
    result = ord(aa) - ord(bb)
    if (result != 0) or (aa == '\0'): break
    inc(i)
    inc(j)
  if result == 0:
    if a[i] != '\0': result = 1

{.this: self.}

proc getIdent*(self: IdentCache; identifier: cstring, length: int, h: Hash): PIdent =
  var idx = h and high(buckets)
  result = buckets[idx]
  var last: PIdent = nil
  var id = 0
  while result != nil:
    if cmpExact(cstring(result.s), identifier, length) == 0:
      if last != nil:
        # make access to last looked up identifier faster:
        last.next = result.next
        result.next = buckets[idx]
        buckets[idx] = result
      return
    elif cmpIgnoreStyle(cstring(result.s), identifier, length) == 0:
      assert((id == 0) or (id == result.id))
      id = result.id
    last = result
    result = result.next
  new(result)
  result.h = h
  result.s = newString(length)
  for i in countup(0, length - 1): result.s[i] = identifier[i]
  result.next = buckets[idx]
  buckets[idx] = result
  if id == 0:
    inc(wordCounter)
    result.id = -wordCounter
  else:
    result.id = id

proc getIdent*(self: IdentCache; identifier: string): PIdent =
  result = getIdent(cstring(identifier), len(identifier),
                    hashIgnoreStyle(identifier))

proc getIdent*(self: IdentCache; identifier: string, h: Hash): PIdent =
  result = getIdent(cstring(identifier), len(identifier), h)

proc newIdentCache*(): IdentCache =
  if legacy.isNil:
    result = IdentCache()
    result.idAnon = result.getIdent":anonymous"
    result.wordCounter = 1
    result.idDelegator = result.getIdent":delegator"
    result.emptyIdent = result.getIdent("")
    # initialize the keywords:
    for s in countup(succ(low(specialWords)), high(specialWords)):
      result.getIdent(specialWords[s], hashIgnoreStyle(specialWords[s])).id = ord(s)
    legacy = result
  else:
    result = legacy

proc whichKeyword*(id: PIdent): TSpecialWord =
  if id.id < 0: result = wInvalid
  else: result = TSpecialWord(id.id)

proc getIdent*(identifier: string): PIdent =
  ## for backwards compatibility.
  if legacy.isNil:
    discard newIdentCache()
  legacy.getIdent identifier
