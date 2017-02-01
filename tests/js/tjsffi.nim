discard """
  output: '''true
true
true
true
true
true
true
true
true
true
true
true
true
true
true
true'''
"""

import macros, jsffi

# Tests for JsObject
# Test JsObject []= and []
block:
  proc test(): bool =
    let obj = newJsObject()
    var working = true
    obj["a"] = 11
    obj["b"] = "test"
    obj["c"] = "test".cstring
    working = working and obj["a"].to(int) == 11
    working = working and obj["c"].to(cstring) == "test".cstring
    working
  echo test()

# Test JsObject .= and .
block:
  proc test(): bool =
    let obj = newJsObject()
    var working = true
    obj.a = 11
    obj.b = "test"
    obj.c = "test".cstring
    obj.`$!&` = 42
    obj.`while` = 99
    working = working and obj.a.to(int) == 11
    working = working and obj.b.to(string) == "test"
    working = working and obj.c.to(cstring) == "test".cstring
    working = working and obj.`$!&`.to(int) == 42
    working = working and obj.`while`.to(int) == 99
    working
  echo test()

# Test JsObject .()
block:
  proc test(): bool =
    let obj = newJsObject()
    obj.`?!$` = proc(x, y, z: int, t: string): string = t & $(x + y + z)
    obj.`?!$`(1, 2, 3, "Result is: ").to(string) == "Result is: 6"
  echo test()

# Test JsObject []()
block:
  proc test(): bool =
    let obj = newJsObject()
    obj.a = proc(x, y, z: int, t: string): string = t & $(x + y + z)
    let call = obj["a"].to(proc(x, y, z: int, t: string): string)
    call(1, 2, 3, "Result is: ") == "Result is: 6"
  echo test()

# Test JsObject Iterators
block:
  proc testPairs(): bool =
    let obj = newJsObject()
    var working = true
    obj.a = 10
    obj.b = 20
    obj.c = 30
    for k, v in obj.pairs:
      case $k
      of "a":
        working = working and v.to(int) == 10
      of "b":
        working = working and v.to(int) == 20
      of "c":
        working = working and v.to(int) == 30
      else:
        return false
    working
  proc testItems(): bool =
    let obj = newJsObject()
    var working = true
    obj.a = 10
    obj.b = 20
    obj.c = 30
    for v in obj.items:
      working = working and v.to(int) in [10, 20, 30]
    working
  proc testKeys(): bool =
    let obj = newJsObject()
    var working = true
    obj.a = 10
    obj.b = 20
    obj.c = 30
    for v in obj.keys:
      working = working and $v in ["a", "b", "c"]
    working
  proc test(): bool = testPairs() and testItems() and testKeys()
  echo test()

# Test JsObject equality
block:
  proc test(): bool =
    {. emit: "var comparison = {a: 22, b: 'test'};" .}
    var comparison {. importc, nodecl .}: JsObject
    let obj = newJsObject()
    obj.a = 22
    obj.b = "test".cstring
    obj.a == comparison.a and obj.b == comparison.b
  echo test()

# Test JsObject literal
block:
  proc test(): bool =
    {. emit: "var comparison = {a: 22, b: 'test'};" .}
    var comparison {. importc, nodecl .}: JsObject
    let obj = JsObject{ a: 22, b: "test".cstring }
    obj.a == comparison.a and obj.b == comparison.b
  echo test()

# Tests for JsAssoc
# Test JsAssoc []= and []
block:
  proc test(): bool =
    let obj = newJsAssoc[int, int]()
    var working = true
    obj[1] = 11
    working = working and not compiles(obj["a"] = 11)
    working = working and not compiles(obj["a"])
    working = working and not compiles(obj[2] = "test")
    working = working and not compiles(obj[3] = "test".cstring)
    working = working and obj[1] == 11
    working
  echo test()

# Test JsAssoc .= and .
block:
  proc test(): bool =
    let obj = newJsAssoc[string, int]()
    var working = true
    obj.a = 11
    obj.`$!&` = 42
    working = working and not compiles(obj.b = "test")
    working = working and not compiles(obj.c = "test".cstring)
    working = working and obj.a == 11
    working = working and obj.`$!&` == 42
    working
  echo test()

# Test JsAssoc .()
block:
  proc test(): bool =
    let obj = newJsAssoc[string, proc(e: int): int]()
    obj.a = proc(e: int): int = e * e
    obj.a(10) == 100
  echo test()

# Test JsAssoc []()
block:
  proc test(): bool =
    let obj = newJsAssoc[string, proc(e: int): int]()
    obj.a = proc(e: int): int = e * e
    let call = obj["a"]
    call(10) == 100
  echo test()

# Test JsAssoc Iterators
block:
  proc testPairs(): bool =
    let obj = newJsAssoc[string, int]()
    var working = true
    obj.a = 10
    obj.b = 20
    obj.c = 30
    for k, v in obj.pairs:
      case $k
      of "a":
        working = working and v == 10
      of "b":
        working = working and v == 20
      of "c":
        working = working and v == 30
      else:
        return false
    working
  proc testItems(): bool =
    let obj = newJsAssoc[string, int]()
    var working = true
    obj.a = 10
    obj.b = 20
    obj.c = 30
    for v in obj.items:
      working = working and v in [10, 20, 30]
    working
  proc testKeys(): bool =
    let obj = newJsAssoc[string, int]()
    var working = true
    obj.a = 10
    obj.b = 20
    obj.c = 30
    for v in obj.keys:
      working = working and v in ["a", "b", "c"]
    working
  proc test(): bool = testPairs() and testItems() and testKeys()
  echo test()

# Test JsAssoc equality
block:
  proc test(): bool =
    {. emit: "var comparison = {a: 22, b: 55};" .}
    var comparison {. importcpp, nodecl .}: JsAssoc[string, int]
    let obj = newJsAssoc[string, int]()
    obj.a = 22
    obj.b = 55
    obj.a == comparison.a and obj.b == comparison.b
  echo test()

# Test JsAssoc literal
block:
  proc test(): bool =
    {. emit: "var comparison = {a: 22, b: 55};" .}
    var comparison {. importcpp, nodecl .}: JsAssoc[string, int]
    let obj = JsAssoc[string, int]{ a: 22, b: 55 }
    var working = true
    working = working and
      compiles(JsAssoc[int, int]{ 1: 22, 2: 55 })
    working = working and
      comparison.a == obj.a and comparison.b == obj.b
    working = working and
      not compiles(JsAssoc[string, int]{ a: "test" })
    working
  echo test()

# Tests for macros on non-JsRoot objects
# Test lit
block:
  type TestObject = object
    a: int
    b: cstring
  proc test(): bool =
    {. emit: "var comparison = {a: 1};" .}
    var comparison {. importc, nodecl .}: TestObject
    let obj = TestObject{ a: 1 }
    obj == comparison
  echo test()

# Test bindMethod
block:
  type TestObject = object
    a: int
    onWhatever: proc(e: int): int
  proc handleWhatever(that: TestObject, e: int): int =
    e + that.a
  proc test(): bool =
    let obj = TestObject(a: 9, onWhatever: bindMethod(handleWhatever))
    obj.onWhatever(1) == 10
  echo test()
