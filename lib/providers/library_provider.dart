import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby_models.dart';
import '../services/emby_client.dart';
import 'server_provider.dart';

/// 读取当前 [EmbyClient]，若未登录则抛出 [StateError]。
EmbyClient _requireClient(Ref ref) {
  final client = ref.watch(embyClientProvider);
  if (client == null) {
    throw StateError('未登录，请先连接到 Emby 服务器');
  }
  return client;
}

/// 用户的媒体库视图列表（`GET /Users/{userId}/Views`）。
final viewsProvider = FutureProvider<ItemsResponse>((ref) async {
  return _requireClient(ref).getViews();
});

/// 指定父级下的媒体项列表（`GET /Users/{userId}/Items?ParentId=...`）。
///
/// 递归查询并按类型过滤，只返回可直接播放的媒体项（电影、剧集、视频），
/// 按名称升序排列。使用 autoDispose 在离开页面时释放内存。
final itemsProvider =
    FutureProvider.autoDispose.family<ItemsResponse, String>((ref, parentId) async {
  return _requireClient(ref).getItems(
    parentId,
    recursive: true,
    types: const ['Movie', 'Series', 'Episode', 'Video'],
    sortBy: 'SortName',
    sortOrder: 'Ascending',
    limit: 200,
    fields: const ['Overview', 'PrimaryImageAspectRatio'],
  );
});

/// 媒体库内容分组（库名 + 媒体项列表）。
class LibrarySection {
  const LibrarySection({required this.title, required this.items, required this.parentId});

  final String title;
  final List<BaseItem> items;
  final String parentId;
}

/// 所有媒体库的内容列表，跳过合集类型的库。
///
/// 遍历用户的每个媒体库视图，递归查询可播放的媒体项（电影/剧集/视频），
/// 按 DateCreated 降序取前 30 条，以库名分组返回。
/// 使用 autoDispose 在离开媒体库 Tab 时释放内存。
final allLibraryItemsProvider =
    FutureProvider.autoDispose<List<LibrarySection>>((ref) async {
  final client = _requireClient(ref);
  final views = await client.getViews();

  // 过滤掉合集（boxsets）、播放列表等非内容库
  final libraryViews = views.items.where((v) {
    final ct = v.collectionType ?? '';
    if (ct == 'boxsets' || ct == 'playlists') return false;
    return true;
  }).toList();

  final sections = <LibrarySection>[];
  for (final view in libraryViews) {
    try {
      final response = await client.getItems(
        view.id,
        recursive: true,
        types: const ['Movie', 'Series', 'Video'],
        sortBy: 'DateCreated',
        sortOrder: 'Descending',
        limit: 30,
        fields: const ['Overview', 'PrimaryImageAspectRatio'],
      );
      if (response.items.isNotEmpty) {
        sections.add(LibrarySection(
          title: view.name,
          items: response.items,
          parentId: view.id,
        ));
      }
    } catch (_) {
      // 单个库加载失败时跳过，不影响其他库
    }
  }
  return sections;
});

/// 继续观看列表（`GET /Users/{userId}/Items/Resume`）。
final resumeItemsProvider = FutureProvider<ItemsResponse>((ref) async {
  return _requireClient(ref).getResumeItems(
    limit: 24,
    fields: const ['Overview', 'PrimaryImageAspectRatio'],
  );
});

/// 最新内容列表（`GET /Users/{userId}/Items/Latest`）。
///
/// family 参数为媒体类型，例如 `'Movie'`、`'Series'`、`'MusicAlbum'`。
final latestItemsProvider =
    FutureProvider.family<List<BaseItem>, String>((ref, type) async {
  return _requireClient(ref).getLatestItems(
    types: [type],
    limit: 24,
    fields: const ['Overview', 'PrimaryImageAspectRatio'],
  );
});

/// 关键词搜索结果（`GET /Users/{userId}/Items?SearchTerm=...`）。
///
/// 当 [query] 为空字符串时返回空结果，不发起请求。
final searchProvider =
    FutureProvider.autoDispose.family<ItemsResponse, String>((ref, query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const ItemsResponse();
  return _requireClient(ref).search(
    trimmed,
    limit: 60,
    fields: const ['Overview', 'PrimaryImageAspectRatio'],
  );
});

/// 单个媒体项详情（`GET /Users/{userId}/Items/{itemId}`）。
///
/// family 参数为 Item Id，返回包含扩展字段的 [BaseItem]。
/// 使用 autoDispose 确保每次进入详情页都重新拉取最新数据（含播放进度）。
final itemDetailProvider =
    FutureProvider.autoDispose.family<BaseItem, String>((ref, itemId) async {
  return _requireClient(ref).getItem(
    itemId,
    fields: const [
      'Overview',
      'Genres',
      'Tags',
      'Studios',
      'People',
      'MediaSources',
      'Backdrop',
      'MediaStreams',
    ],
  );
});

