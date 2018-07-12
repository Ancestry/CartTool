#!/bin/sh

# https://www.swiftbysundell.com/posts/building-a-command-line-tool-using-the-swift-package-manager
swift build -c release -Xswiftc -static-stdlib

