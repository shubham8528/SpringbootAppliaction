set -euo pipefail
if [ -z "${NVIDIA_API_KEY:-}" ]; then
  echo "::error::NVIDIA_API_KEY repository secret is not set."
  echo "Please add NVIDIA_API_KEY to your repository secrets."
  exit 1
fi
if [ ! -s "$ASSESSMENT_REPORT" ]; then
  echo "::error::Assessment report missing or empty: $ASSESSMENT_REPORT"
  exit 1
fi

SYSTEM_PROMPT=$(cat "$SYSTEM_PROMPT_FILE")

# Build the user message = assessment report + referenced files + pom.xml.
USER_PAYLOAD=$(mktemp)
{
  echo "## SECURITY_ASSESSMENT_REPORT.md"
  cat "$ASSESSMENT_REPORT"
  echo
  echo "## pom.xml"
  cat pom.xml
  echo
  echo "## Source files referenced by the assessment report"
  # Pull out repo-relative paths from the report that look like
  # 'src/main/...' and dump each.
  grep -oE '`?src/[A-Za-z0-9_./-]+\.java`?' "$ASSESSMENT_REPORT" \
    | tr -d '`' | sort -u | while IFS= read -r p; do
      if [ -f "$p" ]; then
        echo
        echo "### $p"
        cat "$p"
      fi
    done
  # Also include the application config files regardless.
  for f in $(find src/main/resources -type f \
             \( -name 'application*.yml' -o -name 'application*.yaml' \
                -o -name 'application*.properties' \) 2>/dev/null); do
    echo
    echo "### $f"
    cat "$f"
  done
} > "$USER_PAYLOAD"

echo "=================================="
echo "NVIDIA REMEDIATE: Preparing request"
echo "Assessment report size: $(wc -c < "$ASSESSMENT_REPORT") bytes"
echo "Payload size: $(wc -c < "$USER_PAYLOAD") bytes"
echo "Model: $NVIDIA_MODEL"
echo "Endpoint: $NVIDIA_BASE_URL"
echo "=================================="

REQUEST_BODY=$(jq -n \
  --arg model  "$NVIDIA_MODEL" \
  --arg sys    "$SYSTEM_PROMPT" \
  --arg user   "$(cat "$USER_PAYLOAD")" \
  --argjson temp  "$NVIDIA_TEMPERATURE" \
  --argjson mtok "$NVIDIA_MAX_TOKENS" \
  '{model: $model, temperature: $temp, max_tokens: $mtok,
    messages: [
      {role: "system", content: $sys},
      {role: "user",   content: $user}
    ]}')

echo "Request body size: $(echo "$REQUEST_BODY" | wc -c) bytes"
echo "=== NVIDIA REMEDIATE: Calling API ==="

RESPONSE_FILE=$(mktemp)
HTTP_CODE=$(curl -sS -o "$RESPONSE_FILE" -w "%{http_code}" \
  -H "Authorization: Bearer $NVIDIA_API_KEY" \
  -H "Content-Type: application/json" \
  --max-time 600 \
  -X POST "$NVIDIA_BASE_URL" \
  -d "$REQUEST_BODY" || echo "000")

echo "HTTP Response Code: $HTTP_CODE"

if [ "$HTTP_CODE" != "200" ]; then
  echo "::error::NVIDIA remediate HTTP $HTTP_CODE (expected 200)"
  echo "=== NVIDIA API Response ==="
  cat "$RESPONSE_FILE" || true
  echo "=== End Response ==="
  exit 1
fi

ASSISTANT=$(jq -r '.choices[0].message.content // ""' "$RESPONSE_FILE")
if [ -z "$ASSISTANT" ]; then
  echo "::error::NVIDIA remediate returned empty assistant content."
  echo "=== Full Response ==="
  cat "$RESPONSE_FILE" || true
  echo "=== End Response ==="
  exit 1
fi

echo "✓ Assistant response received: $(echo "$ASSISTANT" | wc -c) bytes"

