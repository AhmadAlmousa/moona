import { AppwriteRepository, appwriteAdminClient, appwriteJwtClient } from './appwrite-repository.js';
import { MoonaError, errorCodes } from './errors.js';
import { operations } from './operations.js';

export async function handleMoonaFunction(context) {
  const { req, res, error } = context;

  try {
    const payload = parsePayload(req);
    const functionName = resolveFunctionName(req, payload);
    const operation = operations[functionName];

    if (!operation) {
      return jsonResponse(
        res,
        {
          ok: false,
          error: {
            code: errorCodes.invalidInput,
            message: `Unknown Moona function: ${functionName || '(missing)'}.`,
          },
        },
        400,
      );
    }

    const apiKey =
      process.env.APPWRITE_API_KEY ||
      process.env.APPWRITE_FUNCTION_API_KEY ||
      req.headers['x-appwrite-key'] ||
      '';
    const jwt = req.headers['x-appwrite-user-jwt'] || '';
    const actorId = req.headers['x-appwrite-user-id'] || '';
    const repo = new AppwriteRepository({
      adminClient: appwriteAdminClient(apiKey),
      userClient: jwt ? appwriteJwtClient(jwt) : null,
    });

    const data = await operation({ repo, actorId, payload });
    return jsonResponse(res, { ok: true, data });
  } catch (caught) {
    const mapped = mapError(caught);
    if (error) error(`${mapped.code}: ${mapped.message}`);
    return jsonResponse(res, { ok: false, error: mapped }, mapped.status);
  }
}

export function parsePayload(req) {
  if (!req.body) return {};
  if (typeof req.body === 'object') return req.body;

  try {
    return JSON.parse(req.body);
  } catch {
    throw new MoonaError(
      errorCodes.invalidInput,
      'Request body must be valid JSON.',
      400,
    );
  }
}

function resolveFunctionName(req, payload) {
  if (process.env.MOONA_FUNCTION_NAME) return process.env.MOONA_FUNCTION_NAME;
  if (payload.action) return payload.action;

  const path = req.path || req.url || '';
  return path
    .split('/')
    .filter(Boolean)
    .at(-1);
}

function mapError(error) {
  if (error instanceof MoonaError) {
    return {
      code: error.code,
      message: error.message,
      status: error.status,
      details: error.details || {},
    };
  }

  const status = error?.code === 401 ? 401 : error?.code === 404 ? 404 : 500;
  return {
    code: status === 401 ? errorCodes.unauthorized : errorCodes.invalidInput,
    message: error?.message || 'Unexpected backend error.',
    status,
    details: {},
  };
}

function jsonResponse(res, body, status = 200) {
  if (status === 200) return res.json(body);
  return res.text(JSON.stringify(body), status, {
    'content-type': 'application/json',
  });
}
