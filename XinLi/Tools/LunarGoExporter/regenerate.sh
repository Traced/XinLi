#!/bin/bash
# Fully offline after checkout: all Go dependencies are vendored.
set -euo pipefail
cd "$(dirname "$0")"
export GOPROXY=off
export GOSUMDB=off
go run -mod=vendor . -out generated/raw
swift compress.swift generated/raw ../../Sources/LunarCore/Resources/LunarGo 1901 2099
