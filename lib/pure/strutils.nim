#
#
#            Nim's Runtime Library
#        (c) Copyright 2012 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## This module contains various string utility routines.
## See the module `re <re.html>`_ for regular expression support.
## See the module `pegs <pegs.html>`_ for PEG support.
## This module is available for the `JavaScript target
## <backends.html#the-javascript-target>`_.

import parseutils
from math import pow, round, floor, log10
from algorithm import reverse

{.deadCodeElim: on.}

{.push debugger:off .} # the user does not want to trace a part
                       # of the standard library!

include "system/inclrtl"

{.pop.}

# Support old split with set[char]
when defined(nimOldSplit):
  {.pragma: deprecatedSplit, deprecated.}
else:
  {.pragma: deprecatedSplit.}

type
  CharSet* {.deprecated.} = set[char] # for compatibility with Nim
{.deprecated: [TCharSet: CharSet].}

const
  Whitespace* = {' ', '\t', '\v', '\r', '\l', '\f'}
    ## All the characters that count as whitespace.

  Letters* = {'A'..'Z', 'a'..'z'}
    ## the set of letters

  Digits* = {'0'..'9'}
    ## the set of digits

  HexDigits* = {'0'..'9', 'A'..'F', 'a'..'f'}
    ## the set of hexadecimal digits

  IdentChars* = {'a'..'z', 'A'..'Z', '0'..'9', '_'}
    ## the set of characters an identifier can consist of

  IdentStartChars* = {'a'..'z', 'A'..'Z', '_'}
    ## the set of characters an identifier can start with

  NewLines* = {'\13', '\10'}
    ## the set of characters a newline terminator can start with

  AllChars* = {'\x00'..'\xFF'}
    ## A set with all the possible characters.
    ##
    ## Not very useful by its own, you can use it to create *inverted* sets to
    ## make the `find() proc <#find,string,set[char],int>`_ find **invalid**
    ## characters in strings.  Example:
    ##
    ## .. code-block:: nim
    ##   let invalid = AllChars - Digits
    ##   doAssert "01234".find(invalid) == -1
    ##   doAssert "01A34".find(invalid) == 2

proc isAlphaAscii*(c: char): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsAlphaAsciiChar".}=
  ## Checks whether or not `c` is alphabetical.
  ##
  ## This checks a-z, A-Z ASCII characters only.
  return c in Letters

proc isAlphaNumeric*(c: char): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsAlphaNumericChar".}=
  ## Checks whether or not `c` is alphanumeric.
  ##
  ## This checks a-z, A-Z, 0-9 ASCII characters only.
  return c in Letters or c in Digits

proc isDigit*(c: char): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsDigitChar".}=
  ## Checks whether or not `c` is a number.
  ##
  ## This checks 0-9 ASCII characters only.
  return c in Digits

proc isSpaceAscii*(c: char): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsSpaceAsciiChar".}=
  ## Checks whether or not `c` is a whitespace character.
  return c in Whitespace

proc isLowerAscii*(c: char): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsLowerAsciiChar".}=
  ## Checks whether or not `c` is a lower case character.
  ##
  ## This checks ASCII characters only.
  return c in {'a'..'z'}

proc isUpperAscii*(c: char): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsUpperAsciiChar".}=
  ## Checks whether or not `c` is an upper case character.
  ##
  ## This checks ASCII characters only.
  return c in {'A'..'Z'}

proc isAlphaAscii*(s: string): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsAlphaAsciiStr".}=
  ## Checks whether or not `s` is alphabetical.
  ##
  ## This checks a-z, A-Z ASCII characters only.
  ## Returns true if all characters in `s` are
  ## alphabetic and there is at least one character
  ## in `s`.
  if s.len() == 0:
    return false

  result = true
  for c in s:
    result = c.isAlphaAscii() and result

proc isAlphaNumeric*(s: string): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsAlphaNumericStr".}=
  ## Checks whether or not `s` is alphanumeric.
  ##
  ## This checks a-z, A-Z, 0-9 ASCII characters only.
  ## Returns true if all characters in `s` are
  ## alpanumeric and there is at least one character
  ## in `s`.
  if s.len() == 0:
    return false

  result = true
  for c in s:
    result = c.isAlphaNumeric() and result

proc isDigit*(s: string): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsDigitStr".}=
  ## Checks whether or not `s` is a numeric value.
  ##
  ## This checks 0-9 ASCII characters only.
  ## Returns true if all characters in `s` are
  ## numeric and there is at least one character
  ## in `s`.
  if s.len() == 0:
    return false

  result = true
  for c in s:
    result = c.isDigit() and result

proc isSpaceAscii*(s: string): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsSpaceAsciiStr".}=
  ## Checks whether or not `s` is completely whitespace.
  ##
  ## Returns true if all characters in `s` are whitespace
  ## characters and there is at least one character in `s`.
  if s.len() == 0:
    return false

  result = true
  for c in s:
    if not c.isSpaceAscii():
      return false

proc isLowerAscii*(s: string): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsLowerAsciiStr".}=
  ## Checks whether or not `s` contains all lower case characters.
  ##
  ## This checks ASCII characters only.
  ## Returns true if all characters in `s` are lower case
  ## and there is at least one character  in `s`.
  if s.len() == 0:
    return false

  for c in s:
    if not c.isLowerAscii():
      return false
  true

proc isUpperAscii*(s: string): bool {.noSideEffect, procvar,
  rtl, extern: "nsuIsUpperAsciiStr".}=
  ## Checks whether or not `s` contains all upper case characters.
  ##
  ## This checks ASCII characters only.
  ## Returns true if all characters in `s` are upper case
  ## and there is at least one character in `s`.
  if s.len() == 0:
    return false

  for c in s:
    if not c.isUpperAscii():
      return false
  true

proc toLowerAscii*(c: char): char {.noSideEffect, procvar,
  rtl, extern: "nsuToLowerAsciiChar".} =
  ## Converts `c` into lower case.
  ##
  ## This works only for the letters ``A-Z``. See `unicode.toLower
  ## <unicode.html#toLower>`_ for a version that works for any Unicode
  ## character.
  if c in {'A'..'Z'}:
    result = chr(ord(c) + (ord('a') - ord('A')))
  else:
    result = c

proc toLowerAscii*(s: string): string {.noSideEffect, procvar,
  rtl, extern: "nsuToLowerAsciiStr".} =
  ## Converts `s` into lower case.
  ##
  ## This works only for the letters ``A-Z``. See `unicode.toLower
  ## <unicode.html#toLower>`_ for a version that works for any Unicode
  ## character.
  result = newString(len(s))
  for i in 0..len(s) - 1:
    result[i] = toLowerAscii(s[i])

proc toUpperAscii*(c: char): char {.noSideEffect, procvar,
  rtl, extern: "nsuToUpperAsciiChar".} =
  ## Converts `c` into upper case.
  ##
  ## This works only for the letters ``A-Z``.  See `unicode.toUpper
  ## <unicode.html#toUpper>`_ for a version that works for any Unicode
  ## character.
  if c in {'a'..'z'}:
    result = chr(ord(c) - (ord('a') - ord('A')))
  else:
    result = c

proc toUpperAscii*(s: string): string {.noSideEffect, procvar,
  rtl, extern: "nsuToUpperAsciiStr".} =
  ## Converts `s` into upper case.
  ##
  ## This works only for the letters ``A-Z``.  See `unicode.toUpper
  ## <unicode.html#toUpper>`_ for a version that works for any Unicode
  ## character.
  result = newString(len(s))
  for i in 0..len(s) - 1:
    result[i] = toUpperAscii(s[i])

proc capitalizeAscii*(s: string): string {.noSideEffect, procvar,
  rtl, extern: "nsuCapitalizeAscii".} =
  ## Converts the first character of `s` into upper case.
  ##
  ## This works only for the letters ``A-Z``.
  result = toUpperAscii(s[0]) & substr(s, 1)

