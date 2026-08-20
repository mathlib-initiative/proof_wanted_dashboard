#!/bin/bash

# Extract all proof_wanted declarations from Mathlib

set -euo pipefail

# Find the files in mathlib's dedicated Wanted source tree that contain proof_wanted.
# This is much faster than elaborating every mathlib source file.
echo "Finding files with proof_wanted..."
mapfile -t FILES < <(
  grep -rlE --include="*.lean" '^[[:space:]]*proof_wanted([[:space:]]|$)' \
    .lake/packages/mathlib/Wanted || true
)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No files with proof_wanted found"
  : > proof_wanted.jsonl
  exit 0
fi

FILE_COUNT=${#FILES[@]}
echo "Found $FILE_COUNT files with proof_wanted declarations"

# Extract from only those files (use lower parallelism for CI stability)
PARALLEL=${PARALLEL:-4}
lake run scout \
  --plugin ProofWantedExtractor \
  --command proof_wanted_extractor \
  --jsonl \
  --parallel "$PARALLEL" \
  --read "${FILES[@]}" \
  > proof_wanted.jsonl

echo "Extracted $(wc -l < proof_wanted.jsonl) proof_wanted declarations to proof_wanted.jsonl"
