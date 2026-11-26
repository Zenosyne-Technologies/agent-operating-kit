#!/usr/bin/env bash
# build-docs.sh - build (or, with --check, verify) the GitHub Pages site in docs/ from site/ (AOS-299).
exec python3 "$(dirname "$0")/lib/build_docs.py" "$@"
