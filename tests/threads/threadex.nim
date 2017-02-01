discard """
  outputsub: "All rights reserved."
"""

type
  TMsgKind = enum
    mLine, mEof
  TMsg = object {.pure, final.}
    case k: TMsgKind
    of mEof: nil
    of mLine: data: string

var
  producer, consumer: Thread[void]
  chan: Channel[TMsg]
  printedLines = 0
  prodId: int
  consId: int

proc consume() {.thread.} =
  consId = getThreadId()
  while true:
    var x = recv(chan)
    if x.k == mEof: break
    echo x.data
    atomicInc(printedLines)

proc produce() {.thread.} =
  prodId = getThreadId()
  var m: TMsg
  var input = open("readme.txt")
  var line = ""
  while input.readLine(line):
    m.data = line
    chan.send(m)
  close(input)
  m.k = mEof
  chan.send(m)

open(chan)
createThread[void](consumer, consume)
createThread[void](producer, produce)
joinThread(consumer)
joinThread(producer)

close(chan)
doAssert prodId != consId
echo printedLines

