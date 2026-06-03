import 'ids.dart';

const maxImageSizeBytes = 5 * 1024 * 1024;
const allowedImageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic'];

class AttributeSpec {
  const AttributeSpec({
    required this.type,
    required this.key,
    required this.required,
    this.size,
    this.elements = const [],
    this.array = false,
    this.min,
    this.max,
    this.defaultValue,
  });

  final String type;
  final String key;
  final bool required;
  final int? size;
  final List<String> elements;
  final bool array;
  final num? min;
  final num? max;
  final Object? defaultValue;
}

class IndexSpec {
  const IndexSpec({
    required this.key,
    required this.type,
    required this.attributes,
    this.orders = const [],
  });

  final String key;
  final String type;
  final List<String> attributes;
  final List<String> orders;
}

class TableSpec {
  const TableSpec({
    required this.id,
    required this.name,
    required this.rowSecurity,
    required this.attributes,
    required this.indexes,
  });

  final String id;
  final String name;
  final bool rowSecurity;
  final List<AttributeSpec> attributes;
  final List<IndexSpec> indexes;
}

class BucketSpec {
  const BucketSpec({
    required this.id,
    required this.name,
    required this.fileSecurity,
    required this.enabled,
    required this.maximumFileSize,
    required this.allowedFileExtensions,
  });

  final String id;
  final String name;
  final bool fileSecurity;
  final bool enabled;
  final int maximumFileSize;
  final List<String> allowedFileExtensions;
}

class FunctionSpec {
  const FunctionSpec({
    required this.functionId,
    required this.name,
    required this.runtime,
    required this.entrypoint,
    required this.commands,
    required this.timeout,
    required this.execute,
    required this.environment,
  });

  final String functionId;
  final String name;
  final String runtime;
  final String entrypoint;
  final String commands;
  final int timeout;
  final List<String> execute;
  final Map<String, String> environment;
}

class AppwriteSchema {
  const AppwriteSchema({
    required this.databaseId,
    required this.databaseName,
    required this.tables,
    required this.bucket,
    required this.functions,
  });

  final String databaseId;
  final String databaseName;
  final List<TableSpec> tables;
  final BucketSpec bucket;
  final List<FunctionSpec> functions;
}

