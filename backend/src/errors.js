export class MoonaError extends Error {
  constructor(code, message, status = 400, details = {}) {
    super(message);
    this.name = 'MoonaError';
    this.code = code;
    this.status = status;
    this.details = details;
  }
}

export const errorCodes = Object.freeze({
  unauthorized: 'unauthorized',
  duplicateItem: 'duplicate_item',
  productMissing: 'product_missing',
  shareSelf: 'share_self',
  shareTargetMissing: 'share_target_missing',
  sharePending: 'share_pending',
  viewerAlreadyReceiving: 'viewer_already_receiving',
  invalidImage: 'invalid_image',
  adminOnly: 'admin_only',
  invalidInput: 'invalid_input',
  notFound: 'not_found',
});

export function unauthorized(message = 'Authentication is required.') {
  return new MoonaError(errorCodes.unauthorized, message, 401);
}

export function adminOnly() {
  return new MoonaError(
    errorCodes.adminOnly,
    'This operation requires an admin user.',
    403,
  );
}

export function notFound(resource) {
  return new MoonaError(
    errorCodes.notFound,
    `${resource} was not found.`,
    404,
    { resource },
  );
}
