import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby_models.dart';
import '../providers/library_provider.dart';
import '../providers/server_provider.dart';
import '../services/emby_client.dart';
import 'actor_detail_screen.dart';
import 'genre_list_screen.dart';
import '../widgets/media_card.dart';
import 'player_screen.dart';
import 'similar_section.dart';
import 'tag_list_screen.dart';

/// 媒体详情页：根据传入的 [item] 拉取完整详情并展示。
///
/// 布局采用 [CustomScrollView] + [SliverAppBar] 实现沉浸式头部，
/// 内容区域包含海报、基本信息、可折叠简介、标签、演员、剧照、剧集列表，
/// 底部固定播放按钮与收藏按钮。
class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.item});

  final BaseItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(itemDetailProvider(item.id));
    final client = ref.watch(embyClientProvider);

    // 优先使用完整详情数据（含 UserData.playedPercentage）。
    final bottomItem = detailAsync.maybeWhen(
      data: (fullItem) => fullItem,
      orElse: () => item,
    );

    return Scaffold(
      body: detailAsync.when(
        loading: () => _DetailContent(
          item: item,
          client: client,
          isLoading: true,
        ),
        error: (error, _) => _DetailContent(
          item: item,
          client: client,
          error: error.toString(),
        ),
        data: (fullItem) => _DetailContent(
          item: fullItem,
          client: client,
        ),
      ),
      bottomNavigationBar: RepaintBoundary(
        child: _BottomActionsBar(item: bottomItem),
      ),
    );
  }
}

/// 跳转到播放器并返回后刷新详情数据。
///
/// 等待 600ms 确保 Emby 服务器处理完 PlaybackStopped 上报后再刷新，
/// 避免因服务器数据未及时更新导致播放记录"时好时坏"。
Future<void> _navigateToPlayer(
  BuildContext context,
  WidgetRef ref,
  String itemId,
) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => PlayerScreen(itemId: itemId)),
  );
  // 等待服务器处理停止上报后再拉取最新数据。
  await Future.delayed(const Duration(milliseconds: 600));
  ref.invalidate(itemDetailProvider(itemId));
}

// ---------------------------------------------------------------------------
// 主体内容
// ---------------------------------------------------------------------------

class _DetailContent extends ConsumerWidget {
  const _DetailContent({
    required this.item,
    required this.client,
    this.isLoading = false,
    this.error,
  });

