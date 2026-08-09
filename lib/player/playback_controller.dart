import 'dart:async';
import 'package:media_kit/media_kit.dart';

/// 播放控制增强：播放队列、预加载、速度无极调节。
class PlaybackController {
  final Player player;

  /// 播放队列（剧集 ID 列表）。
  final List<String> _queue = [];
  int _currentIndex = -1;

  /// 预加载器。
  Player? _preloadPlayer;

  /// 缓冲参数。
  static const defaultCache = 150 * 1024; // 150MB
  static const defaultDemuxer = 50 * 1024 * 1024; // 50MB

  PlaybackController(this.player);

  List<String> get queue => List.unmodifiable(_queue);

  /// 设置播放队列。
  void setQueue(List<String> itemIds, int startIndex) {
    _queue.clear();
    _queue.addAll(itemIds);
    _currentIndex = startIndex;
  }

  /// 跳转到下一集。
  String? nextEpisode() {
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      return _queue[_currentIndex];
    }
    return null;
  }

  /// 上一集。
  String? previousEpisode() {
    if (_currentIndex > 0) {
      _currentIndex--;
      return _queue[_currentIndex];
    }
    return null;
  }

  /// 预加载下一集（后台静默打开，不播放）。
  Future<void> preloadNext(String url, Map<String, String> headers) async {
    _preloadPlayer?.dispose();
    _preloadPlayer = Player();
    await _preloadPlayer!.open(
      Media(url, httpHeaders: headers),
    );
    await _preloadPlayer!.pause();
  }

  /// 设置网络缓冲大小。
  Future<void> setCacheSize(int mb) async {
    final bytes = (mb * 1024 * 1024).clamp(32 * 1024 * 1024, 1024 * 1024 * 1024);    // mpv command (media_kit limitation)
// TODO: mpv IPC
    // mpv command (media_kit limitation)
}

  /// HDR → SDR 色调映射。
  Future<void> setHdrToSdr(bool enable) async {
    if (enable) {    // mpv command (media_kit limitation)
    // mpv command (media_kit limitation)
    // mpv command (media_kit limitation)
} else {    // mpv command (media_kit limitation)
    // mpv command (media_kit limitation)
}
  }

  /// 获取当前进度百分比（用于预加载触发）。
  Future<double> getProgressPercent() async {
    final pos = await Duration.zero /* stream */;
    final dur = await Duration.zero /* stream */;
    if (dur.inMilliseconds == 0) return 0;
    return pos.inMilliseconds / dur.inMilliseconds;
  }

  void dispose() {
    _preloadPlayer?.dispose();
  }
}