final appwriteSchema = AppwriteSchema(
  databaseId: databaseId,
  databaseName: 'Moona',
  tables: const [
    TableSpec(
      id: CollectionIds.profiles,
      name: 'Profiles',
      rowSecurity: true,
      attributes: [
        AttributeSpec(type: 'string', key: 'userId', size: 64, required: true),
        AttributeSpec(type: 'string', key: 'phone', size: 32, required: true),
        AttributeSpec(
            type: 'string', key: 'phoneDigits', size: 32, required: true),
        AttributeSpec(
            type: 'string', key: 'displayName', size: 128, required: true),
        AttributeSpec(
            type: 'enum',
            key: 'language',
            elements: ['ar', 'en'],
            required: true),
        AttributeSpec(
            type: 'enum',
            key: 'theme',
            elements: ['light', 'dark'],
            required: true),
        AttributeSpec(
            type: 'string',
            key: 'activeReceivedOwnerId',
            size: 64,
            required: false),
        AttributeSpec(type: 'datetime', key: 'createdAt', required: true),
        AttributeSpec(type: 'datetime', key: 'updatedAt', required: true),
      ],
      indexes: [
        IndexSpec(
            key: 'phoneDigits_unique',
            type: 'unique',
            attributes: ['phoneDigits']),
        IndexSpec(
            key: 'active_received_owner',
            type: 'key',
            attributes: ['activeReceivedOwnerId']),
      ],
    ),
    TableSpec(
      id: CollectionIds.categories,
      name: 'Categories',
      rowSecurity: false,
      attributes: [
        AttributeSpec(
            type: 'string', key: 'stableId', size: 64, required: true),
        AttributeSpec(type: 'string', key: 'nameAr', size: 128, required: true),
        AttributeSpec(type: 'string', key: 'nameEn', size: 128, required: true),
        AttributeSpec(type: 'string', key: 'emoji', size: 16, required: true),
        AttributeSpec(type: 'integer', key: 'sortOrder', required: true),
        AttributeSpec(type: 'boolean', key: 'active', required: true),
        AttributeSpec(type: 'datetime', key: 'createdAt', required: true),
        AttributeSpec(type: 'datetime', key: 'updatedAt', required: true),
      ],
      indexes: [
        IndexSpec(
            key: 'stable_id_unique', type: 'unique', attributes: ['stableId']),
        IndexSpec(
            key: 'active_sort',
            type: 'key',
            attributes: ['active', 'sortOrder']),
      ],
    ),
    TableSpec(
      id: CollectionIds.units,
      name: 'Units',
      rowSecurity: false,
      attributes: [
        AttributeSpec(
            type: 'string', key: 'stableId', size: 64, required: true),
        AttributeSpec(type: 'string', key: 'nameAr', size: 128, required: true),
        AttributeSpec(type: 'string', key: 'nameEn', size: 128, required: true),
        AttributeSpec(type: 'integer', key: 'sortOrder', required: true),
        AttributeSpec(type: 'boolean', key: 'active', required: true),
        AttributeSpec(type: 'datetime', key: 'createdAt', required: true),
        AttributeSpec(type: 'datetime', key: 'updatedAt', required: true),
      ],
      indexes: [
        IndexSpec(
            key: 'stable_id_unique', type: 'unique', attributes: ['stableId']),
        IndexSpec(
            key: 'active_sort',
            type: 'key',
            attributes: ['active', 'sortOrder']),
      ],
    ),
    TableSpec(
      id: CollectionIds.products,
      name: 'Products',
      rowSecurity: false,
      attributes: [
        AttributeSpec(
            type: 'string', key: 'nameAr', size: 256, required: false),
        AttributeSpec(
            type: 'string', key: 'nameEn', size: 256, required: false),
        AttributeSpec(
            type: 'string', key: 'displayName', size: 256, required: true),
        AttributeSpec(
            type: 'string', key: 'normalizedName', size: 256, required: true),
        AttributeSpec(
            type: 'string',
            key: 'normalizedNameAr',
            size: 256,
            required: false),
        AttributeSpec(
            type: 'string',
            key: 'normalizedNameEn',
            size: 256,
            required: false),
        AttributeSpec(
            type: 'string',
            key: 'aliases',
            size: 256,
            required: false,
            array: true),
        AttributeSpec(
            type: 'string',
            key: 'normalizedAliases',
            size: 256,
            required: false,
            array: true),
        AttributeSpec(
            type: 'string',
            key: 'mergeTargetProductId',
            size: 64,
            required: false),
        AttributeSpec(type: 'boolean', key: 'active', required: true),
        AttributeSpec(type: 'datetime', key: 'createdAt', required: true),
        AttributeSpec(type: 'datetime', key: 'updatedAt', required: true),
      ],
      indexes: [
        IndexSpec(
            key: 'normalized_unique',
            type: 'unique',
            attributes: ['normalizedName']),
        IndexSpec(
            key: 'active_display',
            type: 'key',
            attributes: ['active', 'displayName']),
        IndexSpec(
            key: 'merge_target',
            type: 'key',
            attributes: ['mergeTargetProductId']),
      ],
    ),
    TableSpec(
      id: CollectionIds.listItems,
      name: 'List Items',
      rowSecurity: true,
      attributes: [
        AttributeSpec(type: 'string', key: 'ownerId', size: 64, required: true),
        AttributeSpec(
            type: 'string', key: 'productId', size: 64, required: true),
        AttributeSpec(type: 'float', key: 'count', required: true),
        AttributeSpec(type: 'string', key: 'unitId', size: 64, required: false),
        AttributeSpec(type: 'string', key: 'brand', size: 128, required: false),
        AttributeSpec(
            type: 'string', key: 'seller', size: 128, required: false),
        AttributeSpec(
            type: 'string', key: 'categoryId', size: 64, required: false),
        AttributeSpec(
            type: 'string', key: 'imageFileId', size: 128, required: false),
        AttributeSpec(type: 'boolean', key: 'important', required: true),
        AttributeSpec(type: 'string', key: 'note', size: 2048, required: false),
        AttributeSpec(
            type: 'enum',
            key: 'status',
            elements: ['active', 'trash'],
            required: true),
        AttributeSpec(type: 'datetime', key: 'trashedAt', required: false),
        AttributeSpec(
            type: 'string', key: 'trashedByUserId', size: 64, required: false),
        AttributeSpec(
            type: 'string', key: 'trashReason', size: 64, required: false),
        AttributeSpec(
            type: 'string', key: 'createdByUserId', size: 64, required: true),
        AttributeSpec(
            type: 'string', key: 'updatedByUserId', size: 64, required: true),
        AttributeSpec(type: 'datetime', key: 'createdAt', required: true),
        AttributeSpec(type: 'datetime', key: 'updatedAt', required: true),
      ],
      indexes: [
        IndexSpec(
            key: 'owner_status_product',
            type: 'key',
            attributes: ['ownerId', 'status', 'productId']),
        IndexSpec(
            key: 'owner_status_sort',
            type: 'key',
            attributes: ['ownerId', 'status', 'important', 'updatedAt']),
        IndexSpec(
            key: 'owner_trash',
            type: 'key',
            attributes: ['ownerId', 'status', 'trashedAt']),
      ],
    ),
    TableSpec(
      id: CollectionIds.shares,
      name: 'Shares',
      rowSecurity: true,
      attributes: [
        AttributeSpec(type: 'string', key: 'ownerId', size: 64, required: true),
        AttributeSpec(
            type: 'string', key: 'viewerId', size: 64, required: true),
        AttributeSpec(
            type: 'enum',
            key: 'status',
            elements: ['pending', 'accepted', 'declined', 'revoked'],
            required: true),
        AttributeSpec(type: 'datetime', key: 'requestedAt', required: true),
        AttributeSpec(type: 'datetime', key: 'respondedAt', required: false),
        AttributeSpec(type: 'datetime', key: 'revokedAt', required: false),
        AttributeSpec(type: 'datetime', key: 'createdAt', required: true),
        AttributeSpec(type: 'datetime', key: 'updatedAt', required: true),
      ],
      indexes: [
        IndexSpec(
            key: 'owner_viewer_unique',
            type: 'unique',
            attributes: ['ownerId', 'viewerId']),
        IndexSpec(
            key: 'viewer_status',
            type: 'key',
            attributes: ['viewerId', 'status']),
        IndexSpec(
            key: 'owner_status',
            type: 'key',
            attributes: ['ownerId', 'status']),
      ],
    ),
  ],
  bucket: BucketSpec(
    id: imageBucketId,
    name: 'Item images',
    fileSecurity: true,
    enabled: true,
    maximumFileSize: maxImageSizeBytes,
    allowedFileExtensions: allowedImageExtensions,
  ),
  functions: [
    FunctionSpec(
      functionId: dispatcherFunctionId,
      name: 'moonaApi',
      runtime: 'dart-3.1',
      entrypoint: 'lib/main.dart',
      commands: 'dart pub get',
      timeout: 15,
      execute: ['users'],
      environment: {
        'MOONA_DATABASE_ID': databaseId,
        'MOONA_IMAGE_BUCKET_ID': imageBucketId,
      },
    ),
  ],
);
