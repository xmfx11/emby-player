import 'package:media_kit/media_kit.dart';

/// 字幕管理器：外挂加载、同步偏移、字体样式。
class SubtitleManager {
  final Player player;

  /// 字幕延迟（秒），正值=字幕后移。
  double _delay = 0.0;

  /// 字体缩放倍率。
  double _scale = 1.0;

  /// 字体颜色（BGR hex）。
  String _color = 'FFFFFF';

  SubtitleManager(this.player);

  double get delay => _delay;
  double get scale => _scale;

  /// 加载本地字幕文件。
  Future<void> loadExternal(String path, {String? language}) async {
    await player.setSubtitleTrack(
      SubtitleTrack.uri(path, language: language ?? 'chi'),
    );
  }

  /// 字幕同步偏移（每次 ±0.1 秒）。
  Future<void> adjustDelay(double delta) async {
    _delay = (_delay + delta).clamp(-10.0, 10.0);
    // TODO: mpv IPC
  }

  /// 重置字幕延迟。
  Future<void> resetDelay() async {
    _delay = 0;    // mpv command (media_kit limitation)
}

  /// 字体大小调节。
  Future<void> setScale(double s) async {
    _scale = s.clamp(0.5, 3.0);
    // TODO: mpv IPC
  }

  /// 字体颜色。
  Future<void> setColor(String hex) async {
    _color = hex;
    // TODO: mpv IPC
  }

  /// 字幕位置偏移（屏幕百分比）。
  Future<void> setPosition(double percent) async {
    final v = (percent * 100).clamp(0, 100).round();
    // TODO: mpv IPC
  }
}
