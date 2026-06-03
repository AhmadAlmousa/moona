class MoonaError implements Exception {
  MoonaError(this.code, this.message,
      {this.status = 400, Map<String, Object?>? details})
      : details = details ?? const {};

  final String code;
  final String message;
  final int status;
  final Map<String, Object?> details;

  @override
  String toString() => 'MoonaError($code, $status): $message';
}

abstract final class ErrorCodes {
  static const unauthorized = 'unauthorized';
  static const duplicateItem = 'duplicate_item';
  static const productMissing = 'product_missing';
  static const shareSelf = 'share_self';
  static const shareTargetMissing = 'share_target_missing';
  static const sharePending = 'share_pending';
  static const viewerAlreadyReceiving = 'viewer_already_receiving';
  static const invalidImage = 'invalid_image';
  static const adminOnly = 'admin_only';
  static const invalidInput = 'invalid_input';
  static const notFound = 'not_found';
}

MoonaError unauthorized([String message = 'Authentication is required.']) =>
    MoonaError(ErrorCodes.unauthorized, message, status: 401);

MoonaError adminOnly() => MoonaError(
      ErrorCodes.adminOnly,
      'This operation requires an admin user.',
      status: 403,
    );

MoonaError notFound(String resource) => MoonaError(
      ErrorCodes.notFound,
      '$resource was not found.',
      status: 404,
      details: {'resource': resource},
    );
