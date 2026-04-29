#!/bin/bash
set -e
cd "$(dirname "$0")"
swiftc main.swift -o TensiqSync -framework Cocoa
echo "Built: ./TensiqSync"
echo "Run:   ./TensiqSync"
