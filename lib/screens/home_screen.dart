import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby_models.dart';
import '../providers/library_provider.dart';
import '../providers/server_provider.dart';
import '../widgets/media_card.dart';
import '../services/ota_service.dart';
import 'browse_screen.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

/// 主页面：底部三 Tab 导航（首页 / 媒体库 / 设置）。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 启动后延迟检查更新
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) OtaService.checkOnStartup(context);
    });
  }

  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _HomeTab(),
          _LibrariesTab(),
          _SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.video_library_outlined),
            selectedIcon: Icon(Icons.video_library),
            label: '媒体库',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 首页 Tab
// ---------------------------------------------------------------------------

class _HomeTab extends ConsumerWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resume = ref.watch(resumeItemsProvider);
    final latestMovies = ref.watch(latestItemsProvider('Movie'));
    final latestSeries = ref.watch(latestItemsProvider('Series'));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emby Player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        addAutomaticKeepAlives: false,
        children: [
          // 轮播推荐 banner
          RepaintBoundary(child: _BannerCarousel(async: latestMovies)),
          RepaintBoundary(
            child: _MediaSection<ItemsResponse>(
              title: '继续观看',
              async: resume,
              extract: (ItemsResponse d) => d.items,
            ),
          ),
          RepaintBoundary(
            child: _MediaSection<List<BaseItem>>(
              title: '最新电影',
              async: latestMovies,
              extract: (List<BaseItem> d) => d,
            ),
          ),
          RepaintBoundary(
            child: _MediaSection<List<BaseItem>>(
              title: '最新剧集',
              async: latestSeries,
              extract: (List<BaseItem> d) => d,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 轮播推荐 Banner
// ---------------------------------------------------------------------------

/// 首页顶部轮播推荐：展示最新电影背景图，5 秒自动翻页。
class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel({required this.async});

  final AsyncValue<List<BaseItem>> async;

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  final PageController _pageController = PageController();
  Timer? _autoTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients) return;
      widget.async.maybeWhen(
        data: (items) {
          if (items.isEmpty) return;
          final next = (_currentPage + 1) % items.length;
          _pageController.animateToPage(
            next,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        },
        orElse: () {},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.async.when(
      loading: () => const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox(height: 4),
      data: (items) {
        if (items.isEmpty) return const SizedBox(height: 4);
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            height: 200,
            child: PageView.builder(
              controller: _pageController,
              itemCount: items.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (context, index) {
                final item = items[index];
                return _BannerCard(item: item);
              },
            ),
          ),
        );
      },
    );
  }
}

/// 单张轮播卡片：背景图 + 渐变遮罩 + 标题信息。
class _BannerCard extends ConsumerWidget {
  const _BannerCard({required this.item});

  final BaseItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final client = ref.watch(embyClientProvider);

    final hasBackdrop = item.backdropImageTags.isNotEmpty;
    final imageUrl = client?.imageUrl(
      item.id,
      tag: hasBackdrop
          ? item.backdropImageTags.first
          : item.imageTags.primary,
      type: hasBackdrop ? 'Backdrop' : 'Primary',
      maxHeight: 400,
      imageIndex: hasBackdrop ? 0 : null,
    );

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DetailScreen(item: item),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerHighest,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 600,
                  fadeInDuration: const Duration(milliseconds: 200),
                  placeholder: (context, _) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, _, _) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.movie, size: 48, color: Colors.white24),
                  ),
                )
              else
                Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.movie, size: 48, color: Colors.white24),
                ),
              // 渐变遮罩
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.75),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
              // 标题信息
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (item.productionYear != null)
                          Text(
                            item.productionYear.toString(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        if (item.productionYear != null &&
                            item.officialRating != null)
                          Text(
                            ' · ',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                        if (item.officialRating != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              item.officialRating!,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                            ),
                          ),
                        if (item.communityRating != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.star, size: 14, color: Colors.amber.shade300),
                          const SizedBox(width: 2),
                          Text(
                            item.communityRating!.toStringAsFixed(1),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首页的一个横向滚动媒体区块（纯展示组件，接收已查询的 [AsyncValue]）。
class _MediaSection<T> extends StatelessWidget {
  const _MediaSection({
    required this.title,
    required this.async,
    required this.extract,
  });

  final String title;
  final AsyncValue<T> async;
  final List<BaseItem> Function(T data) extract;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Widget content = async.when(
      loading: () => const SizedBox(
        height: 210,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => SizedBox(
        height: 210,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '加载失败',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ),
      ),
      data: (data) {
        final items = extract(data);
        if (items.isEmpty) return const SizedBox(height: 4);
        return SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            addAutomaticKeepAlives: false,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return SizedBox(
                width: 124,
                child: MediaCard(
                  item: item,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(item: item),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 媒体库 Tab
// ---------------------------------------------------------------------------

class _LibrariesTab extends ConsumerWidget {
  const _LibrariesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(allLibraryItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(allLibraryItemsProvider);
          await ref.read(allLibraryItemsProvider.future);
        },
        child: sections.when(
          loading: () => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(height: 120),
              Center(child: CircularProgressIndicator()),
            ],
          ),
          error: (error, _) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const SizedBox(height: 80),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('加载失败：$error'),
                ),
              ),
            ],
          ),
          data: (sectionList) {
            if (sectionList.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('暂无内容')),
                ],
              );
            }
            return ListView(
              addAutomaticKeepAlives: false,
              children: [
                for (final section in sectionList)
                  RepaintBoundary(child: _LibrarySectionRow(section: section)),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 媒体库分区：标题 + 横向滚动卡片列表，与首页布局一致。
class _LibrarySectionRow extends StatelessWidget {
  const _LibrarySectionRow({required this.section});

  final LibrarySection section;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：库名 + 查看全部
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BrowseScreen(
                        parentId: section.parentId,
                        title: section.title,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '查看全部',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              addAutomaticKeepAlives: false,
              itemCount: section.items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = section.items[index];
                return SizedBox(
                  width: 124,
                  child: MediaCard(
                    item: item,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(item: item),
                      ),
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
// 设置 Tab
// ---------------------------------------------------------------------------

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(activeServerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          if (server != null) ...[
            _sectionHeader(theme, '当前服务器'),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('名称'),
              subtitle: Text(server.name),
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('地址'),
              subtitle: Text(server.url),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('用户'),
              subtitle: Text(server.username),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('用户 ID'),
              subtitle: Text(server.userId),
            ),
          ] else
            const ListTile(title: Text('未登录')),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('登出'),
            onTap: () => _confirmLogout(context, ref),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('检查更新'),
            subtitle: const Text('当前版本 1.0.0'),
            onTap: () => OtaService.checkManual(context),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登出'),
        content: const Text('确定要登出当前服务器吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('登出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(activeServerProvider.notifier).logout();
    }
  }
}
