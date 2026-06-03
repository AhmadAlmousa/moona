import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dart_appwrite/dart_appwrite.dart';

import 'appwrite_repository.dart';
import 'errors.dart';
import 'normalization.dart';
import 'operations.dart';

Future<dynamic> handleMoonaFunction(dynamic context) async {
  final req = context.req;
  final res = context.res;

  try {
    final payload = parsePayload(req);
    final functionName = resolveFunctionName(req, payload);
    final operation = operations[functionName];

    if (operation == null) {
      return jsonResponse(
        res,
        {
          'ok': false,
          'error': {
            'code': ErrorCodes.invalidInput,
            'message':
                'Unknown Moona function: ${functionName ?? '(missing)'}.',
          },
        },
        status: 400,
      );
    }

    final headers = readHeaders(req);
    final apiKey = Platform.environment['APPWRITE_API_KEY'] ??
        Platform.environment['APPWRITE_FUNCTION_API_KEY'] ??
        headers['x-appwrite-key'] ??
        '';
    final jwt = headers['x-appwrite-user-jwt'] ?? '';
    final actorId = headers['x-appwrite-user-id'] ?? '';
    final repo = AppwriteRepository(
      adminClient: appwriteAdminClient(apiKey),
      userClient: jwt.isEmpty ? null : appwriteJwtClient(jwt),
    );

    final data =
        await operation(repo: repo, actorId: actorId, payload: payload);
    return jsonResponse(res, {'ok': true, 'data': data});
  } catch (caught) {
    final mapped = mapError(caught);
    try {
      context.error('${mapped['code']}: ${mapped['message']}');
    } catch (_) {
      // Logging is best effort in local tests.
    }
    return jsonResponse(res, {'ok': false, 'error': mapped},
        status: mapped['status'] as int);
  }
}

JsonMap parsePayload(dynamic req) {
  final bodyJson = readRequestField(req, 'bodyJson');
  if (bodyJson is Map) return bodyJson.cast<String, dynamic>();

  final body =
      readRequestField(req, 'bodyText') ?? readRequestField(req, 'body');
  if (body == null || body == '') return {};
  if (body is Map) return body.cast<String, dynamic>();

  try {
    final decoded = jsonDecode(body.toString());
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return {};
  } catch (_) {
    throw MoonaError(
      ErrorCodes.invalidInput,
      'Request body must be valid JSON.',
    );
  }
}

String? resolveFunctionName(dynamic req, JsonMap payload) {
  final forced = Platform.environment['MOONA_FUNCTION_NAME'];
  if (forced != null && forced.isNotEmpty) return forced;
  final action = payload['action'];
  if (action != null && action.toString().isNotEmpty) return action.toString();

  final path =
      (readRequestField(req, 'path') ?? readRequestField(req, 'url') ?? '')
          .toString();
  final parts = path.split('/').where((part) => part.isNotEmpty).toList();
  return parts.isEmpty ? null : parts.last;
}

Map<String, Object?> mapError(Object error) {
  if (error is MoonaError) {
    return {
      'code': error.code,
      'message': error.message,
      'status': error.status,
      'details': error.details,
    };
  }

  if (error is AppwriteException) {
    final status = error.code == 401
        ? 401
        : error.code == 404
            ? 404
            : 500;
    return {
      'code': status == 401 ? ErrorCodes.unauthorized : ErrorCodes.invalidInput,
      'message': error.message ?? 'Unexpected backend error.',
      'status': status,
      'details': {},
    };
  }

  return {
    'code': ErrorCodes.invalidInput,
    'message': error.toString(),
    'status': 500,
    'details': {},
  };
}

dynamic jsonResponse(dynamic res, JsonMap body, {int status = 200}) {
  if (status == 200) return res.json(body);
  return res.text(
    jsonEncode(body),
    status,
    {'content-type': 'application/json'},
  );
}

Map<String, String> readHeaders(dynamic req) {
  final headers = readRequestField(req, 'headers');
  if (headers is Map) {
    return headers.map((key, value) =>
        MapEntry(key.toString().toLowerCase(), value.toString()));
  }
  return const {};
}

dynamic readRequestField(dynamic req, String field) {
  try {
    return switch (field) {
      'bodyJson' => req.bodyJson,
      'bodyText' => req.bodyText,
      'body' => req.body,
      'headers' => req.headers,
      'path' => req.path,
      'url' => req.url,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}