  final BaseItem item;
  final EmbyClient? client;
  final bool isLoading;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final hasBackdrop = item.backdropImageTags.isNotEmpty;
    final backdropUrl = client?.imageUrl(
      item.id,
      tag: hasBackdrop
          ? item.backdropImageTags.first
          : item.imageTags.backdrop ?? item.imageTags.primary,
      type: hasBackdrop ? 'Backdrop' : 'Primary',
      maxHeight: 600,
      imageIndex: hasBackdrop ? 0 : null,
    );
    final posterUrl = client?.imageUrl(
      item.id,
      tag: item.imageTags.primary,
      maxHeight: 500,
    );

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          flexibleSpace: LayoutBuilder(
            builder: (context, constraints) {
              return FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (backdropUrl != null && backdropUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: backdropUrl,
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        placeholder: (context, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                      )
                    else
                      Container(color: theme.colorScheme.surfaceContainerHighest),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.3),
                            Colors.transparent,
                            theme.colorScheme.surface.withValues(alpha: 0.9),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                    // 评分徽章定位在背景图右下角
                    if (item.communityRating != null)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                      ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star,
                                  size: 16, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                item.communityRating!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),

        // 基本信息：海报 + 标题
        SliverToBoxAdapter(
          child: _InfoSection(
            item: item,
            posterUrl: posterUrl,
          ),
        ),

        // 类型（Genre）横向滚动 — 可点击跳转同类型列表
        if (item.genres.isNotEmpty)
          SliverToBoxAdapter(child: _GenresSection(genres: item.genres)),

        // 剧情简介（可展开/折叠）
        if (item.overview != null && item.overview!.isNotEmpty)
          SliverToBoxAdapter(child: _OverviewSection(overview: item.overview!)),

        // 错误提示
        if (error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '部分详情加载失败：$error',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),

        // 标签列表（横向滚动 Chip）
        if (item.tags.isNotEmpty)
          _TagsSection(tags: item.tags),

        // 演员列表（横向滚动卡片）
        if (item.people.any((p) => p.type == 'Actor'))
          SliverToBoxAdapter(
            child: _CastSection(
              people: item.people.where((p) => p.type == 'Actor').toList(),
              client: client,
            ),
          ),

        // 剧照画廊（横向滚动）—— 跳过第一张背景图（已在头部展示），加入缩略图
        if (item.backdropImageTags.length > 1 ||
            (item.imageTags.thumb != null &&
                item.imageTags.thumb!.isNotEmpty))
          SliverToBoxAdapter(
            child: _GallerySection(
              itemId: item.id,
              backdropTags: item.backdropImageTags,
              thumbTag: item.imageTags.thumb,
              client: client,
            ),
          ),

        // 剧集列表（Series 类型）
        if (item.type == 'Series')
          SliverToBoxAdapter(
            child: _SeasonsSection(seriesId: item.id),
          ),

        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 基本信息
// ---------------------------------------------------------------------------

class _InfoSection extends ConsumerWidget {
  const _InfoSection({required this.item, required this.posterUrl});

  final BaseItem item;
  final String? posterUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final isFavorite = item.userData?.isFavorite ?? false;
    final toggleState = ref.watch(favoriteToggleProvider(item.id));
    final currentFavorite = toggleState.maybeWhen(
      data: (toggled) => toggled,
      orElse: () => isFavorite,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 海报 + 收藏按钮
          Stack(
            children: [
              if (posterUrl != null && posterUrl!.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: posterUrl!,
                    height: 180,
                    width: 120,
                    fit: BoxFit.cover,
                    memCacheWidth: 300,
                    placeholder: (context, _) => Container(
                      height: 180,
                      width: 120,
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    errorWidget: (context, _, _) => Container(
                      height: 180,
                      width: 120,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                )
              else
                Container(
                  height: 180,
                  width: 120,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.movie_outlined, size: 40),
                ),
              // 收藏按钮定位在封面右下角
              Positioned(
                right: 4,
                bottom: 4,
                child: GestureDetector(
                  onTap: toggleState.isLoading
                      ? null
                      : () => ref
                          .read(favoriteToggleProvider(item.id).notifier)
                          .toggle(currentIsFavorite: currentFavorite),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                    child: toggleState.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            currentFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            size: 18,
                            color: currentFavorite
                                ? Colors.redAccent
                                : Colors.white,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 片名：根据字数自适应字号
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: item.name.length > 20
                        ? 16
                        : item.name.length > 12
                            ? 18
                            : item.name.length > 6
                                ? 20
                                : 24,
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 类型（Genre）横向滚动 — 可点击跳转
// ---------------------------------------------------------------------------

class _GenresSection extends StatelessWidget {
  const _GenresSection({required this.genres});

  final List<String> genres;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('类型', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: genres.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final genre = genres[index];
                return ActionChip(
                  label: Text(genre),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GenreListScreen(genre: genre),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 剧情简介（可展开/折叠）
// ---------------------------------------------------------------------------

class _OverviewSection extends StatefulWidget {
  const _OverviewSection({required this.overview});

  final String overview;

  @override
  State<_OverviewSection> createState() => _OverviewSectionState();
}

class _OverviewSectionState extends State<_OverviewSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('简介', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.overview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  if (widget.overview.length > 200)
                    Text(
                      '展开',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            secondChild: GestureDetector(
              onTap: () => setState(() => _expanded = false),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.overview,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  Text(
                    '收起',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 标签列表（横向滚动 Chip）
// ---------------------------------------------------------------------------

class _TagsSection extends StatelessWidget {
  const _TagsSection({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('标签', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: tags.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tag = tags[index];
                  return ActionChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TagListScreen(tag: tag),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 演员列表（横向滚动卡片）
// ---------------------------------------------------------------------------

class _CastSection extends StatelessWidget {
  const _CastSection({required this.people, required this.client});

  final List<Person> people;
  final EmbyClient? client;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('演员', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: people.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final person = people[index];
                final avatarUrl = (person.id != null &&
                        person.primaryImageTag != null &&
                        client != null)
                    ? client!.imageUrl(
                        person.id!,
                        tag: person.primaryImageTag,
                        type: 'Primary',
                        maxHeight: 200,
                      )
                    : null;

                return GestureDetector(
                  onTap: person.id != null
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ActorDetailScreen(
                                personId: person.id!,
                                personName: person.name,
                                personImageTag: person.primaryImageTag,
                              ),
                            ),
                          )
                      : null,
                  child: SizedBox(
                    width: 80,
                    child: Column(
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: avatarUrl != null && avatarUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 200,
                                    placeholder: (context, _) => Container(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                      child: Icon(
                                        Icons.person,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    errorWidget: (context, _, _) => Container(
                                      color: theme
                                          .colorScheme.surfaceContainerHighest,
                                      child: Icon(
                                        Icons.person,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : Container(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.person,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          person.name ?? '未知',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (person.role != null &&
                            person.role!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            person.role!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 剧照画廊（横向滚动，点击全屏预览）
// ---------------------------------------------------------------------------

class _GallerySection extends StatelessWidget {
  const _GallerySection({
    required this.itemId,
    required this.backdropTags,
    required this.thumbTag,
    required this.client,
  });

  final String itemId;
  final List<String> backdropTags;
  final String? thumbTag;
  final EmbyClient? client;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 构建剧照 URL 列表：
    // 1. 跳过第一张 Backdrop（index 0，已在页面头部展示）
    // 2. 其余 Backdrop 使用对应索引，确保获取到不同的图片
    // 3. 若有 Thumb 缩略图（通常是电影截图），也加入画廊
    final urls = <String>[];
    for (var i = 1; i < backdropTags.length; i++) {
      final url = client?.imageUrl(
        itemId,
        tag: backdropTags[i],
        type: 'Backdrop',
        maxHeight: 400,
        imageIndex: i,
      );
      if (url != null && url.isNotEmpty) urls.add(url);
    }
    if (thumbTag != null && thumbTag!.isNotEmpty) {
      final url = client?.imageUrl(
        itemId,
        tag: thumbTag,
        type: 'Thumb',
        maxHeight: 400,
      );
      if (url != null && url.isNotEmpty) urls.add(url);
    }

    if (urls.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('剧照', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: urls.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => _openFullscreenGallery(context, urls, index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: urls[index],
                      fit: BoxFit.cover,
                      width: 260,
                      memCacheWidth: 500,
                      placeholder: (context, _) => Container(
                        width: 260,
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
                      errorWidget: (context, _, _) => Container(
                        width: 260,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (client != null) SimilarSection(itemId: itemId, client: client!),
        ],
      ),
    );
  }

  void _openFullscreenGallery(
    BuildContext context,
    List<String> urls,
    int initialIndex,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullscreenGallery(
            urls: urls,
            initialIndex: initialIndex,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  const _FullscreenGallery({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[index],
                    fit: BoxFit.contain,
                    memCacheWidth: 800,
                    placeholder: (context, _) => const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    ),
                    errorWidget: (context, _, _) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      '${_index + 1} / ${widget.urls.length}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 剧集列表（Series 类型，显示季/集）
// ---------------------------------------------------------------------------

class _SeasonsSection extends ConsumerWidget {
  const _SeasonsSection({required this.seriesId});

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final seasonsAsync = ref.watch(seasonsProvider(seriesId));

    return seasonsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '剧集列表加载失败：$error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
      data: (response) {
        final seasons = response.items
            .where((s) => s.type == 'Season')
            .toList();
        if (seasons.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('剧集', style: theme.textTheme.titleMedium),
              ),
              const SizedBox(height: 8),
              for (final season in seasons)
                _SeasonExpansion(season: season),
            ],
          ),
        );
      },
    );
  }
}

class _SeasonExpansion extends ConsumerStatefulWidget {
  const _SeasonExpansion({required this.season});

  final BaseItem season;

  @override
  ConsumerState<_SeasonExpansion> createState() => _SeasonExpansionState();
}

class _SeasonExpansionState extends ConsumerState<_SeasonExpansion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = ref.watch(embyClientProvider);

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.season.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.season.childCount != null)
                  Text(
                    '${widget.season.childCount} 集',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          _EpisodesList(
            seasonId: widget.season.id,
            client: client,
          ),
      ],
    );
  }
}

class _EpisodesList extends ConsumerWidget {
  const _EpisodesList({required this.seasonId, required this.client});

  final String seasonId;
  final EmbyClient? client;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final episodesAsync = ref.watch(episodesProvider(seasonId));

    return episodesAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '加载失败：$error',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ),
      data: (response) {
        final episodes = response.items
            .where((e) => e.type == 'Episode')
            .toList();
        if (episodes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '暂无剧集',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return Column(
          children: episodes.map((episode) {
            final thumbUrl = client?.imageUrl(
              episode.id,
              tag: episode.imageTags.primary ?? episode.imageTags.thumb,
              type: episode.imageTags.primary != null ? 'Primary' : 'Thumb',
              maxHeight: 200,
            );
            return _EpisodeTile(
              episode: episode,
              thumbUrl: thumbUrl,
            );
          }).toList(),
        );
      },
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({required this.episode, this.thumbUrl});

  final BaseItem episode;
  final String? thumbUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlayerScreen(itemId: episode.id),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 120,
                height: 68,
                child: thumbUrl != null && thumbUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumbUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: 300,
                        placeholder: (context, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                        ),
                        errorWidget: (context, _, _) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.play_circle_outline,
                              size: 28),
                        ),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.play_circle_outline,
                            size: 28),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (episode.indexNumber != null)
                    Text(
                      '第 ${episode.indexNumber} 集',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Text(
                    episode.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (episode.overview != null &&
                      episode.overview!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      episode.overview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 底部操作栏：播放按钮 + 收藏按钮
// ---------------------------------------------------------------------------

class _BottomActionsBar extends ConsumerWidget {
  const _BottomActionsBar({required this.item});

  final BaseItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final userData = item.userData;
    final playedPercentage = userData?.playedPercentage ?? 0;
    final resumeTicks = userData?.playbackPositionTicks ?? 0;
    final runTimeTicks = item.runTimeTicks ?? 0;
    final hasResume = resumeTicks > 0;

    // Emby API 经常不返回 PlayedPercentage，需要从 ticks 计算。
    double effectiveProgress = playedPercentage;
    if (effectiveProgress <= 0 && hasResume && runTimeTicks > 0) {
      effectiveProgress = (resumeTicks / runTimeTicks) * 100;
    }
    // 限制范围
    effectiveProgress = effectiveProgress.clamp(0.0, 100.0);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: _ProgressPlayButton(
          playedPercentage: effectiveProgress,
          hasResume: hasResume,
          onPressed: () => _navigateToPlayer(context, ref, item.id),
        ),
      ),
    );
  }
}

/// 播放按钮。
///
/// - 有播放记录（playbackPositionTicks > 0）：用 LinearGradient 硬切实现
///   左侧主题色填充进度比例、右侧浅色底，文字「继续播放」+ 百分比。
/// - 无播放记录：整块主题色，文字「播放」。
class _ProgressPlayButton extends StatelessWidget {
  const _ProgressPlayButton({
    required this.playedPercentage,
    required this.hasResume,
    required this.onPressed,
  });

  final double playedPercentage;
  final bool hasResume;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final progress = (playedPercentage / 100).clamp(0.001, 0.999);
    final showProgress = hasResume && playedPercentage > 0;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          hasResume ? Icons.play_circle_fill : Icons.play_arrow,
          color: Colors.white,
          size: 22,
        ),
        const SizedBox(width: 8),
        Text(
          hasResume ? '继续播放' : '播放',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (showProgress) ...[
          const SizedBox(width: 8),
          Text(
            '${playedPercentage.toStringAsFixed(0)}%',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ],
    );

    if (!showProgress) {
      // 无进度：纯色按钮
      return GestureDetector(
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(24),
          ),
          alignment: Alignment.center,
          child: content,
        ),
      );
    }

    // 有进度：用 LinearGradient 硬切实现左实右淡的进度填充
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              primary,
              primary,
              primary.withValues(alpha: 0.2),
              primary.withValues(alpha: 0.2),
            ],
            stops: [
              0.0,
              progress,
              progress,
              1.0,
            ],
          ),
        ),
        alignment: Alignment.center,
        child: content,
      ),
    );
  }
}
