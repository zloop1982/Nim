discard """
  output: '''foo
js 3.14
7
1'''
"""

# This file tests the JavaScript generator

#  #335
proc foo() =
  var bar = "foo"
  proc baz() =
    echo bar
  baz()
foo()

# #376
when not defined(JS):
  proc foo(val: float): string = "no js " & $val
else:
  proc foo(val: float): string = "js " & $val

echo foo(3.14)

# #2495
type C = concept x

proc test(x: C, T: typedesc): T =
  cast[T](x)

echo 7.test(int8)

# #4222
const someConst = [ "1"]

proc procThatRefersToConst() # Forward decl
procThatRefersToConst() # Call bar before it is defined

proc procThatRefersToConst() =
  var i = 0 # Use a var index, otherwise nim will constfold foo[0]
  echo someConst[i] # JS exception here: foo is still not initialized (undefined)
