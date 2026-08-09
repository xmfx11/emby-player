import 'package:flutter/material.dart';

import '../models/emby_models.dart';
import '../services/emby_client.dart';
import '../widgets/media_card.dart';
import 'detail_screen.dart';

/// 相似推荐区域：调用 Emby Similar API。
class SimilarSection extends StatefulWidget {
  const SimilarSection({required this.itemId, required this.client});
  final String itemId;
  final EmbyClient client;
  @override
  State<SimilarSection> createState() => _SimilarSectionState();
}

class _SimilarSectionState extends State<SimilarSection> {
  List<BaseItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await widget.client.dio.get(
        'Items/${widget.itemId}/Similar',
        queryParameters: {'Limit': 20, 'UserId': widget.client.userId},
      );
      final data = response.data;
      if (data is Map && data['Items'] is List) {
        final items = (data['Items'] as List)
            .map((e) => BaseItem.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _items = items;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('相似推荐', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = _items[index];
                return SizedBox(
                  width: 130,
                  child: MediaCard(
                    item: item,
                    showProgress: false,
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
