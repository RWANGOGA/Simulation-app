#!/usr/bin/env python3
"""
Container entrypoint.

Crane Cloud (and most other container hosts) inject $PORT to tell the
process which port to listen on. Our CMD is a fixed uvicorn invocation
with `--port 8000`; this script replaces that port with $PORT (default
8000) and execs uvicorn.

Implemented in Python instead of shell so the argv survives intact:
`set -- $(echo "$@" | sed ...)` mangles the args if any contain spaces
or shell metacharacters, which `exec` then re-parses incorrectly.
"""
import os
import sys


def main() -> int:
    port = os.environ.get("PORT", "8000")
    args = sys.argv[1:]
    if not args:
        print("entrypoint: no command provided", file=sys.stderr)
        return 2

    # Replace any existing --port N with the platform-provided port, or
    # append one if it's missing.
    new_args = []
    replaced = False
    i = 0
    while i < len(args):
        if args[i] == "--port" and i + 1 < len(args):
            new_args.extend([args[i], port])
            replaced = True
            i += 2
            continue
        if args[i].startswith("--port="):
            new_args.append(f"--port={port}")
            replaced = True
            i += 1
            continue
        new_args.append(args[i])
        i += 1
    if not replaced:
        new_args.extend(["--port", port])

    print(f"entrypoint: launching: {' '.join(new_args)}", flush=True)
    os.execvp(new_args[0], new_args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
