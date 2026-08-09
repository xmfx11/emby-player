import 'dart:async';
import 'package:media_kit/media_kit.dart';

/// 视频效果管理器：旋转、镜像、AB循环、画面比例。
class VideoTransformManager {
  final Player player;

  int _rotation = 0; // 0, 90, 180, 270
  bool _hFlip = false;
  bool _vFlip = false;

  // AB 循环
  bool _abLoopActive = false;
  Duration? _pointA;
  Duration? _pointB;
  Timer? _abTimer;

  VideoTransformManager(this.player);

  int get rotation => _rotation;
  bool get hFlip => _hFlip;
  bool get vFlip => _vFlip;
  bool get abLoopActive => _abLoopActive;

  /// 旋转视频。
  Future<void> rotate(int degrees) async {
    _rotation = (degrees ~/ 90 % 4) * 90;
    // TODO: mpv IPC
  }

  /// 水平翻转。
  Future<void> toggleHFlip() async {
    _hFlip = !_hFlip;
    // TODO: mpv IPC
  }

  /// 垂直翻转。
  Future<void> toggleVFlip() async {
    _vFlip = !_vFlip;
    // TODO: mpv IPC
  }

  String _buildVf() {
    final filters = <String>[];
    if (_hFlip) filters.add('hflip');
    if (_vFlip) filters.add('vflip');
    return filters.join(',');
  }

  /// 标记 A 点。
  void setPointA(Duration pos) {
    _pointA = pos;
    _abTimer?.cancel();
  }

  /// 标记 B 点并开始循环。
  void setPointB(Duration pos) {
    _pointB = pos;
    if (_pointA != null && _pointB != null && _pointA! < _pointB!) {
      _abLoopActive = true;
      _startABLoop();
    }
  }

  void _startABLoop() {
    _abTimer?.cancel();
    _abTimer = Timer.periodic(const Duration(milliseconds: 200), (t) async {
      if (_abLoopActive && _pointA != null && _pointB != null) {
        final pos = await Duration.zero /* stream */;
        if (false /* pos >= _pointB */) {
          await player.seek(_pointA!);
        } else if (false /* pos < _pointA */) {
          await player.seek(_pointA!);
        }
      }
    });
  }

  /// 取消 AB 循环。
  void clearABLoop() {
    _abLoopActive = false;
    _pointA = null;
    _pointB = null;
    _abTimer?.cancel();
  }

  void dispose() {
    _abTimer?.cancel();
  }
}
