import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby_models.dart';
import '../providers/library_provider.dart';
import '../providers/server_provider.dart';
import 'detail_screen.dart';

/// 风格（Genre）筛选列表页。
///
/// 接收 [genre] 字符串，网格展示同风格下的内容。点击任一卡片进入对应详情页。
class GenreListScreen extends ConsumerWidget {
  const GenreListScreen({super.key, required this.genre});

  final String genre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(itemsByGenreProvider(genre));
    final client = ref.read(embyClientProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: true,
            title: Text(
              genre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.35),
                      theme.colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
          ),
          itemsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48),
                      const SizedBox(height: 12),
                      Text('加载失败：$error',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: () =>
                            ref.invalidate(itemsByGenreProvider(genre)),
                        icon: const Icon(Icons.refresh),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            data: (response) {
              if (response.items.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('该类型下暂无内容'),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 160,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.62,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = response.items[index];
                      return _MediaGridCard(
                        item: item,
                        imageUrl: client?.imageUrl(
                          item.id,
                          tag: item.imageTags.primary,
                          type: 'Primary',
                          maxHeight: 400,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DetailScreen(item: item),
                          ),
                        ),
                      );
                    },
                    childCount: response.items.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MediaGridCard extends StatelessWidget {
  const _MediaGridCard({
    required this.item,
    required this.imageUrl,
    required this.onTap,
  });

  final BaseItem item;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: imageUrl == null
                  ? _PosterPlaceholder(type: item.type)
                  : CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => _PosterPlaceholder(type: item.type),
                      errorWidget: (_, _, _) =>
                          _PosterPlaceholder(type: item.type),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.productionYear != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${item.productionYear}',
                      style: theme.textTheme.labelSmall?.copyWith(
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

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHigh,
      alignment: Alignment.center,
      child: Icon(
        _iconForType(type),
        size: 40,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

IconData _iconForType(String type) {
  switch (type) {
    case 'Movie':
      return Icons.movie_outlined;
    case 'Series':
      return Icons.tv_outlined;
    case 'Episode':
      return Icons.play_circle_outline;
    case 'MusicAlbum':
    case 'Audio':
      return Icons.album_outlined;
    case 'CollectionFolder':
      return Icons.folder_outlined;
    default:
      return Icons.video_library_outlined;
  }
}
