discard """
  file: "tpendingcheck.nim"
  exitcode: 0
  output: ""
"""

import asyncdispatch

doAssert(not hasPendingOperations())

proc test() {.async.} =
  await sleepAsync(100)

var f = test()
while not f.finished:
  doAssert(hasPendingOperations())
  poll(10)
f.read

doAssert(not hasPendingOperations())

