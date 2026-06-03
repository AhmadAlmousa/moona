# Moona Appwrite Backend

This package contains the Dart Appwrite backend scaffold for Moona:

- Appwrite table/storage/function schema metadata.
- Provisioning script for database, tables, indexes, bucket, function, and seed
  catalog data.
- Shared domain rules for phone/product normalization, duplicate detection,
  sharing, trash metadata, and product merge suggestions.
- A single Dart Appwrite Function dispatcher (`moonaApi`) used by all
  operations.
- Local Dart tests for backend behavior that do not require Appwrite.

## Setup

```bash
cd backend
dart pub get
```

The Flutter app and backend examples default to the Appwrite Cloud MVP project:

- `APPWRITE_ENDPOINT=https://nyc.cloud.appwrite.io/v1`
- `APPWRITE_PROJECT_ID=6a20305f000a1a0251d2`

The database, tables, storage bucket, function, and seed catalogs are
provisioned in that remote project. Only create a local `.env` from
`.env.example` when rerunning `dart run bin/provision.dart` from your shell;
that command needs an `APPWRITE_API_KEY` with project-management scopes.

Registered client platforms:

- Android application ID: `sa.almou.moona`
- iOS bundle ID: `sa.almou.moona`
- Web hostnames: `localhost`, `127.0.0.1`, `dev.almou.sa`

## Provision

```bash
dart run bin/provision.dart
```

The script is idempotent for create conflicts and seeds the default categories,
units, and universal products from the mockup/spec.

## Function

The deployed function ID is `moonaApi`, and it points at `lib/main.dart`. The
dispatcher resolves the operation from the request `action` field.
`MOONA_FUNCTION_NAME` is still supported for local single-operation tests, but
it is not set in the free-plan cloud deployment.

Authenticated Appwrite invocations must include the function headers Appwrite
provides automatically:

- `x-appwrite-user-id`
- `x-appwrite-user-jwt`
- `x-appwrite-key` or backend env `APPWRITE_API_KEY`

## Tests

```bash
dart test
```
