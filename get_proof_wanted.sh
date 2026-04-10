#!/bin/bash

# Extract all proof_wanted declarations from Mathlib

set -euo pipefail

# First, find all Mathlib source files that actually contain proof_wanted
# (much faster than elaborating all 7000+ files, and avoids MathlibTest files)
echo "Finding files with proof_wanted..."
FILES=$(grep -rl "^proof_wanted" .lake/packages/mathlib/Mathlib --include="*.lean" | tr '\n' ' ')

if [ -z "$FILES" ]; then
  echo "No files with proof_wanted found"
  exit 0
fi

FILE_COUNT=$(echo $FILES | wc -w)
echo "Found $FILE_COUNT files with proof_wanted declarations"

# Extract from only those files (use lower parallelism for CI stability)
PARALLEL=${PARALLEL:-4}
lake run scout \
  --plugin ProofWantedExtractor \
  --command proof_wanted_extractor \
  --jsonl \
  --parallel $PARALLEL \
  --read $FILES \
  > proof_wanted.jsonl

echo "Extracted $(wc -l < proof_wanted.jsonl) proof_wanted declarations to proof_wanted.jsonl"