/// 媒体项的所有可用图片（`GET /Items/{itemId}/Images`）。
///
/// 用于剧照画廊，返回包含所有 Backdrop 和 Thumb 类型图片的列表。
final itemImagesProvider =
    FutureProvider.autoDispose.family<List<RemoteImageInfo>, String>((ref, itemId) async {
  return _requireClient(ref).getImages(itemId);
});

/// 剧集季列表（`GET /Users/{userId}/Items?ParentId={seriesId}`）。
///
/// family 参数为剧集（Series）Id。
final seasonsProvider =
    FutureProvider.autoDispose.family<ItemsResponse, String>((ref, seriesId) async {
  return _requireClient(ref).getItems(
    seriesId,
    sortBy: 'SortName',
    sortOrder: 'Ascending',
  );
});

/// 指定季的集列表（`GET /Users/{userId}/Items?ParentId={seasonId}`）。
///
/// family 参数为季（Season）Id。
final episodesProvider =
    FutureProvider.autoDispose.family<ItemsResponse, String>((ref, seasonId) async {
  return _requireClient(ref).getItems(
    seasonId,
    sortBy: 'SortName',
    sortOrder: 'Ascending',
    fields: const ['Overview', 'MediaSources', 'MediaStreams'],
  );
});

/// 收藏状态管理。
///
/// 调用 [toggle] 方法切换收藏状态，成功后使 [itemDetailProvider] 失效
/// 以刷新 UI。
final favoriteToggleProvider =
    AsyncNotifierProvider.autoDispose.family<FavoriteToggleNotifier, bool, String>(
  FavoriteToggleNotifier.new,
);

class FavoriteToggleNotifier
    extends AutoDisposeFamilyAsyncNotifier<bool, String> {
  @override
  bool build(String arg) {
    return false;
  }

  /// 切换收藏状态。[currentIsFavorite] 为当前是否已收藏。
  Future<void> toggle({required bool currentIsFavorite}) async {
    final client = _requireClient(ref);
    state = const AsyncLoading<bool>();
    state = await AsyncValue.guard(() async {
      if (currentIsFavorite) {
        await client.unmarkFavorite(arg);
        return false;
      } else {
        await client.markFavorite(arg);
        return true;
      }
    });
    // 刷新详情页数据。
    ref.invalidate(itemDetailProvider(arg));
  }
}

/// 按标签筛选的媒体项列表（`GET /Users/{userId}/Items?Tags=...`）。
///
/// family 参数为 [TagFilterQuery]，支持同时按标签与媒体类型过滤。
final itemsByTagProvider =
    FutureProvider.autoDispose.family<ItemsResponse, TagFilterQuery>((ref, query) async {
  if (query.tag.trim().isEmpty) return const ItemsResponse();
  return _requireClient(ref).getItemsByFilter(
    tag: query.tag,
    includeTypes: query.includeTypesList,
    limit: 100,
    fields: const ['Overview', 'PrimaryImageAspectRatio'],
  );
});

/// 标签筛选查询参数（同时作为 [itemsByTagProvider] 的 family 键）。
class TagFilterQuery {
  const TagFilterQuery(this.tag, {this.includeTypes});

  /// 标签名。
  final String tag;

  /// 可选的 `IncludeItemTypes`，多个类型以英文逗号分隔，如 `Movie,Series`。
  final String? includeTypes;

  /// 将逗号分隔的 [includeTypes] 拆分为列表。
  List<String>? get includeTypesList {
    final raw = includeTypes;
    if (raw == null || raw.trim().isEmpty) return null;
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagFilterQuery &&
          tag == other.tag &&
          includeTypes == other.includeTypes;

  @override
  int get hashCode => Object.hash(tag, includeTypes);
}

/// 按风格（Genre）筛选的媒体项列表。
final itemsByGenreProvider =
    FutureProvider.autoDispose.family<ItemsResponse, String>((ref, genre) async {
  if (genre.trim().isEmpty) return const ItemsResponse();
  return _requireClient(ref).getItemsByFilter(
    genre: genre,
    limit: 100,
    fields: const ['Overview', 'PrimaryImageAspectRatio'],
  );
});

/// 指定演员参与的影视作品列表。
final itemsByPersonProvider =
    FutureProvider.autoDispose.family<ItemsResponse, String>((ref, personId) async {
  if (personId.trim().isEmpty) return const ItemsResponse();
  return _requireClient(ref).getItemsByPerson(
    personId,
    limit: 100,
    fields: const ['Overview', 'PrimaryImageAspectRatio'],
  );
});

/// 演员详情（复用 getItem 获取 Person 类型项）。
final personDetailProvider =
    FutureProvider.autoDispose.family<BaseItem, String>((ref, personId) async {
  return _requireClient(ref).getItem(
    personId,
    fields: const ['Overview', 'People'],
  );
});