# Block 1: ```nvidia-patches ... ```
PATCHES=$(printf '%s\n' "$ASSISTANT" \
  | awk '
      /^```nvidia-patches/{ if (!in_block) {in_block=1; next} else {in_block=0; exit} }
      /^```/{ if (!in_block) next }
      in_block {print}
    ')

# Block 2: ```markdown ... ``` (the second ```markdown block, or the
# first ``` ... ``` block if no info string — we just take the last
# fenced block with a markdown info string or the last generic block.)
REPORT_BODY=$(printf '%s\n' "$ASSISTANT" \
  | awk '
      /^```markdown/{ if (!in_block) {in_block=1; next} else {in_block=0; print "<<END>>"; exit} }
      /^```/{ if (in_block) {in_block=0; print "<<END>>"; next} }
      in_block {print}
    ')
# If no ```markdown``` block, take the last generic ``` block.
if [ -z "$REPORT_BODY" ]; then
  REPORT_BODY=$(printf '%s\n' "$ASSISTANT" \
    | awk '
        /^```/{ if (!in_block) {in_block=1; next} else {in_block=0; printbuf=1} }
        in_block {buf=buf $0 "\n"}
        END {if (printbuf) printf "%s", buf}
      ')
fi

# Always write the remediation report (it documents the run either way).
printf '%s\n' "$REPORT_BODY" > "$REMEDIATION_REPORT"
echo "✓ Wrote $REMEDIATION_REPORT ($(wc -c < "$REMEDIATION_REPORT") bytes)."

# Apply patches if any. Patch file format: lines, with `@@@` on its
# own line separating path from body, and `@@@` on its own line
# between records. We assume path is one line, body is everything
# between this `@@@` and the next `@@@`.
if [ -n "$PATCHES" ]; then
  APPLIED=0
  # Use awk to walk the patch block line-by-line and properly parse
  # the @@@-delimited records. State machine: path -> body -> path...
  # PATCH_QUEUE is the queue file we read back in the next step.
  # It MUST be truncated once (in BEGIN), then appended-to (>>) for
  # every write, otherwise multi-record patches lose everything but
  # the last record.
  PATCH_QUEUE=$(mktemp)

  printf '%s\n' "$PATCHES" | awk -v QFILE="$PATCH_QUEUE" '
    BEGIN {
      state = "path"
      path = ""
      body = ""
      # Truncate the queue file exactly once, so the BEGIN block
      # owns the file initial state and the rules only append.
      printf "" > QFILE
    }
    /^@@@$/ {
      if (state == "body") {
        # End of body: append the complete record.
        printf "%s\n", path      >> QFILE
        printf "%s\n", body      >> QFILE
        printf "RECORD_SEPARATOR\n" >> QFILE
        state = "path"
        path = ""
        body = ""
        next
      }
      if (state == "path") {
        # Transition to body
        state = "body"
        next
      }
    }
    state == "path" {
      # Accumulate path lines
      path = (path == "" ? $0 : path "\n" $0)
      next
    }
    state == "body" {
      # Accumulate body lines
      body = (body == "" ? $0 : body "\n" $0)
      next
    }
  '
  
  # Read patch records from PATCH_QUEUE (path, then body, then separator)
  CURRENT_PATH=""
  CURRENT_BODY=""
  while IFS= read -r line; do
    if [ "$line" = "RECORD_SEPARATOR" ]; then
      # Process the accumulated patch
      if [ -n "$CURRENT_PATH" ]; then
        # Trim whitespace
        CURRENT_PATH=$(printf '%s' "$CURRENT_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Security: refuse paths that escape the repo or are absolute.
        if printf '%s' "$CURRENT_PATH" | grep -qE '^/|/\.\./|\.\./|/\.\.$'; then
          echo "::error::refusing unsafe patch path: $CURRENT_PATH"
          exit 1
        fi
        
        # Validate path format (alphanumeric, dots, slashes, hyphens, underscores)
        if ! printf '%s' "$CURRENT_PATH" | grep -qE '^[a-zA-Z0-9._/-]+$'; then
          echo "::warning::skipping suspicious patch path: $CURRENT_PATH"
          CURRENT_PATH=""
          CURRENT_BODY=""
          continue
        fi
        
        # Write the file
        mkdir -p "$(dirname "$CURRENT_PATH")"
        printf '%s\n' "$CURRENT_BODY" > "$CURRENT_PATH"
        APPLIED=$((APPLIED+1))
        echo "✓ Patched $CURRENT_PATH"
      fi
      CURRENT_PATH=""
      CURRENT_BODY=""
    elif [ -z "$CURRENT_PATH" ]; then
      # First line after separator (or start) is the path
      CURRENT_PATH="$line"
    else
      # All subsequent lines until RECORD_SEPARATOR are body
      CURRENT_BODY="$(printf '%s\n%s' "$CURRENT_BODY" "$line")"
    fi
  done < "$PATCH_QUEUE"
  
  echo "Applied $APPLIED file(s)."
else
  echo "ℹ No patches emitted by NVIDIA (empty patch block)."
fi
