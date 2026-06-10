#!/usr/bin/env bash
#
# Deploy the moonaApi Dart function to Appwrite Cloud.
#
# WHY THIS SCRIPT EXISTS
# ----------------------
# The `dart-3.1` runtime ships Dart SDK 3.1.5, which is incompatible with the
# `test ^1.25.15` dev-dependency in pubspec.yaml (it needs SDK >= 3.2.0). The
# cloud build runs `dart pub get` and fails version solving. `test` is not needed
# at runtime, so this script deploys a bundle WITHOUT dev_dependencies. See
# DEPLOY_LOG.md (2026-06-03) for the full story.
#
# If you instead bump the runtime to dart-3.5+/3.8+ in lib/src/schema.dart, the
# real pubspec.yaml (with `test`) builds as-is and you can replace this script
# with a plain `appwrite push function`.
#
# REQUIRES
#   - appwrite CLI:  npm i -g appwrite-cli   (CLI flag names vary by version)
#   - an API key with functions.write (+ ability to update the function)
#   - APPWRITE_* values from backend/.env or the environment
#
set -euo pipefail
cd "$(dirname "$0")/.."   # -> backend/

# Load backend/.env if present (APPWRITE_ENDPOINT / _PROJECT_ID / _API_KEY).
if [ -f .env ]; then set -a; . ./.env; set +a; fi

: "${APPWRITE_ENDPOINT:?set APPWRITE_ENDPOINT}"
: "${APPWRITE_PROJECT_ID:?set APPWRITE_PROJECT_ID}"
: "${APPWRITE_API_KEY:?set APPWRITE_API_KEY (needs functions.write)}"

FUNCTION_ID="moonaApi"
RUNTIME="dart-3.1"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Runtime-only bundle: lib/ + bin/ + analysis_options.yaml + a pubspec with no
# dev_dependencies. No pubspec.lock / test/ so pub resolves fresh on SDK 3.1.5.
cp -r lib bin analysis_options.yaml "$STAGE"/
cat > "$STAGE/pubspec.yaml" <<'YAML'
name: moona_backend
description: Dart Appwrite backend for Moona.
publish_to: 'none'

environment:
  sdk: '>=3.1.0 <4.0.0'

dependencies:
  dart_appwrite: ^25.0.0
YAML

appwrite client \
  --endpoint "$APPWRITE_ENDPOINT" \
  --project-id "$APPWRITE_PROJECT_ID" \
  --key "$APPWRITE_API_KEY"

# Keep the function config aligned with FunctionSpec in lib/src/schema.dart.
appwrite functions update \
  --function-id "$FUNCTION_ID" \
  --name moonaApi \
  --runtime "$RUNTIME" \
  --entrypoint lib/main.dart \
  --commands 'dart pub get' \
  --execute users \
  --scopes databases.read tables.read rows.read rows.write \
           users.read users.write buckets.read files.read files.write \
           tokens.write messages.write

# Upload code and activate on successful build.
appwrite functions create-deployment \
  --function-id "$FUNCTION_ID" \
  --entrypoint lib/main.dart \
  --code "$STAGE" \
  --activate true

echo "Submitted. Watch the build:"
echo "  appwrite functions list-deployments --function-id $FUNCTION_ID"
