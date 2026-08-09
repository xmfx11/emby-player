import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby_models.dart';
import '../providers/server_provider.dart';

/// 通用媒体卡片：竖向布局，封面图 + 标题 + 副标题，可选播放进度。
///
/// 卡片会填满父级给定的宽度（封面以 2:3 宽高比自适应高度），
/// 因此在横向滚动列表中应在外层用 [SizedBox] 约束宽度，
/// 在网格中直接放入即可。
class MediaCard extends ConsumerWidget {
  const MediaCard({
    super.key,
    required this.item,
    this.onTap,
    this.showProgress = true,
  });

  /// 媒体项数据。
  final BaseItem item;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 是否在封面上叠加播放进度条。
  final bool showProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final client = ref.watch(embyClientProvider);
    final imageUrl = client?.imageUrl(
      item.id,
      tag: item.imageTags.primary,
      maxHeight: 400,
    );

    final percentage = item.userData?.playedPercentage;
    final hasProgress = showProgress &&
        percentage != null &&
        percentage > 0 &&
        percentage < 100;

    final subtitle = _subtitle(item);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl == null || imageUrl.isEmpty)
                    _Placeholder(theme: theme)
                  else
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (context, _) => _Placeholder(theme: theme),
                      errorWidget: (context, _, _) => _Placeholder(theme: theme),
                    ),
                  // 已观看标记
                  if (item.userData?.played == true)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  // 播放进度条（彩色：绿→黄→红）
                  if (hasProgress)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final ratio = (percentage / 100).clamp(0.0, 1.0);
                          final color = ratio < 0.5
                              ? const Color(0xFF4CAF50)
                              : ratio < 0.8
                                  ? const Color(0xFFFFC107)
                                  : const Color(0xFFFF5722);
                          return Stack(
                            children: [
                              Container(
                                height: 4,
                                color: Colors.black.withValues(alpha: 0.45),
                              ),
                              Container(
                                height: 4,
                                width: constraints.maxWidth * ratio,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(2),
                                    bottomRight: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  /// 计算副标题：剧集显示 SxxExx，否则显示年份或子项数量。
  static String _subtitle(BaseItem item) {
    if (item.type == 'Episode' &&
        item.parentIndexNumber != null &&
        item.indexNumber != null) {
      return 'S${item.parentIndexNumber}E${item.indexNumber}';
    }
    if (item.productionYear != null) {
      return item.productionYear.toString();
    }
    if (item.childCount != null && item.childCount! > 0) {
      return '${item.childCount} 项';
    }
    return '';
  }
}

/// 封面占位与加载中视图。
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
