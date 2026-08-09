import 'package:media_kit/media_kit.dart';

/// 音效管理器：音频延迟、均衡器预设、直通模式。
class AudioManager {
  final Player player;
  double _delay = 0; // 音频延迟（秒），正值=音频滞后
  String _eqPreset = 'off';

  AudioManager(this.player);

  double get delay => _delay;
  String get eqPreset => _eqPreset;

  /// 音频延迟调节（±100ms）。
  Future<void> adjustDelay(double ms) async {
    _delay = (_delay + ms / 1000).clamp(-5.0, 5.0);
    // TODO: mpv IPC
  }

  Future<void> resetDelay() async {
    _delay = 0;    // mpv command (media_kit limitation)
}

  /// 均衡器预设。
  static const presets = {
    'off': '关闭',
    'rock': '摇滚',
    'pop': '流行',
    'classical': '古典',
    'vocal': '人声',
    'bass_boost': '低音增强',
    'treble_boost': '高音增强',
  };

  Future<void> setEqPreset(String preset) async {
    _eqPreset = preset;
    switch (preset) {
      case 'rock':
        await _setEq([5, 4, 0, 2, 4, 5, 5, 5, 5, 4]);
        break;
      case 'pop':
        await _setEq([0, 3, 5, 4, 0, -2, -2, 0, 0, 0]);
        break;
      case 'classical':
        await _setEq([0, 0, 0, 0, -2, -2, 0, 0, 0, -4]);
        break;
      case 'vocal':
        await _setEq([-2, -3, -3, 0, 4, 3, 0, -1, -2, -3]);
        break;
      case 'bass_boost':
        await _setEq([10, 8, 4, 0, -2, -4, -6, -6, -4, -2]);
        break;
      case 'treble_boost':
        await _setEq([-4, -4, -2, 0, 2, 4, 6, 8, 8, 8]);
        break;
      default:
        await _setEq([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    }
  }

  Future<void> _setEq(List<int> bands) async {
    for (var i = 0; i < bands.length; i++) {
      // TODO: mpv IPC
    }
  }

  /// 音频直通（Passthrough）。
  Future<void> setPassthrough(bool enable) async {
    // TODO: mpv IPC
    // TODO: mpv IPC
  }
}
