import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emby_models.dart';
import '../providers/library_provider.dart';
import '../widgets/media_card.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

/// 全部媒体浏览页：支持类型、年份、风格筛选。
class BrowseAllScreen extends ConsumerStatefulWidget {
  const BrowseAllScreen({super.key});

  @override
  ConsumerState<BrowseAllScreen> createState() => _BrowseAllScreenState();
}

class _BrowseAllScreenState extends ConsumerState<BrowseAllScreen> {
  String? _selectedType; // Movie / Series
  String? _selectedGenre;
  int? _selectedYear;
  bool _showFilters = false;

  static const _types = ['全部', '电影', '剧集'];
  static const _genres = [
    '全部', '动作', '喜剧', '剧情', '恐怖', '科幻', '爱情', '悬疑',
    '动画', '纪录', '犯罪', '奇幻', '战争', '历史'
  ];
  static final _years = List.generate(
      30, (i) => DateTime.now().year - i);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = AllItemsFilter(
      types: _selectedType == '电影'
          ? 'Movie'
          : _selectedType == '剧集'
              ? 'Series'
              : null,
      genre: _selectedGenre == '全部' ? null : _selectedGenre,
      year: _selectedYear,
    );
    final itemsAsync = ref.watch(allItemsProvider(filter));

    return Scaffold(
      appBar: AppBar(
        title: const Text('全部媒体'),
        actions: [
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_list_off : Icons.filter_list),
            tooltip: '筛选',
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showFilters) _buildFilters(theme),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(allItemsProvider(filter));
              },
              child: itemsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败：$e')),
                data: (response) {
                  if (response.items.isEmpty) {
                    return ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('暂无内容')),
                      ],
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: response.items.length,
                    itemBuilder: (context, index) {
                      final item = response.items[index];
                      return MediaCard(
                        item: item,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DetailScreen(item: item),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 类型
          _FilterRow(
            label: '类型',
            options: _types,
            selected: _selectedType ?? '全部',
            onTap: (v) {
              setState(() => _selectedType = v == '全部' ? null : v);
            },
          ),
          const SizedBox(height: 4),
          // 年份
          SizedBox(
            height: 36,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _years.length + 1,
              itemBuilder: (_, i) {
                final year = i == 0 ? null : _years[i - 1];
                final label = i == 0 ? '全部年份' : year.toString();
                final selected = i == 0 ? _selectedYear == null : _selectedYear == year;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedYear = year);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          // 风格
          _FilterRow(
            label: '风格',
            options: _genres,
            selected: _selectedGenre ?? '全部',
            onTap: (v) {
              setState(() => _selectedGenre = v == '全部' ? null : v);
            },
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.label,
    required this.options,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final List<String> options;
  final String selected;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: options.length,
        itemBuilder: (_, i) {
          final opt = options[i];
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              label: Text(opt, style: const TextStyle(fontSize: 12)),
              selected: opt == selected,
              onSelected: (_) => onTap(opt),
            ),
          );
        },
      ),
    );
  }
}
