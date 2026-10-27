#!/usr/bin/env python3
"""Run a Lua file with real Lua 5.1 (or LuaJIT 2.1 with --jit) through lupa.

Acts like the `lua` executable for the test suite: `python tools/lua.py [--jit] file.lua [args...]`.
The script sees its arguments in the global `arg` (arg[0] = script path), like the standalone interpreter.
Install once: python -m pip install --user lupa
"""
import sys


def main(argv):
    jit = False
    if argv and argv[0] == "--jit":
        jit = True
        argv = argv[1:]
    if not argv:
        print("usage: lua.py [--jit] script.lua [args...]", file=sys.stderr)
        return 2
    if jit:
        from lupa import luajit21 as lupa_mod
    else:
        from lupa import lua51 as lupa_mod
    lua = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    script = argv[0].replace("\\", "/")
    # _LUPA tells scripts to `return` their exit code instead of calling os.exit (which would skip Python's cleanup)
    setup = lua.eval("function(n) arg = {} ; _LUPA = true ; return arg end")
    arg = setup(len(argv))
    for i, a in enumerate(argv):
        arg[i] = a
    runner = lua.eval(
        "function(path) local f, err = loadfile(path) if not f then error(err, 0) end "
        "local ok, res = pcall(f) if not ok then return false, tostring(res) end "
        "return true, res end")
    ok, res = runner(script)
    if not ok:
        print("lua: " + str(res), file=sys.stderr)
        return 1
    if isinstance(res, (int, float)) and not isinstance(res, bool):
        return int(res)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