proc isSpace*(c: char): bool {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuIsSpaceChar".}=
  ## Checks whether or not `c` is a whitespace character.
  ##
  ## **Deprecated since version 0.15.0**: use ``isSpaceAscii`` instead.
  isSpaceAscii(c)

proc isLower*(c: char): bool {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuIsLowerChar".}=
  ## Checks whether or not `c` is a lower case character.
  ##
  ## This checks ASCII characters only.
  ##
  ## **Deprecated since version 0.15.0**: use ``isLowerAscii`` instead.
  isLowerAscii(c)

proc isUpper*(c: char): bool {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuIsUpperChar".}=
  ## Checks whether or not `c` is an upper case character.
  ##
  ## This checks ASCII characters only.
  ##
  ## **Deprecated since version 0.15.0**: use ``isUpperAscii`` instead.
  isUpperAscii(c)

proc isAlpha*(c: char): bool {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuIsAlphaChar".}=
  ## Checks whether or not `c` is alphabetical.
  ##
  ## This checks a-z, A-Z ASCII characters only.
  ##
  ## **Deprecated since version 0.15.0**: use ``isAlphaAscii`` instead.
  isAlphaAscii(c)

proc isAlpha*(s: string): bool {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuIsAlphaStr".}=
  ## Checks whether or not `s` is alphabetical.
  ##
  ## This checks a-z, A-Z ASCII characters only.
  ## Returns true if all characters in `s` are
  ## alphabetic and there is at least one character
  ## in `s`.
  ##
  ## **Deprecated since version 0.15.0**: use ``isAlphaAscii`` instead.
  isAlphaAscii(s)

proc isSpace*(s: string): bool {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuIsSpaceStr".}=
  ## Checks whether or not `s` is completely whitespace.
  ##
  ## Returns true if all characters in `s` are whitespace
  ## characters and there is at least one character in `s`.
  ##
  ## **Deprecated since version 0.15.0**: use ``isSpaceAscii`` instead.
  isSpaceAscii(s)

proc isLower*(s: string): bool {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuIsLowerStr".}=
  ## Checks whether or not `s` contains all lower case characters.
  ##
  ## This checks ASCII characters only.
  ## Returns true if all characters in `s` are lower case
  ## and there is at least one character  in `s`.
  ##
  ## **Deprecated since version 0.15.0**: use ``isLowerAscii`` instead.
  isLowerAscii(s)

proc isUpper*(s: string): bool {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuIsUpperStr".}=
  ## Checks whether or not `s` contains all upper case characters.
  ##
  ## This checks ASCII characters only.
  ## Returns true if all characters in `s` are upper case
  ## and there is at least one character in `s`.
  ##
  ## **Deprecated since version 0.15.0**: use ``isUpperAscii`` instead.
  isUpperAscii(s)

proc toLower*(c: char): char {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuToLowerChar".} =
  ## Converts `c` into lower case.
  ##
  ## This works only for the letters ``A-Z``. See `unicode.toLower
  ## <unicode.html#toLower>`_ for a version that works for any Unicode
  ## character.
  ##
  ## **Deprecated since version 0.15.0**: use ``toLowerAscii`` instead.
  toLowerAscii(c)

proc toLower*(s: string): string {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuToLowerStr".} =
  ## Converts `s` into lower case.
  ##
  ## This works only for the letters ``A-Z``. See `unicode.toLower
  ## <unicode.html#toLower>`_ for a version that works for any Unicode
  ## character.
  ##
  ## **Deprecated since version 0.15.0**: use ``toLowerAscii`` instead.
  toLowerAscii(s)

proc toUpper*(c: char): char {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuToUpperChar".} =
  ## Converts `c` into upper case.
  ##
  ## This works only for the letters ``A-Z``.  See `unicode.toUpper
  ## <unicode.html#toUpper>`_ for a version that works for any Unicode
  ## character.
  ##
  ## **Deprecated since version 0.15.0**: use ``toUpperAscii`` instead.
  toUpperAscii(c)

proc toUpper*(s: string): string {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuToUpperStr".} =
  ## Converts `s` into upper case.
  ##
  ## This works only for the letters ``A-Z``.  See `unicode.toUpper
  ## <unicode.html#toUpper>`_ for a version that works for any Unicode
  ## character.
  ##
  ## **Deprecated since version 0.15.0**: use ``toUpperAscii`` instead.
  toUpperAscii(s)

proc capitalize*(s: string): string {.noSideEffect, procvar,
  rtl, deprecated, extern: "nsuCapitalize".} =
  ## Converts the first character of `s` into upper case.
  ##
  ## This works only for the letters ``A-Z``.
  ##
  ## **Deprecated since version 0.15.0**: use ``capitalizeAscii`` instead.
  capitalizeAscii(s)

proc normalize*(s: string): string {.noSideEffect, procvar,
  rtl, extern: "nsuNormalize".} =
  ## Normalizes the string `s`.
  ##
  ## That means to convert it to lower case and remove any '_'. This is needed
  ## for Nim identifiers for example.
  result = newString(s.len)
  var j = 0
  for i in 0..len(s) - 1:
    if s[i] in {'A'..'Z'}:
      result[j] = chr(ord(s[i]) + (ord('a') - ord('A')))
      inc j
    elif s[i] != '_':
      result[j] = s[i]
      inc j
  if j != s.len: setLen(result, j)

proc cmpIgnoreCase*(a, b: string): int {.noSideEffect,
  rtl, extern: "nsuCmpIgnoreCase", procvar.} =
  ## Compares two strings in a case insensitive manner. Returns:
  ##
  ## | 0 iff a == b
  ## | < 0 iff a < b
  ## | > 0 iff a > b
  var i = 0
  var m = min(a.len, b.len)
  while i < m:
    result = ord(toLowerAscii(a[i])) - ord(toLowerAscii(b[i]))
    if result != 0: return
    inc(i)
  result = a.len - b.len

{.push checks: off, line_trace: off .} # this is a hot-spot in the compiler!
                                       # thus we compile without checks here

proc cmpIgnoreStyle*(a, b: string): int {.noSideEffect,
  rtl, extern: "nsuCmpIgnoreStyle", procvar.} =
  ## Compares two strings normalized (i.e. case and
  ## underscores do not matter). Returns:
  ##
  ## | 0 iff a == b
  ## | < 0 iff a < b
  ## | > 0 iff a > b
  var i = 0
  var j = 0
  while true:
    while a[i] == '_': inc(i)
    while b[j] == '_': inc(j) # BUGFIX: typo
    var aa = toLowerAscii(a[i])
    var bb = toLowerAscii(b[j])
    result = ord(aa) - ord(bb)
    if result != 0 or aa == '\0': break
    inc(i)
    inc(j)


proc strip*(s: string, leading = true, trailing = true,
            chars: set[char] = Whitespace): string
  {.noSideEffect, rtl, extern: "nsuStrip".} =
  ## Strips `chars` from `s` and returns the resulting string.
  ##
  ## If `leading` is true, leading `chars` are stripped.
  ## If `trailing` is true, trailing `chars` are stripped.
  var
    first = 0
    last = len(s)-1
  if leading:
    while s[first] in chars: inc(first)
  if trailing:
    while last >= 0 and s[last] in chars: dec(last)
  result = substr(s, first, last)

proc toOctal*(c: char): string {.noSideEffect, rtl, extern: "nsuToOctal".} =
  ## Converts a character `c` to its octal representation.
  ##
  ## The resulting string may not have a leading zero. Its length is always
  ## exactly 3.
  result = newString(3)
  var val = ord(c)
  for i in countdown(2, 0):
    result[i] = chr(val mod 8 + ord('0'))
    val = val div 8

proc isNilOrEmpty*(s: string): bool {.noSideEffect, procvar, rtl, extern: "nsuIsNilOrEmpty".} =
  ## Checks if `s` is nil or empty.
  result = len(s) == 0

proc isNilOrWhitespace*(s: string): bool {.noSideEffect, procvar, rtl, extern: "nsuIsNilOrWhitespace".} =
  ## Checks if `s` is nil or consists entirely of whitespace characters.
  if len(s) == 0:
    return true

  result = true
  for c in s:
    if not c.isSpaceAscii():
      return false

proc substrEq(s: string, pos: int, substr: string): bool =
  var i = 0
  var length = substr.len
  while i < length and s[pos+i] == substr[i]:
    inc i

  return i == length

# --------- Private templates for different split separators -----------

template stringHasSep(s: string, index: int, seps: set[char]): bool =
  s[index] in seps

template stringHasSep(s: string, index: int, sep: char): bool =
  s[index] == sep

template stringHasSep(s: string, index: int, sep: string): bool =
  s.substrEq(index, sep)

template splitCommon(s, sep, maxsplit, sepLen) =
  ## Common code for split procedures
  var last = 0
  var splits = maxsplit

  if len(s) > 0:
    while last <= len(s):
      var first = last
      while last < len(s) and not stringHasSep(s, last, sep):
        inc(last)
      if splits == 0: last = len(s)
      yield substr(s, first, last-1)
      if splits == 0: break
      dec(splits)
      inc(last, sepLen)

template oldSplit(s, seps, maxsplit) =
  var last = 0
  var splits = maxsplit
  assert(not ('\0' in seps))
  while last < len(s):
    while s[last] in seps: inc(last)
    var first = last
    while last < len(s) and s[last] notin seps: inc(last)
    if first <= last-1:
      if splits == 0: last = len(s)
      yield substr(s, first, last-1)
      if splits == 0: break
      dec(splits)

iterator split*(s: string, seps: set[char] = Whitespace,
                maxsplit: int = -1): string =
  ## Splits the string `s` into substrings using a group of separators.
  ##
  ## Substrings are separated by a substring containing only `seps`.
  ##
  ## .. code-block:: nim
  ##   for word in split("this\lis an\texample"):
  ##     writeLine(stdout, word)
  ##
  ## ...generates this output:
  ##
  ## .. code-block::
  ##   "this"
  ##   "is"
  ##   "an"
  ##   "example"
  ##
  ## And the following code:
  ##
  ## .. code-block:: nim
  ##   for word in split("this:is;an$example", {';', ':', '$'}):
  ##     writeLine(stdout, word)
  ##
  ## ...produces the same output as the first example. The code:
  ##
  ## .. code-block:: nim
  ##   let date = "2012-11-20T22:08:08.398990"
  ##   let separators = {' ', '-', ':', 'T'}
  ##   for number in split(date, separators):
  ##     writeLine(stdout, number)
  ##
  ## ...results in:
  ##
  ## .. code-block::
  ##   "2012"
  ##   "11"
  ##   "20"
  ##   "22"
  ##   "08"
  ##   "08.398990"
  ##
  when defined(nimOldSplit):
    oldSplit(s, seps, maxsplit)
  else:
    splitCommon(s, seps, maxsplit, 1)

iterator splitWhitespace*(s: string): string =
  ## Splits at whitespace.
  oldSplit(s, Whitespace, -1)

proc splitWhitespace*(s: string): seq[string] {.noSideEffect,
  rtl, extern: "nsuSplitWhitespace".} =
  ## The same as the `splitWhitespace <#splitWhitespace.i,string>`_
  ## iterator, but is a proc that returns a sequence of substrings.
  accumulateResult(splitWhitespace(s))

iterator split*(s: string, sep: char, maxsplit: int = -1): string =
  ## Splits the string `s` into substrings using a single separator.
  ##
  ## Substrings are separated by the character `sep`.
  ## The code:
  ##
  ## .. code-block:: nim
  ##   for word in split(";;this;is;an;;example;;;", ';'):
  ##     writeLine(stdout, word)
  ##
  ## Results in:
  ##
  ## .. code-block::
  ##   ""
  ##   ""
  ##   "this"
  ##   "is"
  ##   "an"
  ##   ""
  ##   "example"
  ##   ""
  ##   ""
  ##   ""
  ##
  splitCommon(s, sep, maxsplit, 1)

iterator split*(s: string, sep: string, maxsplit: int = -1): string =
  ## Splits the string `s` into substrings using a string separator.
  ##
  ## Substrings are separated by the string `sep`.
  ## The code:
  ##
  ## .. code-block:: nim
  ##   for word in split("thisDATAisDATAcorrupted", "DATA"):
  ##     writeLine(stdout, word)
  ##
  ## Results in:
  ##
  ## .. code-block::
  ##   "this"
  ##   "is"
  ##   "corrupted"
  ##

  splitCommon(s, sep, maxsplit, sep.len)

template rsplitCommon(s, sep, maxsplit, sepLen) =
  ## Common code for rsplit functions
  var
    last = s.len - 1
    first = last
    splits = maxsplit
    startPos = 0

  if len(s) > 0:
    # go to -1 in order to get separators at the beginning
    while first >= -1:
      while first >= 0 and not stringHasSep(s, first, sep):
        dec(first)

      if splits == 0:
        # No more splits means set first to the beginning
        first = -1

      if first == -1:
        startPos = 0
      else:
        startPos = first + sepLen

      yield substr(s, startPos, last)

      if splits == 0:
        break

      dec(splits)
      dec(first)

      last = first

iterator rsplit*(s: string, seps: set[char] = Whitespace,
                 maxsplit: int = -1): string =
  ## Splits the string `s` into substrings from the right using a
  ## string separator. Works exactly the same as `split iterator
  ## <#split.i,string,char>`_ except in reverse order.
  ##
  ## .. code-block:: nim
  ##   for piece in "foo bar".rsplit(WhiteSpace):
  ##     echo piece
  ##
  ## Results in:
  ##
  ## .. code-block:: nim
  ##   "bar"
  ##   "foo"
  ##
  ## Substrings are separated from the right by the set of chars `seps`

  rsplitCommon(s, seps, maxsplit, 1)

iterator rsplit*(s: string, sep: char,
                 maxsplit: int = -1): string =
  ## Splits the string `s` into substrings from the right using a
  ## string separator. Works exactly the same as `split iterator
  ## <#split.i,string,char>`_ except in reverse order.
  ##
  ## .. code-block:: nim
  ##   for piece in "foo:bar".rsplit(':'):
  ##     echo piece
  ##
  ## Results in:
  ##
  ## .. code-block:: nim
  ##   "bar"
  ##   "foo"
  ##
  ## Substrings are separated from the right by the char `sep`
  rsplitCommon(s, sep, maxsplit, 1)

iterator rsplit*(s: string, sep: string, maxsplit: int = -1,
                 keepSeparators: bool = false): string =
  ## Splits the string `s` into substrings from the right using a
  ## string separator. Works exactly the same as `split iterator
  ## <#split.i,string,string>`_ except in reverse order.
  ##
  ## .. code-block:: nim
  ##   for piece in "foothebar".rsplit("the"):
  ##     echo piece
  ##
  ## Results in:
  ##
  ## .. code-block:: nim
  ##   "bar"
  ##   "foo"
  ##
  ## Substrings are separated from the right by the string `sep`
  rsplitCommon(s, sep, maxsplit, sep.len)

iterator splitLines*(s: string): string =
  ## Splits the string `s` into its containing lines.
  ##
  ## Every `character literal <manual.html#character-literals>`_ newline
  ## combination (CR, LF, CR-LF) is supported. The result strings contain no
  ## trailing ``\n``.
  ##
  ## Example:
  ##
  ## .. code-block:: nim
  ##   for line in splitLines("\nthis\nis\nan\n\nexample\n"):
  ##     writeLine(stdout, line)
  ##
  ## Results in:
  ##
  ## .. code-block:: nim
  ##   ""
  ##   "this"
  ##   "is"
  ##   "an"
  ##   ""
  ##   "example"
  ##   ""
  var first = 0
  var last = 0
  while true:
    while s[last] notin {'\0', '\c', '\l'}: inc(last)
    yield substr(s, first, last-1)
    # skip newlines:
    if s[last] == '\l': inc(last)
    elif s[last] == '\c':
      inc(last)
      if s[last] == '\l': inc(last)
    else: break # was '\0'
    first = last

proc splitLines*(s: string): seq[string] {.noSideEffect,
  rtl, extern: "nsuSplitLines".} =
  ## The same as the `splitLines <#splitLines.i,string>`_ iterator, but is a
  ## proc that returns a sequence of substrings.
  accumulateResult(splitLines(s))

proc countLines*(s: string): int {.noSideEffect,
  rtl, extern: "nsuCountLines".} =
  ## Returns the number of new line separators in the string `s`.
  ##
  ## This is the same as ``len(splitLines(s))``, but much more efficient
  ## because it doesn't modify the string creating temporal objects. Every
  ## `character literal <manual.html#character-literals>`_ newline combination
  ## (CR, LF, CR-LF) is supported.
  ##
  ## Despite its name this proc might not actually return the *number of lines*
  ## in `s` because the concept of what a line is can vary. For example, a
  ## string like ``Hello world`` is a line of text, but the proc will return a
  ## value of zero because there are no newline separators.  Also, text editors
  ## usually don't count trailing newline characters in a text file as a new
  ## empty line, but this proc will.
  var i = 0
  while i < s.len:
    case s[i]
    of '\c':
      if s[i+1] == '\l': inc i
      inc result
    of '\l': inc result
    else: discard
    inc i

proc split*(s: string, seps: set[char] = Whitespace, maxsplit: int = -1): seq[string] {.
  noSideEffect, rtl, extern: "nsuSplitCharSet".} =
  ## The same as the `split iterator <#split.i,string,set[char]>`_, but is a
  ## proc that returns a sequence of substrings.
  accumulateResult(split(s, seps, maxsplit))

proc split*(s: string, sep: char, maxsplit: int = -1): seq[string] {.noSideEffect,
  rtl, extern: "nsuSplitChar".} =
  ## The same as the `split iterator <#split.i,string,char>`_, but is a proc
  ## that returns a sequence of substrings.
  accumulateResult(split(s, sep, maxsplit))

proc split*(s: string, sep: string, maxsplit: int = -1): seq[string] {.noSideEffect,
  rtl, extern: "nsuSplitString".} =
  ## Splits the string `s` into substrings using a string separator.
  ##
  ## Substrings are separated by the string `sep`. This is a wrapper around the
  ## `split iterator <#split.i,string,string>`_.
  doAssert(sep.len > 0)

  accumulateResult(split(s, sep, maxsplit))

proc rsplit*(s: string, seps: set[char] = Whitespace,
             maxsplit: int = -1): seq[string]
             {.noSideEffect, rtl, extern: "nsuRSplitCharSet".} =
  ## The same as the `rsplit iterator <#rsplit.i,string,set[char]>`_, but is a
  ## proc that returns a sequence of substrings.
  ##
  ## A possible common use case for `rsplit` is path manipulation,
  ## particularly on systems that don't use a common delimiter.
  ##
  ## For example, if a system had `#` as a delimiter, you could
  ## do the following to get the tail of the path:
  ##
  ## .. code-block:: nim
  ##   var tailSplit = rsplit("Root#Object#Method#Index", {'#'}, maxsplit=1)
  ##
  ## Results in `tailSplit` containing:
  ##
  ## .. code-block:: nim
  ##   @["Root#Object#Method", "Index"]
  ##
  accumulateResult(rsplit(s, seps, maxsplit))
  result.reverse()

proc rsplit*(s: string, sep: char, maxsplit: int = -1): seq[string]
             {.noSideEffect, rtl, extern: "nsuRSplitChar".} =
  ## The same as the `split iterator <#rsplit.i,string,char>`_, but is a proc
  ## that returns a sequence of substrings.
  ##
  ## A possible common use case for `rsplit` is path manipulation,
  ## particularly on systems that don't use a common delimiter.
  ##
  ## For example, if a system had `#` as a delimiter, you could
  ## do the following to get the tail of the path:
  ##
  ## .. code-block:: nim
  ##   var tailSplit = rsplit("Root#Object#Method#Index", '#', maxsplit=1)
  ##
  ## Results in `tailSplit` containing:
  ##
  ## .. code-block:: nim
  ##   @["Root#Object#Method", "Index"]
  ##
  accumulateResult(rsplit(s, sep, maxsplit))
  result.reverse()

proc rsplit*(s: string, sep: string, maxsplit: int = -1): seq[string]
             {.noSideEffect, rtl, extern: "nsuRSplitString".} =
  ## The same as the `split iterator <#rsplit.i,string,string>`_, but is a proc
  ## that returns a sequence of substrings.
  ##
  ## A possible common use case for `rsplit` is path manipulation,
  ## particularly on systems that don't use a common delimiter.
  ##
  ## For example, if a system had `#` as a delimiter, you could
  ## do the following to get the tail of the path:
  ##
  ## .. code-block:: nim
  ##   var tailSplit = rsplit("Root#Object#Method#Index", "#", maxsplit=1)
  ##
  ## Results in `tailSplit` containing:
  ##
  ## .. code-block:: nim
  ##   @["Root#Object#Method", "Index"]
  ##
  accumulateResult(rsplit(s, sep, maxsplit))
  result.reverse()

proc toHex*(x: BiggestInt, len: Positive): string {.noSideEffect,
  rtl, extern: "nsuToHex".} =
  ## Converts `x` to its hexadecimal representation.
  ##
  ## The resulting string will be exactly `len` characters long. No prefix like
  ## ``0x`` is generated. `x` is treated as an unsigned value.
  const
    HexChars = "0123456789ABCDEF"
  var
    n = x
  result = newString(len)
  for j in countdown(len-1, 0):
    result[j] = HexChars[n and 0xF]
    n = n shr 4
    # handle negative overflow
    if n == 0 and x < 0: n = -1

proc toHex*[T](x: T): string =
  ## Shortcut for ``toHex(x, T.sizeOf * 2)``
  toHex(x, T.sizeOf * 2)

proc intToStr*(x: int, minchars: Positive = 1): string {.noSideEffect,
  rtl, extern: "nsuIntToStr".} =
  ## Converts `x` to its decimal representation.
  ##
  ## The resulting string will be minimally `minchars` characters long. This is
  ## achieved by adding leading zeros.
  result = $abs(x)
  for i in 1 .. minchars - len(result):
    result = '0' & result
  if x < 0:
    result = '-' & result

proc parseInt*(s: string): int {.noSideEffect, procvar,
  rtl, extern: "nsuParseInt".} =
  ## Parses a decimal integer value contained in `s`.
  ##
  ## If `s` is not a valid integer, `ValueError` is raised.
  var L = parseutils.parseInt(s, result, 0)
  if L != s.len or L == 0:
    raise newException(ValueError, "invalid integer: " & s)

proc parseBiggestInt*(s: string): BiggestInt {.noSideEffect, procvar,
  rtl, extern: "nsuParseBiggestInt".} =
  ## Parses a decimal integer value contained in `s`.
  ##
  ## If `s` is not a valid integer, `ValueError` is raised.
  var L = parseutils.parseBiggestInt(s, result, 0)
  if L != s.len or L == 0:
    raise newException(ValueError, "invalid integer: " & s)

proc parseUInt*(s: string): uint {.noSideEffect, procvar,
  rtl, extern: "nsuParseUInt".} =
  ## Parses a decimal unsigned integer value contained in `s`.
  ##
  ## If `s` is not a valid integer, `ValueError` is raised.
  var L = parseutils.parseUInt(s, result, 0)
  if L != s.len or L == 0:
    raise newException(ValueError, "invalid unsigned integer: " & s)

proc parseBiggestUInt*(s: string): uint64 {.noSideEffect, procvar,
  rtl, extern: "nsuParseBiggestUInt".} =
  ## Parses a decimal unsigned integer value contained in `s`.
  ##
  ## If `s` is not a valid integer, `ValueError` is raised.
  var L = parseutils.parseBiggestUInt(s, result, 0)
  if L != s.len or L == 0:
    raise newException(ValueError, "invalid unsigned integer: " & s)

proc parseFloat*(s: string): float {.noSideEffect, procvar,
  rtl, extern: "nsuParseFloat".} =
  ## Parses a decimal floating point value contained in `s`. If `s` is not
  ## a valid floating point number, `ValueError` is raised. ``NAN``,
  ## ``INF``, ``-INF`` are also supported (case insensitive comparison).
  var L = parseutils.parseFloat(s, result, 0)
  if L != s.len or L == 0:
    raise newException(ValueError, "invalid float: " & s)

proc parseHexInt*(s: string): int {.noSideEffect, procvar,
  rtl, extern: "nsuParseHexInt".} =
  ## Parses a hexadecimal integer value contained in `s`.
  ##
  ## If `s` is not a valid integer, `ValueError` is raised. `s` can have one
  ## of the following optional prefixes: ``0x``, ``0X``, ``#``.  Underscores
  ## within `s` are ignored.
  var i = 0
  if s[i] == '0' and (s[i+1] == 'x' or s[i+1] == 'X'): inc(i, 2)
  elif s[i] == '#': inc(i)
  while true:
    case s[i]
    of '_': inc(i)
    of '0'..'9':
      result = result shl 4 or (ord(s[i]) - ord('0'))
      inc(i)
    of 'a'..'f':
      result = result shl 4 or (ord(s[i]) - ord('a') + 10)
      inc(i)
    of 'A'..'F':
      result = result shl 4 or (ord(s[i]) - ord('A') + 10)
      inc(i)
    of '\0': break
    else: raise newException(ValueError, "invalid integer: " & s)

proc parseBool*(s: string): bool =
  ## Parses a value into a `bool`.
  ##
  ## If ``s`` is one of the following values: ``y, yes, true, 1, on``, then
  ## returns `true`. If ``s`` is one of the following values: ``n, no, false,
  ## 0, off``, then returns `false`.  If ``s`` is something else a
  ## ``ValueError`` exception is raised.
  case normalize(s)
  of "y", "yes", "true", "1", "on": result = true
  of "n", "no", "false", "0", "off": result = false
  else: raise newException(ValueError, "cannot interpret as a bool: " & s)

proc parseEnum*[T: enum](s: string): T =
  ## Parses an enum ``T``.
  ##
  ## Raises ``ValueError`` for an invalid value in `s`. The comparison is
  ## done in a style insensitive way.
  for e in low(T)..high(T):
    if cmpIgnoreStyle(s, $e) == 0:
      return e
  raise newException(ValueError, "invalid enum value: " & s)

proc parseEnum*[T: enum](s: string, default: T): T =
  ## Parses an enum ``T``.
  ##
  ## Uses `default` for an invalid value in `s`. The comparison is done in a
  ## style insensitive way.
  for e in low(T)..high(T):
    if cmpIgnoreStyle(s, $e) == 0:
      return e
  result = default

proc repeat*(c: char, count: Natural): string {.noSideEffect,
  rtl, extern: "nsuRepeatChar".} =
  ## Returns a string of length `count` consisting only of
  ## the character `c`. You can use this proc to left align strings. Example:
  ##
  ## .. code-block:: nim
  ##   proc tabexpand(indent: int, text: string, tabsize: int = 4) =
  ##     echo '\t'.repeat(indent div tabsize), ' '.repeat(indent mod tabsize),
  ##         text
  ##
  ##   tabexpand(4, "At four")
  ##   tabexpand(5, "At five")
  ##   tabexpand(6, "At six")
  result = newString(count)
  for i in 0..count-1: result[i] = c

proc repeat*(s: string, n: Natural): string {.noSideEffect,
  rtl, extern: "nsuRepeatStr".} =
  ## Returns String `s` concatenated `n` times.  Example:
  ##
  ## .. code-block:: nim
  ##   echo "+++ STOP ".repeat(4), "+++"
  result = newStringOfCap(n * s.len)
  for i in 1..n: result.add(s)

template spaces*(n: Natural): string = repeat(' ', n)
  ## Returns a String with `n` space characters. You can use this proc
  ## to left align strings. Example:
  ##
  ## .. code-block:: nim
  ##   let
  ##     width = 15
  ##     text1 = "Hello user!"
  ##     text2 = "This is a very long string"
  ##   echo text1 & spaces(max(0, width - text1.len)) & "|"
  ##   echo text2 & spaces(max(0, width - text2.len)) & "|"

proc repeatChar*(count: Natural, c: char = ' '): string {.deprecated.} =
  ## deprecated: use repeat() or spaces()
  repeat(c, count)

proc repeatStr*(count: Natural, s: string): string {.deprecated.} =
  ## deprecated: use repeat(string, count) or string.repeat(count)
  repeat(s, count)

proc align*(s: string, count: Natural, padding = ' '): string {.
  noSideEffect, rtl, extern: "nsuAlignString".} =
  ## Aligns a string `s` with `padding`, so that it is of length `count`.
  ##
  ## `padding` characters (by default spaces) are added before `s` resulting in
  ## right alignment. If ``s.len >= count``, no spaces are added and `s` is
  ## returned unchanged. If you need to left align a string use the `repeatChar
  ## proc <#repeatChar>`_. Example:
  ##
  ## .. code-block:: nim
  ##   assert align("abc", 4) == " abc"
  ##   assert align("a", 0) == "a"
  ##   assert align("1232", 6) == "  1232"
  ##   assert align("1232", 6, '#') == "##1232"
  if s.len < count:
    result = newString(count)
    let spaces = count - s.len
    for i in 0..spaces-1: result[i] = padding
    for i in spaces..count-1: result[i] = s[i-spaces]
  else:
    result = s

iterator tokenize*(s: string, seps: set[char] = Whitespace): tuple[
  token: string, isSep: bool] =
  ## Tokenizes the string `s` into substrings.
  ##
  ## Substrings are separated by a substring containing only `seps`.
  ## Examples:
  ##
  ## .. code-block:: nim
  ##   for word in tokenize("  this is an  example  "):
  ##     writeLine(stdout, word)
  ##
  ## Results in:
  ##
  ## .. code-block:: nim
  ##   ("  ", true)
  ##   ("this", false)
  ##   (" ", true)
  ##   ("is", false)
  ##   (" ", true)
  ##   ("an", false)
  ##   ("  ", true)
  ##   ("example", false)
  ##   ("  ", true)
  var i = 0
  while true:
    var j = i
    var isSep = s[j] in seps
    while j < s.len and (s[j] in seps) == isSep: inc(j)
    if j > i:
      yield (substr(s, i, j-1), isSep)
    else:
      break
    i = j

proc wordWrap*(s: string, maxLineWidth = 80,
               splitLongWords = true,
               seps: set[char] = Whitespace,
               newLine = "\n"): string {.
               noSideEffect, rtl, extern: "nsuWordWrap".} =
  ## Word wraps `s`.
  result = newStringOfCap(s.len + s.len shr 6)
  var spaceLeft = maxLineWidth
  var lastSep = ""
  for word, isSep in tokenize(s, seps):
    if isSep:
      lastSep = word
      spaceLeft = spaceLeft - len(word)
      continue
    if len(word) > spaceLeft:
      if splitLongWords and len(word) > maxLineWidth:
        result.add(substr(word, 0, spaceLeft-1))
        var w = spaceLeft+1
        var wordLeft = len(word) - spaceLeft
        while wordLeft > 0:
          result.add(newLine)
          var L = min(maxLineWidth, wordLeft)
          spaceLeft = maxLineWidth - L
          result.add(substr(word, w, w+L-1))
          inc(w, L)
          dec(wordLeft, L)
      else:
        spaceLeft = maxLineWidth - len(word)
        result.add(newLine)
        result.add(word)
    else:
      spaceLeft = spaceLeft - len(word)
      result.add(lastSep & word)
      lastSep.setLen(0)

proc indent*(s: string, count: Natural, padding: string = " "): string
    {.noSideEffect, rtl, extern: "nsuIndent".} =
  ## Indents each line in ``s`` by ``count`` amount of ``padding``.
  ##
  ## **Note:** This does not preserve the new line characters used in ``s``.
  result = ""
  var i = 0
  for line in s.splitLines():
    if i != 0:
      result.add("\n")
    for j in 1..count:
      result.add(padding)
    result.add(line)
    i.inc

proc unindent*(s: string, count: Natural, padding: string = " "): string
    {.noSideEffect, rtl, extern: "nsuUnindent".} =
  ## Unindents each line in ``s`` by ``count`` amount of ``padding``.
  ##
  ## **Note:** This does not preserve the new line characters used in ``s``.
  result = ""
  var i = 0
  for line in s.splitLines():
    if i != 0:
      result.add("\n")
    var indentCount = 0
    for j in 0..<count.int:
      indentCount.inc
      if line[j .. j + <padding.len] != padding:
        indentCount = j
        break
    result.add(line[indentCount*padding.len .. ^1])
    i.inc

proc unindent*(s: string): string
    {.noSideEffect, rtl, extern: "nsuUnindentAll".} =
  ## Removes all indentation composed of whitespace from each line in ``s``.
  ##
  ## For example:
  ##
  ## .. code-block:: nim
  ##   const x = """
  ##     Hello
  ##     There
  ##   """.unindent()
  ##
  ##   doAssert x == "Hello\nThere\n"
  unindent(s, 1000) # TODO: Passing a 1000 is a bit hackish.

proc startsWith*(s, prefix: string): bool {.noSideEffect,
  rtl, extern: "nsuStartsWith".} =
  ## Returns true iff ``s`` starts with ``prefix``.
  ##
  ## If ``prefix == ""`` true is returned.
  var i = 0
  while true:
    if prefix[i] == '\0': return true
    if s[i] != prefix[i]: return false
    inc(i)

proc startsWith*(s: string, prefix: char): bool {.noSideEffect, inline.} =
  ## Returns true iff ``s`` starts with ``prefix``.
  result = s[0] == prefix

proc endsWith*(s, suffix: string): bool {.noSideEffect,
  rtl, extern: "nsuEndsWith".} =
  ## Returns true iff ``s`` ends with ``suffix``.
  ##
  ## If ``suffix == ""`` true is returned.
  var i = 0
  var j = len(s) - len(suffix)
  while i+j <% s.len:
    if s[i+j] != suffix[i]: return false
    inc(i)
  if suffix[i] == '\0': return true

proc endsWith*(s: string, suffix: char): bool {.noSideEffect, inline.} =
  ## Returns true iff ``s`` ends with ``suffix``.
  result = s[s.high] == suffix

proc continuesWith*(s, substr: string, start: Natural): bool {.noSideEffect,
  rtl, extern: "nsuContinuesWith".} =
  ## Returns true iff ``s`` continues with ``substr`` at position ``start``.
  ##
  ## If ``substr == ""`` true is returned.
  var i = 0
  while true:
    if substr[i] == '\0': return true
    if s[i+start] != substr[i]: return false
    inc(i)

proc addSep*(dest: var string, sep = ", ", startLen: Natural = 0)
  {.noSideEffect, inline.} =
  ## Adds a separator to `dest` only if its length is bigger than `startLen`.
  ##
  ## A shorthand for:
  ##
  ## .. code-block:: nim
  ##   if dest.len > startLen: add(dest, sep)
  ##
  ## This is often useful for generating some code where the items need to
  ## be *separated* by `sep`. `sep` is only added if `dest` is longer than
  ## `startLen`. The following example creates a string describing
  ## an array of integers:
  ##
  ## .. code-block:: nim
  ##   var arr = "["
  ##   for x in items([2, 3, 5, 7, 11]):
  ##     addSep(arr, startLen=len("["))
  ##     add(arr, $x)
  ##   add(arr, "]")
  if dest.len > startLen: add(dest, sep)

proc allCharsInSet*(s: string, theSet: set[char]): bool =
  ## Returns true iff each character of `s` is in the set `theSet`.
  for c in items(s):
    if c notin theSet: return false
  return true

proc abbrev*(s: string, possibilities: openArray[string]): int =
  ## Returns the index of the first item in `possibilities` if not ambiguous.
  ##
  ## Returns -1 if no item has been found and -2 if multiple items match.
  result = -1 # none found
  for i in 0..possibilities.len-1:
    if possibilities[i].startsWith(s):
      if possibilities[i] == s:
        # special case: exact match shouldn't be ambiguous
        return i
      if result >= 0: return -2 # ambiguous
      result = i

# ---------------------------------------------------------------------------

proc join*(a: openArray[string], sep: string = ""): string {.
  noSideEffect, rtl, extern: "nsuJoinSep".} =
  ## Concatenates all strings in `a` separating them with `sep`.
  if len(a) > 0:
    var L = sep.len * (a.len-1)
    for i in 0..high(a): inc(L, a[i].len)
    result = newStringOfCap(L)
    add(result, a[0])
    for i in 1..high(a):
      add(result, sep)
      add(result, a[i])
  else:
    result = ""

proc join*[T: not string](a: openArray[T], sep: string = ""): string {.
  noSideEffect, rtl.} =
  ## Converts all elements in `a` to strings using `$` and concatenates them
  ## with `sep`.
  result = ""
  for i, x in a:
    if i > 0:
      add(result, sep)
    add(result, $x)

type
  SkipTable = array[char, int]

{.push profiler: off.}
proc preprocessSub(sub: string, a: var SkipTable) =
  var m = len(sub)
  for i in 0..0xff: a[chr(i)] = m+1
  for i in 0..m-1: a[sub[i]] = m-i
{.pop.}

proc findAux(s, sub: string, start, last: int, a: SkipTable): int =
  # Fast "quick search" algorithm:
  var
    m = len(sub)
    n = last + 1
  # search:
  var j = start
  while j <= n - m:
    block match:
      for k in 0..m-1:
        if sub[k] != s[k+j]: break match
      return j
    inc(j, a[s[j+m]])
  return -1

when not (defined(js) or defined(nimdoc) or defined(nimscript)):
  proc c_memchr(cstr: pointer, c: char, n: csize): pointer {.
                importc: "memchr", header: "<string.h>" .}
  const hasCStringBuiltin = true
else:
  const hasCStringBuiltin = false

proc find*(s, sub: string, start: Natural = 0, last: Natural = 0): int {.noSideEffect,
  rtl, extern: "nsuFindStr".} =
  ## Searches for `sub` in `s` inside range `start`..`last`.
  ## If `last` is unspecified, it defaults to `s.high`.
  ##
  ## Searching is case-sensitive. If `sub` is not in `s`, -1 is returned.
  var a {.noinit.}: SkipTable
  let last = if last==0: s.high else: last
  preprocessSub(sub, a)
  result = findAux(s, sub, start, last, a)

proc find*(s: string, sub: char, start: Natural = 0, last: Natural = 0): int {.noSideEffect,
  rtl, extern: "nsuFindChar".} =
  ## Searches for `sub` in `s` inside range `start`..`last`.
  ## If `last` is unspecified, it defaults to `s.high`.
  ##
  ## Searching is case-sensitive. If `sub` is not in `s`, -1 is returned.
  let last = if last==0: s.high else: last
  when nimvm:
    for i in start..last:
      if sub == s[i]: return i
  else:
    when hasCStringBuiltin:
      let found = c_memchr(s[start].unsafeAddr, sub, last-start+1)
      if not found.isNil:
        return cast[ByteAddress](found) -% cast[ByteAddress](s.cstring)
    else:
      for i in start..last:
        if sub == s[i]: return i

  return -1

proc find*(s: string, chars: set[char], start: Natural = 0, last: Natural = 0): int {.noSideEffect,
  rtl, extern: "nsuFindCharSet".} =
  ## Searches for `chars` in `s` inside range `start`..`last`.
  ## If `last` is unspecified, it defaults to `s.high`.
  ##
  ## If `s` contains none of the characters in `chars`, -1 is returned.
  let last = if last==0: s.high else: last
  for i in start..last:
    if s[i] in chars: return i
  return -1

proc rfind*(s, sub: string, start: int = -1): int {.noSideEffect.} =
  ## Searches for `sub` in `s` in reverse, starting at `start` and going
  ## backwards to 0.
  ##
  ## Searching is case-sensitive. If `sub` is not in `s`, -1 is returned.
  let realStart = if start == -1: s.len else: start
  for i in countdown(realStart-sub.len, 0):
    for j in 0..sub.len-1:
      result = i
      if sub[j] != s[i+j]:
        result = -1
        break
    if result != -1: return
  return -1

proc rfind*(s: string, sub: char, start: int = -1): int {.noSideEffect,
  rtl.} =
  ## Searches for `sub` in `s` in reverse starting at position `start`.
  ##
  ## Searching is case-sensitive. If `sub` is not in `s`, -1 is returned.
  let realStart = if start == -1: s.len-1 else: start
  for i in countdown(realStart, 0):
    if sub == s[i]: return i
  return -1

proc rfind*(s: string, chars: set[char], start: int = -1): int {.noSideEffect.} =
  ## Searches for `chars` in `s` in reverse starting at position `start`.
  ##
  ## Searching is case-sensitive. If `sub` is not in `s`, -1 is returned.
  let realStart = if start == -1: s.len-1 else: start
  for i in countdown(realStart, 0):
    if s[i] in chars: return i
  return -1

proc center*(s: string, width: int, fillChar: char = ' '): string {.
  noSideEffect, rtl, extern: "nsuCenterString".} =
  ## Return the contents of `s` centered in a string `width` long using
  ## `fillChar` as padding.
  ##
  ## The original string is returned if `width` is less than or equal
  ## to `s.len`.
  if width <= s.len:
    return s

  result = newString(width)

  # Left padding will be one fillChar
  # smaller if there are an odd number
  # of characters
  let
    charsLeft = (width - s.len)
    leftPadding = charsLeft div 2

  for i in 0 ..< width:
    if i >= leftPadding and i < leftPadding + s.len:
      # we are where the string should be located
      result[i] = s[i-leftPadding]
    else:
      # we are either before or after where
      # the string s should go
      result[i] = fillChar

proc count*(s: string, sub: string, overlapping: bool = false): int {.
  noSideEffect, rtl, extern: "nsuCountString".} =
  ## Count the occurrences of a substring `sub` in the string `s`.
  ## Overlapping occurrences of `sub` only count when `overlapping`
  ## is set to true.
  var i = 0
  while true:
    i = s.find(sub, i)
    if i < 0:
      break
    if overlapping:
      inc i
    else:
      i += sub.len
    inc result

proc count*(s: string, sub: char): int {.noSideEffect,
  rtl, extern: "nsuCountChar".} =
  ## Count the occurrences of the character `sub` in the string `s`.
  for c in s:
    if c == sub:
      inc result

proc count*(s: string, subs: set[char]): int {.noSideEffect,
  rtl, extern: "nsuCountCharSet".} =
  ## Count the occurrences of the group of character `subs` in the string `s`.
  for c in s:
    if c in subs:
      inc result

proc quoteIfContainsWhite*(s: string): string {.deprecated.} =
  ## Returns ``'"' & s & '"'`` if `s` contains a space and does not
  ## start with a quote, else returns `s`.
  ##
  ## **DEPRECATED** as it was confused for shell quoting function.  For this
  ## application use `osproc.quoteShell <osproc.html#quoteShell>`_.
  if find(s, {' ', '\t'}) >= 0 and s[0] != '"':
    result = '"' & s & '"'
  else:
    result = s

proc contains*(s: string, c: char): bool {.noSideEffect.} =
  ## Same as ``find(s, c) >= 0``.
  return find(s, c) >= 0

proc contains*(s, sub: string): bool {.noSideEffect.} =
  ## Same as ``find(s, sub) >= 0``.
  return find(s, sub) >= 0

proc contains*(s: string, chars: set[char]): bool {.noSideEffect.} =
  ## Same as ``find(s, chars) >= 0``.
  return find(s, chars) >= 0

proc replace*(s, sub: string, by = ""): string {.noSideEffect,
  rtl, extern: "nsuReplaceStr".} =
  ## Replaces `sub` in `s` by the string `by`.
  var a {.noinit.}: SkipTable
  result = ""
  preprocessSub(sub, a)
  let last = s.high
  var i = 0
  while true:
    var j = findAux(s, sub, i, last, a)
    if j < 0: break
    add result, substr(s, i, j - 1)
    add result, by
    i = j + len(sub)
  # copy the rest:
  add result, substr(s, i)

proc replace*(s: string, sub, by: char): string {.noSideEffect,
  rtl, extern: "nsuReplaceChar".} =
  ## Replaces `sub` in `s` by the character `by`.
  ##
  ## Optimized version of `replace <#replace,string,string>`_ for characters.
  result = newString(s.len)
  var i = 0
  while i < s.len:
    if s[i] == sub: result[i] = by
    else: result[i] = s[i]
    inc(i)

proc replaceWord*(s, sub: string, by = ""): string {.noSideEffect,
  rtl, extern: "nsuReplaceWord".} =
  ## Replaces `sub` in `s` by the string `by`.
  ##
  ## Each occurrence of `sub` has to be surrounded by word boundaries
  ## (comparable to ``\\w`` in regular expressions), otherwise it is not
  ## replaced.
  const wordChars = {'a'..'z', 'A'..'Z', '0'..'9', '_', '\128'..'\255'}
  var a {.noinit.}: SkipTable
  result = ""
  preprocessSub(sub, a)
  var i = 0
  let last = s.high
  while true:
    var j = findAux(s, sub, i, last, a)
    if j < 0: break
    # word boundary?
    if (j == 0 or s[j-1] notin wordChars) and
        (j+sub.len >= s.len or s[j+sub.len] notin wordChars):
      add result, substr(s, i, j - 1)
      add result, by
      i = j + len(sub)
    else:
      add result, substr(s, i, j)
      i = j + 1
  # copy the rest:
  add result, substr(s, i)

proc delete*(s: var string, first, last: int) {.noSideEffect,
  rtl, extern: "nsuDelete".} =
  ## Deletes in `s` the characters at position `first` .. `last`.
  ##
  ## This modifies `s` itself, it does not return a copy.
  var i = first
  var j = last+1
  var newLen = len(s)-j+i
  while i < newLen:
    s[i] = s[j]
    inc(i)
    inc(j)
  setLen(s, newLen)

proc parseOctInt*(s: string): int {.noSideEffect,
  rtl, extern: "nsuParseOctInt".} =
  ## Parses an octal integer value contained in `s`.
  ##
  ## If `s` is not a valid integer, `ValueError` is raised. `s` can have one
  ## of the following optional prefixes: ``0o``, ``0O``.  Underscores within
  ## `s` are ignored.
  var i = 0
  if s[i] == '0' and (s[i+1] == 'o' or s[i+1] == 'O'): inc(i, 2)
  while true:
    case s[i]
    of '_': inc(i)
    of '0'..'7':
      result = result shl 3 or (ord(s[i]) - ord('0'))
      inc(i)
    of '\0': break
    else: raise newException(ValueError, "invalid integer: " & s)

proc toOct*(x: BiggestInt, len: Positive): string {.noSideEffect,
  rtl, extern: "nsuToOct".} =
  ## Converts `x` into its octal representation.
  ##
  ## The resulting string is always `len` characters long. No leading ``0o``
  ## prefix is generated.
  var
    mask: BiggestInt = 7
    shift: BiggestInt = 0
  assert(len > 0)
  result = newString(len)
  for j in countdown(len-1, 0):
    result[j] = chr(int((x and mask) shr shift) + ord('0'))
    shift = shift + 3
    mask = mask shl 3

proc toBin*(x: BiggestInt, len: Positive): string {.noSideEffect,
  rtl, extern: "nsuToBin".} =
  ## Converts `x` into its binary representation.
  ##
  ## The resulting string is always `len` characters long. No leading ``0b``
  ## prefix is generated.
  var
    mask: BiggestInt = 1
    shift: BiggestInt = 0
  assert(len > 0)
  result = newString(len)
  for j in countdown(len-1, 0):
    result[j] = chr(int((x and mask) shr shift) + ord('0'))
    shift = shift + 1
    mask = mask shl 1

proc insertSep*(s: string, sep = '_', digits = 3): string {.noSideEffect,
  rtl, extern: "nsuInsertSep".} =
  ## Inserts the separator `sep` after `digits` digits from right to left.
  ##
  ## Even though the algorithm works with any string `s`, it is only useful
  ## if `s` contains a number.
  ## Example: ``insertSep("1000000") == "1_000_000"``
  var L = (s.len-1) div digits + s.len
  result = newString(L)
  var j = 0
  dec(L)
  for i in countdown(len(s)-1, 0):
    if j == digits:
      result[L] = sep
      dec(L)
      j = 0
    result[L] = s[i]
    inc(j)
    dec(L)

proc escape*(s: string, prefix = "\"", suffix = "\""): string {.noSideEffect,
  rtl, extern: "nsuEscape".} =
  ## Escapes a string `s`.
  ##
  ## This does these operations (at the same time):
  ## * replaces any ``\`` by ``\\``
  ## * replaces any ``'`` by ``\'``
  ## * replaces any ``"`` by ``\"``
  ## * replaces any other character in the set ``{'\0'..'\31', '\128'..'\255'}``
  ##   by ``\xHH`` where ``HH`` is its hexadecimal value.
  ## The procedure has been designed so that its output is usable for many
  ## different common syntaxes. The resulting string is prefixed with
  ## `prefix` and suffixed with `suffix`. Both may be empty strings.
  result = newStringOfCap(s.len + s.len shr 2)
  result.add(prefix)
  for c in items(s):
    case c
    of '\0'..'\31', '\128'..'\255':
      add(result, "\\x")
      add(result, toHex(ord(c), 2))
    of '\\': add(result, "\\\\")
    of '\'': add(result, "\\'")
    of '\"': add(result, "\\\"")
    else: add(result, c)
  add(result, suffix)

proc unescape*(s: string, prefix = "\"", suffix = "\""): string {.noSideEffect,
  rtl, extern: "nsuUnescape".} =
  ## Unescapes a string `s`.
  ##
  ## This complements `escape <#escape>`_ as it performs the opposite
  ## operations.
  ##
  ## If `s` does not begin with ``prefix`` and end with ``suffix`` a
  ## ValueError exception will be raised.
  result = newStringOfCap(s.len)
  var i = prefix.len
  if not s.startsWith(prefix):
    raise newException(ValueError,
                       "String does not start with a prefix of: " & prefix)
  while true:
    if i == s.len-suffix.len: break
    case s[i]
    of '\\':
      case s[i+1]:
      of 'x':
        inc i, 2
        var c: int
        i += parseutils.parseHex(s, c, i, maxLen=2)
        result.add(chr(c))
        dec i, 2
      of '\\':
        result.add('\\')
      of '\'':
        result.add('\'')
      of '\"':
        result.add('\"')
      else: result.add("\\" & s[i+1])
      inc(i)
    of '\0': break
    else:
      result.add(s[i])
    inc(i)
  if not s.endsWith(suffix):
    raise newException(ValueError,
                       "String does not end with a suffix of: " & suffix)

proc validIdentifier*(s: string): bool {.noSideEffect,
  rtl, extern: "nsuValidIdentifier".} =
  ## Returns true if `s` is a valid identifier.
  ##
  ## A valid identifier starts with a character of the set `IdentStartChars`
  ## and is followed by any number of characters of the set `IdentChars`.
  if s[0] in IdentStartChars:
    for i in 1..s.len-1:
      if s[i] notin IdentChars: return false
    return true

proc editDistance*(a, b: string): int {.noSideEffect,
  rtl, extern: "nsuEditDistance".} =
  ## Returns the edit distance between `a` and `b`.
  ##
  ## This uses the `Levenshtein`:idx: distance algorithm with only a linear
  ## memory overhead.  This implementation is highly optimized!
  var len1 = a.len
  var len2 = b.len
  if len1 > len2:
    # make `b` the longer string
    return editDistance(b, a)

  # strip common prefix:
  var s = 0
  while a[s] == b[s] and a[s] != '\0':
    inc(s)
    dec(len1)
    dec(len2)
  # strip common suffix:
  while len1 > 0 and len2 > 0 and a[s+len1-1] == b[s+len2-1]:
    dec(len1)
    dec(len2)
  # trivial cases:
  if len1 == 0: return len2
  if len2 == 0: return len1

  # another special case:
  if len1 == 1:
    for j in s..s+len2-1:
      if a[s] == b[j]: return len2 - 1
    return len2

  inc(len1)
  inc(len2)
  var half = len1 shr 1
  # initalize first row:
  #var row = cast[ptr array[0..high(int) div 8, int]](alloc(len2*sizeof(int)))
  var row: seq[int]
  newSeq(row, len2)
  var e = s + len2 - 1 # end marker
  for i in 1..len2 - half - 1: row[i] = i
  row[0] = len1 - half - 1
  for i in 1 .. len1 - 1:
    var char1 = a[i + s - 1]
    var char2p: int
    var D, x: int
    var p: int
    if i >= len1 - half:
      # skip the upper triangle:
      var offset = i - len1 + half
      char2p = offset
      p = offset
      var c3 = row[p] + ord(char1 != b[s + char2p])
      inc(p)
      inc(char2p)
      x = row[p] + 1
      D = x
      if x > c3: x = c3
      row[p] = x
      inc(p)
    else:
      p = 1
      char2p = 0
      D = i
      x = i
    if i <= half + 1:
      # skip the lower triangle:
      e = len2 + i - half - 2
    # main:
    while p <= e:
      dec(D)
      var c3 = D + ord(char1 != b[char2p + s])
      inc(char2p)
      inc(x)
      if x > c3: x = c3
      D = row[p] + 1
      if x > D: x = D
      row[p] = x
      inc(p)
    # lower triangle sentinel:
    if i <= half:
      dec(D)
      var c3 = D + ord(char1 != b[char2p + s])
      inc(x)
      if x > c3: x = c3
      row[p] = x
  result = row[e]
  #dealloc(row)


# floating point formating:
when not defined(js):
  proc c_sprintf(buf, frmt: cstring): cint {.header: "<stdio.h>",
                                     importc: "sprintf", varargs, noSideEffect.}

type
  FloatFormatMode* = enum ## the different modes of floating point formating
    ffDefault,         ## use the shorter floating point notation
    ffDecimal,         ## use decimal floating point notation
    ffScientific       ## use scientific notation (using ``e`` character)

{.deprecated: [TFloatFormat: FloatFormatMode].}

proc formatBiggestFloat*(f: BiggestFloat, format: FloatFormatMode = ffDefault,
                         precision: range[0..32] = 16;
                         decimalSep = '.'): string {.
                         noSideEffect, rtl, extern: "nsu$1".} =
  ## Converts a floating point value `f` to a string.
  ##
  ## If ``format == ffDecimal`` then precision is the number of digits to
  ## be printed after the decimal point.
  ## If ``format == ffScientific`` then precision is the maximum number
  ## of significant digits to be printed.
  ## `precision`'s default value is the maximum number of meaningful digits
  ## after the decimal point for Nim's ``biggestFloat`` type.
  ##
  ## If ``precision == 0``, it tries to format it nicely.
  when defined(js):
    var res: cstring
    case format
    of ffDefault:
      {.emit: "`res` = `f`.toString();".}
    of ffDecimal:
      {.emit: "`res` = `f`.toFixed(`precision`);".}
    of ffScientific:
      {.emit: "`res` = `f`.toExponential(`precision`);".}
    result = $res
    for i in 0 ..< result.len:
      # Depending on the locale either dot or comma is produced,
      # but nothing else is possible:
      if result[i] in {'.', ','}: result[i] = decimalsep
  else:
    const floatFormatToChar: array[FloatFormatMode, char] = ['g', 'f', 'e']
    var
      frmtstr {.noinit.}: array[0..5, char]
      buf {.noinit.}: array[0..2500, char]
      L: cint
    frmtstr[0] = '%'
    if precision > 0:
      frmtstr[1] = '#'
      frmtstr[2] = '.'
      frmtstr[3] = '*'
      frmtstr[4] = floatFormatToChar[format]
      frmtstr[5] = '\0'
      L = c_sprintf(buf, frmtstr, precision, f)
    else:
      frmtstr[1] = floatFormatToChar[format]
      frmtstr[2] = '\0'
      L = c_sprintf(buf, frmtstr, f)
    result = newString(L)
    for i in 0 ..< L:
      # Depending on the locale either dot or comma is produced,
      # but nothing else is possible:
      if buf[i] in {'.', ','}: result[i] = decimalsep
      else: result[i] = buf[i]

proc formatFloat*(f: float, format: FloatFormatMode = ffDefault,
                  precision: range[0..32] = 16; decimalSep = '.'): string {.
                  noSideEffect, rtl, extern: "nsu$1".} =
  ## Converts a floating point value `f` to a string.
  ##
  ## If ``format == ffDecimal`` then precision is the number of digits to
  ## be printed after the decimal point.
  ## If ``format == ffScientific`` then precision is the maximum number
  ## of significant digits to be printed.
  ## `precision`'s default value is the maximum number of meaningful digits
  ## after the decimal point for Nim's ``float`` type.
  result = formatBiggestFloat(f, format, precision, decimalSep)

proc trimZeros*(x: var string) {.noSideEffect.} =
  ## Trim trailing zeros from a formatted floating point
  ## value (`x`).  Modifies the passed value.
  var spl: seq[string]
  if x.contains('.') or x.contains(','):
    if x.contains('e'):
      spl= x.split('e')
      x = spl[0]
    while x[x.high] == '0':
      x.setLen(x.len-1)
    if x[x.high] in [',', '.']:
      x.setLen(x.len-1)
    if spl.len > 0:
      x &= "e" & spl[1]

type
  BinaryPrefixMode* = enum ## the different names for binary prefixes
    bpIEC, # use the IEC/ISO standard prefixes such as kibi
    bpColloquial # use the colloquial kilo, mega etc

proc formatSize*(bytes: int64,
                 decimalSep = '.',
                 prefix = bpIEC,
                 includeSpace = false): string {.noSideEffect.} =
  ## Rounds and formats `bytes`.
  ##
  ## By default, uses the IEC/ISO standard binary prefixes, so 1024 will be
  ## formatted as 1KiB.  Set prefix to `bpColloquial` to use the colloquial
  ## names from the SI standard (e.g. k for 1000 being reused as 1024).
  ##
  ## `includeSpace` can be set to true to include the (SI preferred) space
  ## between the number and the unit (e.g. 1 KiB).
  ##
  ## Examples:
  ##
  ## .. code-block:: nim
  ##
  ##    formatSize((1'i64 shl 31) + (300'i64 shl 20)) == "2.293GiB"
  ##    formatSize((2.234*1024*1024).int) == "2.234MiB"
  ##    formatSize(4096, includeSpace=true) == "4 KiB"
  ##    formatSize(4096, prefix=bpColloquial, includeSpace=true) == "4 kB"
  ##    formatSize(4096) == "4KiB"
  ##    formatSize(5_378_934, prefix=bpColloquial, decimalSep=',') == "5,13MB"
  ##
  const iecPrefixes = ["", "Ki", "Mi", "Gi", "Ti", "Pi", "Ei", "Zi", "Yi"]
  const collPrefixes = ["", "k", "M", "G", "T", "P", "E", "Z", "Y"]
  var
    xb: int64 = bytes
    fbytes: float
    last_xb: int64 = bytes
    matchedIndex: int
    prefixes: array[9, string]
  if prefix == bpColloquial:
    prefixes = collPrefixes
  else:
    prefixes = iecPrefixes

  # Iterate through prefixes seeing if value will be greater than
  # 0 in each case
  for index in 1..<prefixes.len:
    last_xb = xb
    xb = bytes div (1'i64 shl (index*10))
    matchedIndex = index
    if xb == 0:
      xb = last_xb
      matchedIndex = index - 1
      break
  # xb has the integer number for the latest value; index should be correct
  fbytes = bytes.float / (1'i64 shl (matchedIndex*10)).float
  result = formatFloat(fbytes, format=ffDecimal, precision=3, decimalSep=decimalSep)
  result.trimZeros()
  if includeSpace:
    result &= " "
  result &= prefixes[matchedIndex]
  result &= "B"

proc formatEng*(f: BiggestFloat,
                precision: range[0..32] = 10,
                trim: bool = true,
                siPrefix: bool = false,
                unit: string = nil,
                decimalSep = '.'): string {.noSideEffect.} =
  ## Converts a floating point value `f` to a string using engineering notation.
  ##
  ## Numbers in of the range -1000.0<f<1000.0 will be formatted without an
  ## exponent.  Numbers outside of this range will be formatted as a
  ## significand in the range -1000.0<f<1000.0 and an exponent that will always
  ## be an integer multiple of 3, corresponding with the SI prefix scale k, M,
  ## G, T etc for numbers with an absolute value greater than 1 and m, μ, n, p
  ## etc for numbers with an absolute value less than 1.
  ##
  ## The default configuration (`trim=true` and `precision=10`) shows the
  ## **shortest** form that precisely (up to a maximum of 10 decimal places)
  ## displays the value.  For example, 4.100000 will be displayed as 4.1 (which
  ## is mathematically identical) whereas 4.1000003 will be displayed as
  ## 4.1000003.
  ##
  ## If `trim` is set to true, trailing zeros will be removed; if false, the
  ## number of digits specified by `precision` will always be shown.
  ##
  ## `precision` can be used to set the number of digits to be shown after the
  ## decimal point or (if `trim` is true) the maximum number of digits to be
  ## shown.
  ##
  ## .. code-block:: nim
  ##
  ##    formatEng(0, 2, trim=false) == "0.00"
  ##    formatEng(0, 2) == "0"
  ##    formatEng(0.053, 0) == "53e-3"
  ##    formatEng(52731234, 2) == "52.73e6"
  ##    formatEng(-52731234, 2) == "-52.73e6"
  ##
  ## If `siPrefix` is set to true, the number will be displayed with the SI
  ## prefix corresponding to the exponent.  For example 4100 will be displayed
  ## as "4.1 k" instead of "4.1e3".  Note that `u` is used for micro- in place
  ## of the greek letter mu (μ) as per ISO 2955.  Numbers with an absolute
  ## value outside of the range 1e-18<f<1000e18 (1a<f<1000E) will be displayed
  ## with an exponent rather than an SI prefix, regardless of whether
  ## `siPrefix` is true.
  ##
  ## If `unit` is not nil, the provided unit will be appended to the string
  ## (with a space as required by the SI standard).  This behaviour is slightly
  ## different to appending the unit to the result as the location of the space
  ## is altered depending on whether there is an exponent.
  ##
  ## .. code-block:: nim
  ##
  ##    formatEng(4100, siPrefix=true, unit="V") == "4.1 kV"
  ##    formatEng(4.1, siPrefix=true, unit="V") == "4.1 V"
  ##    formatEng(4.1, siPrefix=true) == "4.1" # Note lack of space
  ##    formatEng(4100, siPrefix=true) == "4.1 k"
  ##    formatEng(4.1, siPrefix=true, unit="") == "4.1 " # Space with unit=""
  ##    formatEng(4100, siPrefix=true, unit="") == "4.1 k"
  ##    formatEng(4100) == "4.1e3"
  ##    formatEng(4100, unit="V") == "4.1e3 V"
  ##    formatEng(4100, unit="") == "4.1e3 " # Space with unit=""
  ##
  ## `decimalSep` is used as the decimal separator
  var
    absolute: BiggestFloat
    significand: BiggestFloat
    fexponent: BiggestFloat
    exponent: int
    splitResult: seq[string]
    suffix: string = ""
  proc getPrefix(exp: int): char =
    ## Get the SI prefix for a given exponent
    ##
    ## Assumes exponent is a multiple of 3; returns ' ' if no prefix found
    const siPrefixes = ['a','f','p','n','u','m',' ','k','M','G','T','P','E']
    var index: int = (exp div 3) + 6
    result = ' '
    if index in low(siPrefixes)..high(siPrefixes):
      result = siPrefixes[index]

  # Most of the work is done with the sign ignored, so get the absolute value
  absolute = abs(f)
  significand = f

  if absolute == 0.0:
    # Simple case: just format it and force the exponent to 0
    exponent = 0
    result = significand.formatBiggestFloat(ffDecimal, precision, decimalSep='.')
  else:
    # Find the best exponent that's a multiple of 3
    fexponent = round(floor(log10(absolute)))
    fexponent = 3.0 * round(floor(fexponent / 3.0))
    # Adjust the significand for the new exponent
    significand /= pow(10.0, fexponent)

    # Round the significand and check whether it has affected
    # the exponent
    significand = round(significand, precision)
    absolute = abs(significand)
    if absolute >= 1000.0:
      significand *= 0.001
      fexponent += 3
    # Components of the result:
    result = significand.formatBiggestFloat(ffDecimal, precision, decimalSep='.')
    exponent = fexponent.int()

  splitResult = result.split('.')
  result = splitResult[0]
  # result should have at most one decimal character
  if splitResult.len() > 1:
    # If trim is set, we get rid of trailing zeros.  Don't use trimZeros here as
    # we can be a bit more efficient through knowledge that there will never be
    # an exponent in this part.
    if trim:
        while splitResult[1].endsWith("0"):
          # Trim last character
          splitResult[1].setLen(splitResult[1].len-1)
        if splitResult[1].len() > 0:
          result &= decimalSep & splitResult[1]
    else:
      result &= decimalSep & splitResult[1]

  # Combine the results accordingly
  if siPrefix and exponent != 0:
    var p = getPrefix(exponent)
    if p != ' ':
      suffix = " " & p
      exponent = 0 # Exponent replaced by SI prefix
  if suffix == "" and unit != nil:
    suffix = " "
  if unit != nil:
    suffix &= unit
  if exponent != 0:
    result &= "e" & $exponent
  result &= suffix

proc findNormalized(x: string, inArray: openArray[string]): int =
  var i = 0
  while i < high(inArray):
    if cmpIgnoreStyle(x, inArray[i]) == 0: return i
    inc(i, 2) # incrementing by 1 would probably lead to a
              # security hole...
  return -1

proc invalidFormatString() {.noinline.} =
  raise newException(ValueError, "invalid format string")

proc addf*(s: var string, formatstr: string, a: varargs[string, `$`]) {.
  noSideEffect, rtl, extern: "nsuAddf".} =
  ## The same as ``add(s, formatstr % a)``, but more efficient.
  const PatternChars = {'a'..'z', 'A'..'Z', '0'..'9', '\128'..'\255', '_'}
  var i = 0
  var num = 0
  while i < len(formatstr):
    if formatstr[i] == '$':
      case formatstr[i+1] # again we use the fact that strings
                          # are zero-terminated here
      of '#':
        if num >% a.high: invalidFormatString()
        add s, a[num]
        inc i, 2
        inc num
      of '$':
        add s, '$'
        inc(i, 2)
      of '1'..'9', '-':
        var j = 0
        inc(i) # skip $
        var negative = formatstr[i] == '-'
        if negative: inc i
        while formatstr[i] in Digits:
          j = j * 10 + ord(formatstr[i]) - ord('0')
          inc(i)
        let idx = if not negative: j-1 else: a.len-j
        if idx >% a.high: invalidFormatString()
        add s, a[idx]
      of '{':
        var j = i+1
        while formatstr[j] notin {'\0', '}'}: inc(j)
        var x = findNormalized(substr(formatstr, i+2, j-1), a)
        if x >= 0 and x < high(a): add s, a[x+1]
        else: invalidFormatString()
        i = j+1
      of 'a'..'z', 'A'..'Z', '\128'..'\255', '_':
        var j = i+1
        while formatstr[j] in PatternChars: inc(j)
        var x = findNormalized(substr(formatstr, i+1, j-1), a)
        if x >= 0 and x < high(a): add s, a[x+1]
        else: invalidFormatString()
        i = j
      else:
        invalidFormatString()
    else:
      add s, formatstr[i]
      inc(i)

proc `%` *(formatstr: string, a: openArray[string]): string {.noSideEffect,
  rtl, extern: "nsuFormatOpenArray".} =
  ## Interpolates a format string with the values from `a`.
  ##
  ## The `substitution`:idx: operator performs string substitutions in
  ## `formatstr` and returns a modified `formatstr`. This is often called
  ## `string interpolation`:idx:.
  ##
  ## This is best explained by an example:
  ##
  ## .. code-block:: nim
  ##   "$1 eats $2." % ["The cat", "fish"]
  ##
  ## Results in:
  ##
  ## .. code-block:: nim
  ##   "The cat eats fish."
  ##
  ## The substitution variables (the thing after the ``$``) are enumerated
  ## from 1 to ``a.len``.
  ## To produce a verbatim ``$``, use ``$$``.
  ## The notation ``$#`` can be used to refer to the next substitution
  ## variable:
  ##
  ## .. code-block:: nim
  ##   "$# eats $#." % ["The cat", "fish"]
  ##
  ## Substitution variables can also be words (that is
  ## ``[A-Za-z_]+[A-Za-z0-9_]*``) in which case the arguments in `a` with even
  ## indices are keys and with odd indices are the corresponding values.
  ## An example:
  ##
  ## .. code-block:: nim
  ##   "$animal eats $food." % ["animal", "The cat", "food", "fish"]
  ##
  ## Results in:
  ##
  ## .. code-block:: nim
  ##   "The cat eats fish."
  ##
  ## The variables are compared with `cmpIgnoreStyle`. `ValueError` is
  ## raised if an ill-formed format string has been passed to the `%` operator.
  result = newStringOfCap(formatstr.len + a.len shl 4)
  addf(result, formatstr, a)

proc `%` *(formatstr, a: string): string {.noSideEffect,
  rtl, extern: "nsuFormatSingleElem".} =
  ## This is the same as ``formatstr % [a]``.
  result = newStringOfCap(formatstr.len + a.len)
  addf(result, formatstr, [a])

proc format*(formatstr: string, a: varargs[string, `$`]): string {.noSideEffect,
  rtl, extern: "nsuFormatVarargs".} =
  ## This is the same as ``formatstr % a`` except that it supports
  ## auto stringification.
  result = newStringOfCap(formatstr.len + a.len)
  addf(result, formatstr, a)

{.pop.}

proc removeSuffix*(s: var string, chars: set[char] = Newlines) {.
  rtl, extern: "nsuRemoveSuffixCharSet".} =
  ## Removes the first matching character from the string (in-place) given a
  ## set of characters. If the set of characters is only equal to `Newlines`
  ## then it will remove both the newline and return feed.
  ## .. code-block:: nim
  ##   var
  ##     userInput = "Hello World!\r\n"
  ##     otherInput = "Hello!?!"
  ##   userInput.removeSuffix
  ##   userInput == "Hello World!"
  ##   userInput.removeSuffix({'!', '?'})
  ##   userInput == "Hello World"
  ##   otherInput.removeSuffix({'!', '?'})
  ##   otherInput == "Hello!?"

  var last = len(s) - 1

  if chars == Newlines:
    if s[last] == '\10':
      last -= 1

    if s[last] == '\13':
      last -= 1

  else:
    if s[last] in chars:
      last -= 1

  s.setLen(last + 1)

proc removeSuffix*(s: var string, c: char) {.
  rtl, extern: "nsuRemoveSuffixChar".} =
  ## Removes a single character (in-place) from a string.
  ## .. code-block:: nim
  ##   var
  ##     table = "users"
  ##   table.removeSuffix('s')
  ##   table == "user"
  removeSuffix(s, chars = {c})

proc removeSuffix*(s: var string, suffix: string) {.
  rtl, extern: "nsuRemoveSuffixString".} =
  ## Remove the first matching suffix (in-place) from a string.
  ## .. code-block:: nim
  ##   var
  ##     answers = "yeses"
  ##   answers.removeSuffix("es")
  ##   answers == "yes"

  var newLen = s.len

  if s.endsWith(suffix):
    newLen -= len(suffix)

  s.setLen(newLen)

when isMainModule:
  doAssert align("abc", 4) == " abc"
  doAssert align("a", 0) == "a"
  doAssert align("1232", 6) == "  1232"
  doAssert align("1232", 6, '#') == "##1232"

  let
    inp = """ this is a long text --  muchlongerthan10chars and here
               it goes"""
    outp = " this is a\nlong text\n--\nmuchlongerthan10chars\nand here\nit goes"
  doAssert wordWrap(inp, 10, false) == outp

  doAssert formatBiggestFloat(0.00000000001, ffDecimal, 11) == "0.00000000001"
  doAssert formatBiggestFloat(0.00000000001, ffScientific, 1, ',') in
                                                   ["1,0e-11", "1,0e-011"]

  doAssert "$# $3 $# $#" % ["a", "b", "c"] == "a c b c"

  block: # formatSize tests
    doAssert formatSize((1'i64 shl 31) + (300'i64 shl 20)) == "2.293GiB"
    doAssert formatSize((2.234*1024*1024).int) == "2.234MiB"
    doAssert formatSize(4096) == "4KiB"
    doAssert formatSize(4096, prefix=bpColloquial, includeSpace=true) == "4 kB"
    doAssert formatSize(4096, includeSpace=true) == "4 KiB"
    doAssert formatSize(5_378_934, prefix=bpColloquial, decimalSep=',') == "5,13MB"

  doAssert "$animal eats $food." % ["animal", "The cat", "food", "fish"] ==
           "The cat eats fish."

  doAssert "-ld a-ldz -ld".replaceWord("-ld") == " a-ldz "
  doAssert "-lda-ldz -ld abc".replaceWord("-ld") == "-lda-ldz  abc"

  type MyEnum = enum enA, enB, enC, enuD, enE
  doAssert parseEnum[MyEnum]("enu_D") == enuD

  doAssert parseEnum("invalid enum value", enC) == enC

  doAssert center("foo", 13) == "     foo     "
  doAssert center("foo", 0) == "foo"
  doAssert center("foo", 3, fillChar = 'a') == "foo"
  doAssert center("foo", 10, fillChar = '\t') == "\t\t\tfoo\t\t\t\t"

  doAssert count("foofoofoo", "foofoo") == 1
  doAssert count("foofoofoo", "foofoo", overlapping = true) == 2
  doAssert count("foofoofoo", 'f') == 3
  doAssert count("foofoofoobar", {'f','b'}) == 4

  doAssert strip("  foofoofoo  ") == "foofoofoo"
  doAssert strip("sfoofoofoos", chars = {'s'}) == "foofoofoo"
  doAssert strip("barfoofoofoobar", chars = {'b', 'a', 'r'}) == "foofoofoo"
  doAssert strip("stripme but don't strip this stripme",
                 chars = {'s', 't', 'r', 'i', 'p', 'm', 'e'}) ==
                 " but don't strip this "
  doAssert strip("sfoofoofoos", leading = false, chars = {'s'}) == "sfoofoofoo"
  doAssert strip("sfoofoofoos", trailing = false, chars = {'s'}) == "foofoofoos"

  doAssert "  foo\n  bar".indent(4, "Q") == "QQQQ  foo\nQQQQ  bar"

  doAssert isAlphaAscii('r')
  doAssert isAlphaAscii('A')
  doAssert(not isAlphaAscii('$'))

  doAssert isAlphaAscii("Rasp")
  doAssert isAlphaAscii("Args")
  doAssert(not isAlphaAscii("$Tomato"))

  doAssert isAlphaNumeric('3')
  doAssert isAlphaNumeric('R')
  doAssert(not isAlphaNumeric('!'))

  doAssert isAlphaNumeric("34ABc")
  doAssert isAlphaNumeric("Rad")
  doAssert isAlphaNumeric("1234")
  doAssert(not isAlphaNumeric("@nose"))

  doAssert isDigit('3')
  doAssert(not isDigit('a'))
  doAssert(not isDigit('%'))

  doAssert isDigit("12533")
  doAssert(not isDigit("12.33"))
  doAssert(not isDigit("A45b"))

  doAssert isSpaceAscii('\t')
  doAssert isSpaceAscii('\l')
  doAssert(not isSpaceAscii('A'))

  doAssert isSpaceAscii("\t\l \v\r\f")
  doAssert isSpaceAscii("       ")
  doAssert(not isSpaceAscii("ABc   \td"))

  doAssert(isNilOrEmpty(""))
  doAssert(isNilOrEmpty(nil))
  doAssert(not isNilOrEmpty("test"))
  doAssert(not isNilOrEmpty(" "))

  doAssert(isNilOrWhitespace(""))
  doAssert(isNilOrWhitespace(nil))
  doAssert(isNilOrWhitespace("       "))
  doAssert(isNilOrWhitespace("\t\l \v\r\f"))
  doAssert(not isNilOrWhitespace("ABc   \td"))

  doAssert isLowerAscii('a')
  doAssert isLowerAscii('z')
  doAssert(not isLowerAscii('A'))
  doAssert(not isLowerAscii('5'))
  doAssert(not isLowerAscii('&'))

  doAssert isLowerAscii("abcd")
  doAssert(not isLowerAscii("abCD"))
  doAssert(not isLowerAscii("33aa"))

  doAssert isUpperAscii('A')
  doAssert(not isUpperAscii('b'))
  doAssert(not isUpperAscii('5'))
  doAssert(not isUpperAscii('%'))

  doAssert isUpperAscii("ABC")
  doAssert(not isUpperAscii("AAcc"))
  doAssert(not isUpperAscii("A#$"))

  doAssert rsplit("foo bar", seps=Whitespace) == @["foo", "bar"]
  doAssert rsplit(" foo bar", seps=Whitespace, maxsplit=1) == @[" foo", "bar"]
  doAssert rsplit(" foo bar ", seps=Whitespace, maxsplit=1) == @[" foo bar", ""]
  doAssert rsplit(":foo:bar", sep=':') == @["", "foo", "bar"]
  doAssert rsplit(":foo:bar", sep=':', maxsplit=2) == @["", "foo", "bar"]
  doAssert rsplit(":foo:bar", sep=':', maxsplit=3) == @["", "foo", "bar"]
  doAssert rsplit("foothebar", sep="the") == @["foo", "bar"]

  doAssert(unescape(r"\x013", "", "") == "\x013")

  doAssert join(["foo", "bar", "baz"]) == "foobarbaz"
  doAssert join(@["foo", "bar", "baz"], ", ") == "foo, bar, baz"
  doAssert join([1, 2, 3]) == "123"
  doAssert join(@[1, 2, 3], ", ") == "1, 2, 3"

  doAssert """~~!!foo
~~!!bar
~~!!baz""".unindent(2, "~~!!") == "foo\nbar\nbaz"

  doAssert """~~!!foo
~~!!bar
~~!!baz""".unindent(2, "~~!!aa") == "~~!!foo\n~~!!bar\n~~!!baz"
  doAssert """~~foo
~~  bar
~~  baz""".unindent(4, "~") == "foo\n  bar\n  baz"
  doAssert """foo
bar
    baz
  """.unindent(4) == "foo\nbar\nbaz\n"
  doAssert """foo
    bar
    baz
  """.unindent(2) == "foo\n  bar\n  baz\n"
  doAssert """foo
    bar
    baz
  """.unindent(100) == "foo\nbar\nbaz\n"

  doAssert """foo
    foo
    bar
  """.unindent() == "foo\nfoo\nbar\n"

  let s = " this is an example  "
  let s2 = ":this;is;an:example;;"

  doAssert s.split() == @["", "this", "is", "an", "example", "", ""]
  doAssert s2.split(seps={':', ';'}) == @["", "this", "is", "an", "example", "", ""]
  doAssert s.split(maxsplit=4) == @["", "this", "is", "an", "example  "]
  doAssert s.split(' ', maxsplit=1) == @["", "this is an example  "]
  doAssert s.split(" ", maxsplit=4) == @["", "this", "is", "an", "example  "]

  block: # formatEng tests
    doAssert formatEng(0, 2, trim=false) == "0.00"
    doAssert formatEng(0, 2) == "0"
    doAssert formatEng(53, 2, trim=false) == "53.00"
    doAssert formatEng(0.053, 2, trim=false) == "53.00e-3"
    doAssert formatEng(0.053, 4, trim=false) == "53.0000e-3"
    doAssert formatEng(0.053, 4, trim=true) == "53e-3"
    doAssert formatEng(0.053, 0) == "53e-3"
    doAssert formatEng(52731234) == "52.731234e6"
    doAssert formatEng(-52731234) == "-52.731234e6"
    doAssert formatEng(52731234, 1) == "52.7e6"
    doAssert formatEng(-52731234, 1) == "-52.7e6"
    doAssert formatEng(52731234, 1, decimalSep=',') == "52,7e6"
    doAssert formatEng(-52731234, 1, decimalSep=',') == "-52,7e6"

    doAssert formatEng(4100, siPrefix=true, unit="V") == "4.1 kV"
    doAssert formatEng(4.1, siPrefix=true, unit="V") == "4.1 V"
    doAssert formatEng(4.1, siPrefix=true) == "4.1" # Note lack of space
    doAssert formatEng(4100, siPrefix=true) == "4.1 k"
    doAssert formatEng(4.1, siPrefix=true, unit="") == "4.1 " # Includes space
    doAssert formatEng(4100, siPrefix=true, unit="") == "4.1 k"
    doAssert formatEng(4100) == "4.1e3"
    doAssert formatEng(4100, unit="V") == "4.1e3 V"
    doAssert formatEng(4100, unit="") == "4.1e3 " # Space with unit=""
    # Don't use SI prefix as number is too big
    doAssert formatEng(3.1e22, siPrefix=true, unit="a") == "31e21 a"
    # Don't use SI prefix as number is too small
    doAssert formatEng(3.1e-25, siPrefix=true, unit="A") == "310e-27 A"

  block: # startsWith / endsWith char tests
    var s = "abcdef"
    doAssert s.startsWith('a')
    doAssert s.startsWith('b') == false
    doAssert s.endsWith('f')
    doAssert s.endsWith('a') == false
    doAssert s.endsWith('\0') == false

  #echo("strutils tests passed")
