#!/bin/sh
# Run the tests. With only the command line tools (no Xcode), SwiftPM does not
# find Testing.framework. This script passes the paths. With full Xcode, plain
# `swift test` works and this script also works.
set -e
DEV=/Library/Developer/CommandLineTools/Library/Developer
if [ -d "$DEV/Frameworks/Testing.framework" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$DEV/Frameworks" \
    -Xlinker -F -Xlinker "$DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/Frameworks" \
    -Xlinker -rpath -Xlinker "$DEV/usr/lib" "$@"
fi
exec swift test "$@"
