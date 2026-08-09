import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:uuid/uuid.dart';

import '../models/emby_models.dart';
import '../providers/server_provider.dart';
import '../services/emby_client.dart';

/// 视频播放器页面。
///
/// 基于 `media_kit`（Player + VideoController）实现，负责：
/// * 通过 [EmbyClient.getPlaybackInfo] 协商播放地址（DirectStream / HLS / 兜底 / STRM）。
/// * 自定义底部控制栏（播放暂停、进度条、时间、倍速、音轨、字幕）。
/// * 手势操作：左右滑动快进快退、左侧上下滑动调亮度、右侧上下滑动调音量。
/// * 控制栏 3 秒无操作自动隐藏。
/// * 播放进度上报（开始 / 每 3 秒 / 停止）与续播。
/// * 错误处理与重试、全屏支持。
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.itemId,
    this.mediaSourceId,
  });

  final String itemId;

  /// 可选：指定使用的媒体源 Id；为空时使用第一个。
  final String? mediaSourceId;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

/// 1 毫秒对应的 Emby Ticks 数（1 秒 = 10,000,000 Ticks）。
const int _ticksPerMs = 10000;

/// 可选倍速列表。
const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// 垂直手势模式。
enum _VerticalMode { brightness, volume }

/// 屏幕比例选项。
const List<BoxFit> _boxFitOptions = [
  BoxFit.contain,
  BoxFit.fill,
  BoxFit.cover,
  BoxFit.fitWidth,
  BoxFit.fitHeight,
];

const List<String> _boxFitLabels = ['适应', '拉伸', '裁剪', '填宽', '填高'];

/// 系统音量 MethodChannel。
const _volumeChannel = MethodChannel('com.emby.emby_player/volume');

/// 播放地址解析结果。
class _ResolvedPlayback {
  const _ResolvedPlayback(this.url, this.method);
  final String url;

  /// `DirectStream` / `Transcode` / `DirectPlay`。
  final String method;
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player player;
  late final VideoController controller;

  // --- 上下文 ---
  EmbyClient? _client;
  BaseItem? _item;
  List<MediaStream> _audioStreams = const [];
  List<MediaStream> _subtitleStreams = const [];

  // --- 加载 / 错误状态 ---
  bool _loading = true;
  bool _initialized = false;
  String? _errorMessage;

  // --- 播放状态 ---
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _buffering = false;
  double _speed = 1.0;
  double _volume = 100;
  bool _completed = false;
  int? _selectedAudioIndex;
  int? _selectedSubtitleIndex; // null 表示关闭字幕

  // --- 缓冲速度追踪 ---
  int _lastBufferedBytes = 0;
  DateTime _lastBufferedTime = DateTime.now();
  String _bufferSpeedText = '';

  // --- 控制栏可见性 ---
  bool _controlsVisible = true;
  bool _isImmersive = true;
  Timer? _hideTimer;

  // --- 屏幕方向 ---
  bool _isPortrait = false;

  // --- 屏幕锁 ---
  bool _isLocked = false;
  bool _showLockUnlock = false;

  // --- 屏幕比例 ---
  int _boxFitIndex = 0;

  // --- 系统音量 ---
  double _systemMaxVolume = 15.0;

  // --- 手势状态 ---
  bool _isSeeking = false;
  Duration _seekStartPos = Duration.zero;
  double _seekStartDx = 0;
  Duration? _seekPreview;

  bool _isVerticalDragging = false;
  _VerticalMode _verticalMode = _VerticalMode.volume;
  double _verticalStartDy = 0;
  double _verticalStartVal = 0;

  // --- 屏幕亮度（系统级，0.0~1.0）---
  double _screenBrightness = 0.5;
  double _initialBrightness = 0.5;

  // --- 播放上报 ---
  Timer? _progressTimer;
  String? _playSessionId;
  String? _currentMediaSourceId;
  String _playMethod = 'DirectStream';
  Duration _resumePosition = Duration.zero;
  bool _reportedStart = false;

  // --- UI 节流 ---
  Duration _lastUiPosition = Duration.zero;
  Timer? _uiThrottleTimer;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    player = Player();
    controller = VideoController(player);
    _enterLandscape();
    _initSystemVolume();
    _initScreenBrightness();
    _initPlayback();
  }

  Future<void> _initScreenBrightness() async {
    try {
      final brightness = await _volumeChannel.invokeMethod<double>('getScreenBrightness');
      if (brightness != null) {
        _screenBrightness = brightness.clamp(0.0, 1.0);
        _initialBrightness = _screenBrightness;
      }
    } catch (_) {}
  }

  Future<void> _initSystemVolume() async {
    try {
      final max = await _volumeChannel.invokeMethod<double>('getMaxVolume');
      if (max != null && max > 0) _systemMaxVolume = max;
      final vol = await _volumeChannel.invokeMethod<double>('getVolume');
      if (vol != null) {
        _volume = (vol / _systemMaxVolume) * 100;
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 初始化与播放地址解析
  // ---------------------------------------------------------------------------

  Future<void> _initPlayback() async {
    final client = ref.read(embyClientProvider);
    _client = client;
    if (client == null) {
      setState(() {
        _loading = false;
        _errorMessage = '未连接到 Emby 服务器，请先登录。';
      });
      return;
    }

    try {
      // 并行获取元数据和播放信息（加快起播速度）
      BaseItem? item;
      PlaybackInfo? info;
      
      try {
        item = await client.getItem(widget.itemId,
            fields: const ['MediaSources', 'Overview']);
        _item = item;
      } catch (_) {}
      
      try {
        info = await client.getPlaybackInfo(widget.itemId);
      } catch (_) {}

      List<MediaSource> mediaSources;
      
      if (info != null) {
        _playSessionId = info.playSessionId;
        mediaSources = info.mediaSources;
      } else if (item?.mediaSources.isNotEmpty == true) {
        mediaSources = item!.mediaSources;
        _playSessionId = const Uuid().v4();
      } else {
        setState(() {
          _loading = false;
          _errorMessage = '没有可用的媒体源。请检查 STRM 文件是否正确。';
        });
        return;
      }

      MediaSource ms;
      if (widget.mediaSourceId != null &&
          mediaSources.any((m) => m.id == widget.mediaSourceId)) {
        ms = mediaSources.firstWhere((m) => m.id == widget.mediaSourceId);
      } else {
        ms = mediaSources.first;
      }
      _currentMediaSourceId = ms.id;
      _audioStreams =
          ms.mediaStreams.where((s) => s.type == 'Audio').toList();
      _subtitleStreams =
          ms.mediaStreams.where((s) => s.type == 'Subtitle').toList();
      if (_audioStreams.isNotEmpty) {
        _selectedAudioIndex = _audioStreams
            .firstWhere((s) => s.isDefault, orElse: () => _audioStreams.first)
            .index;
      } else {
        _selectedAudioIndex = null;
      }
      _selectedSubtitleIndex = null;

      // 续播位置。
      final resumeTicks = _item?.userData?.playbackPositionTicks ?? 0;
      if (resumeTicks > 0) {
        _resumePosition = Duration(milliseconds: resumeTicks ~/ _ticksPerMs);
      }

      final resolved = _resolvePlayUrl(client, widget.itemId, ms);
      _playMethod = resolved.method;

      _setupListeners();

      await player.open(
        Media(
          resolved.url,
          httpHeaders: {'X-Emby-Token': client.token},
          start: _resumePosition > Duration.zero ? _resumePosition : null,
        ),
      );
      await player.setRate(_speed);
      // 始终将 mpv 内部音量设为 100（满），实际音量由系统音量控制。
      await player.setVolume(100);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _initialized = true;
      });

      _startProgressReporting();
      _resetHideTimer();
      await _reportStart();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '播放初始化失败：$e';
      });
    }
  }

  /// 按优先级解析播放地址。
  /// 1. STRM 文件（`.strm` 或 `protocol==Http && isRemote`）→ 直链 stream URL。
  /// 2. 服务器返回的 `DirectStreamUrl`。
  /// 3. `EmbyClient.directStreamUrl`（静态直链）。
  /// 4. `EmbyClient.hlsUrl`（HLS 转码）。
  /// 5. 服务器返回的 `TranscodingUrl`。
  /// 6. `EmbyClient.fallbackStreamUrl`（兜底）。
  _ResolvedPlayback _resolvePlayUrl(
    EmbyClient client,
    String itemId,
    MediaSource ms,
  ) {
    final path = ms.path?.toLowerCase() ?? '';
    final isStrm = path.endsWith('.strm') ||
        (ms.protocol == 'Http' && ms.isRemote);

    if (isStrm) {
      final url = (ms.id != null && ms.id!.isNotEmpty)
          ? client.directStreamUrl(itemId, ms.id!)
          : client.fallbackStreamUrl(itemId);
      return _ResolvedPlayback(url, 'DirectPlay');
    }

    // 1. 服务器返回的 DirectStreamUrl（可能是相对路径）。
    if (ms.directStreamUrl != null && ms.directStreamUrl!.isNotEmpty) {
      return _ResolvedPlayback(
        _ensureAbsolute(client, ms.directStreamUrl!),
        'DirectStream',
      );
    }

    final mediaSourceId = ms.id;

    // 2. 静态直链。
    if (ms.supportsDirectStream &&
        mediaSourceId != null &&
        mediaSourceId.isNotEmpty) {
      return _ResolvedPlayback(
        client.directStreamUrl(itemId, mediaSourceId),
        'DirectStream',
      );
    }

    // 3. HLS 转码。
    if (ms.supportsTranscoding &&
        mediaSourceId != null &&
        mediaSourceId.isNotEmpty) {
      return _ResolvedPlayback(
        client.hlsUrl(itemId, mediaSourceId),
        'Transcode',
      );
    }

    // 4. 服务器返回的 TranscodingUrl。
    if (ms.transcodingUrl != null && ms.transcodingUrl!.isNotEmpty) {
      return _ResolvedPlayback(
        _ensureAbsolute(client, ms.transcodingUrl!),
        'Transcode',
      );
    }

    // 5. 兜底直链。
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      return _ResolvedPlayback(
        client.directStreamUrl(itemId, mediaSourceId),
        'DirectStream',
      );
    }
    return _ResolvedPlayback(client.fallbackStreamUrl(itemId), 'DirectStream');
  }

  /// 将可能是相对路径的 Emby URL 转换为绝对地址。
  String _ensureAbsolute(EmbyClient client, String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '${client.baseUrl}${url.substring(1)}';
    return '${client.baseUrl}$url';
  }

  // ---------------------------------------------------------------------------
  // 事件监听
  // ---------------------------------------------------------------------------

  void _setupListeners() {
    _subscriptions.add(player.stream.position.listen((p) {
      _position = p;
      // 节流：每 500ms 更新一次 UI，避免每帧 setState 导致卡顿。
      final diff = (p - _lastUiPosition).abs();
      if (diff >= const Duration(milliseconds: 500) || !_isPlaying) {
        _lastUiPosition = p;
        if (mounted) setState(() {});
      }
    }));
    _subscriptions.add(player.stream.duration.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    }));
    _subscriptions.add(player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
      if (playing) {
        _resetHideTimer();
      } else {
        // 暂停时立即上报进度，避免退出时丢失最近播放位置。
        _reportProgress(isPaused: true);
      }
    }));
    _subscriptions.add(player.stream.buffering.listen((b) {
      if (!mounted) return;
      setState(() => _buffering = b);
      if (b) {
        _lastBufferedTime = DateTime.now();
        _reportProgress(isPaused: true);
      }
    }));
    _subscriptions.add(player.stream.completed.listen((completed) {
      if (completed && mounted) {
        setState(() => _completed = true);
        _reportProgress(isPaused: true);
      }
    }));
    _subscriptions.add(player.stream.error.listen((err) {
      if (!mounted || err.isEmpty) return;
      setState(() => _errorMessage = '播放错误：$err');
    }));
    // 不监听 player.stream.volume，因为实际音量由系统音量控制。
  }

  // ---------------------------------------------------------------------------
  // 播放进度上报
  // ---------------------------------------------------------------------------

  int _ticks(Duration d) => d.inMilliseconds * _ticksPerMs;

  Future<void> _reportStart() async {
    final client = _client;
    if (client == null || _reportedStart) return;
    _reportedStart = true;
    try {
      await client.reportPlaybackStart(PlaybackStartInfo(
        itemId: widget.itemId,
        mediaSourceId: _currentMediaSourceId,
        playSessionId: _playSessionId,
        positionTicks: _ticks(_resumePosition),
        playMethod: _playMethod,
        canSeek: true,
      ));
    } catch (_) {}
  }

  Future<void> _reportProgress({bool isPaused = false}) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.reportPlaybackProgress(PlaybackProgressInfo(
        itemId: widget.itemId,
        mediaSourceId: _currentMediaSourceId,
        playSessionId: _playSessionId,
        positionTicks: _ticks(_position),
        isPaused: isPaused,
        playMethod: _playMethod,
        playbackRate: _speed,
      ));
    } catch (_) {}
  }

  void _startProgressReporting() {
    _progressTimer?.cancel();
    // 每 3 秒上报一次进度，保证 Emby 继续观看列表及时更新。
    _progressTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _reportProgress(isPaused: !_isPlaying);
    });
  }

  // ---------------------------------------------------------------------------
  // 控制栏自动隐藏
  // ---------------------------------------------------------------------------

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    // 仅在播放时自动隐藏；暂停时保持可见。
    if (_isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _isPlaying) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _resetHideTimer();
    }
  }

  // ---------------------------------------------------------------------------
  // 播放控制
  // ---------------------------------------------------------------------------

  Future<void> _playOrPause() async {
    if (_completed) {
      _completed = false;
      await player.seek(Duration.zero);
      await player.play();
    } else {
      await player.playOrPause();
    }
    _resetHideTimer();
  }

  /// 退出播放器：暂停播放后返回上一页，停止上报放到后台执行。
  ///
  /// 不阻塞用户操作，dispose() 中也有兜底上报。
  /// 退出播放：上报停止、恢复方向、返回。
  Future<void> _exitPlayer() async {
    await player.pause();
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _restoreOrientation();
    _restoreBrightness();
    if (mounted) Navigator.of(context).pop();
  }

  /// 直接退出播放器，无弹窗确认。
  void _confirmExit() {
    _exitPlayer();
  }

  Future<void> _seekTo(Duration position) async {
    await player.seek(position);
    setState(() {
      _position = position;
      _completed = false;
    });
    _reportProgress(isPaused: !_isPlaying);
    _resetHideTimer();
  }

  Future<void> _setSpeed(double speed) async {
    setState(() => _speed = speed);
    await player.setRate(speed);
    _resetHideTimer();
  }

  Future<void> _selectAudio(int index) async {
    setState(() => _selectedAudioIndex = index);
    try {
      // 以流索引作为 mpv track id（直链场景下通常可对齐）。
      await player.setAudioTrack(AudioTrack(index.toString(), null, null));
    } catch (_) {}
    _resetHideTimer();
  }

  Future<void> _selectSubtitle(int? index) async {
    setState(() => _selectedSubtitleIndex = index);
    try {
      if (index == null) {
        await player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        final stream = _subtitleStreams.firstWhere((s) => s.index == index);
        if (stream.isExternal &&
            stream.deliveryUrl != null &&
            stream.deliveryUrl!.isNotEmpty) {
          final url = _ensureAbsolute(_client!, stream.deliveryUrl!);
          await player.setSubtitleTrack(SubtitleTrack.uri(
            url,
            title: stream.displayTitle,
            language: stream.language,
          ));
        } else {
          await player
              .setSubtitleTrack(SubtitleTrack(index.toString(), null, null));
        }
      }
    } catch (_) {}
    _resetHideTimer();
  }

  void _applyBrightness() {
    try {
      _volumeChannel.invokeMethod('setScreenBrightness', <String, dynamic>{
        'brightness': _screenBrightness,
      });
    } catch (_) {}
  }

  /// 恢复进入播放前的系统亮度。
  void _restoreBrightness() {
    _screenBrightness = _initialBrightness;
    _applyBrightness();
  }

  Future<void> _setVolume(double v) async {
    _volume = v.clamp(0.0, 100.0);
    // 控制系统音量。
    final sysVol = (_volume / 100.0 * _systemMaxVolume).round();
    try {
      await _volumeChannel.invokeMethod('setVolume', <String, int>{'volume': sysVol});
    } catch (_) {}
    if (mounted) setState(() {});
  }

  void _setBrightness(double value) {
    _screenBrightness = value.clamp(0.0, 1.0);
    _applyBrightness();
    setState(() {});
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      _showLockUnlock = false;
      if (_isLocked) {
        _controlsVisible = false;
        _hideTimer?.cancel();
      }
    });
  }

  void _cycleAspectRatio() {
    setState(() {
      _boxFitIndex = (_boxFitIndex + 1) % _boxFitOptions.length;
    });
    _resetHideTimer();
  }

  // ---------------------------------------------------------------------------
  // 手势
  // ---------------------------------------------------------------------------

  void _onHorizontalDragStart(DragStartDetails details) {
    _isSeeking = true;
    _seekStartPos = _position;
    _seekStartDx = details.globalPosition.dx;
    _seekPreview = _position;
    _hideTimer?.cancel();
    setState(() {});
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isSeeking) return;
    final dx = details.globalPosition.dx - _seekStartDx;
    final width = MediaQuery.of(context).size.width;
    // 每屏宽度对应 120 秒，短滑小跳、长滑大跳，手感更自然。
    final deltaMs = 120000 * (dx / width);
    var target = _seekStartPos + Duration(milliseconds: deltaMs.round());
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    setState(() => _seekPreview = target);
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    if (_isSeeking && _seekPreview != null) {
      player.seek(_seekPreview!);
      setState(() {
        _position = _seekPreview!;
        _completed = false;
      });
      // 拖动结束后立即上报进度
      _reportProgress(isPaused: !_isPlaying);
    }
    _isSeeking = false;
    _seekPreview = null;
    _resetHideTimer();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _isVerticalDragging = true;
    _verticalStartDy = details.globalPosition.dy;
    final isLeft = details.globalPosition.dx <
        MediaQuery.of(context).size.width / 2;
    _verticalMode =
        isLeft ? _VerticalMode.brightness : _VerticalMode.volume;
    _verticalStartVal = _verticalMode == _VerticalMode.volume
        ? _volume
        : _screenBrightness * 100; // 统一用 0~100 内部计算
    _hideTimer?.cancel();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isVerticalDragging) return;
    final dy = details.globalPosition.dy - _verticalStartDy;
    final height = MediaQuery.of(context).size.height;
    final ratio = (-dy / height).clamp(-1.0, 1.0);
    if (_verticalMode == _VerticalMode.volume) {
      // 音量：线性，手感跟手
      final newVol = (_verticalStartVal + ratio * 100).clamp(0.0, 100.0);
      _setVolume(newVol);
    } else {
      // 亮度：指数曲线 gamma=2.2，参考 VLC/MX Player
      // 低亮度段慢速（精细），高亮度段加速
      final curved =
          ratio.sign * math.pow(ratio.abs(), 2.2) * 100;
      final newPercent = (_verticalStartVal + curved).clamp(0.0, 100.0);
      _setBrightness(newPercent / 100.0);
    }
  }

  void _onVerticalDragEnd(DragEndDetails _) {
    _isVerticalDragging = false;
    _resetHideTimer();
  }

  // ---------------------------------------------------------------------------
  // 全屏 / 方向
  // ---------------------------------------------------------------------------

  void _enterLandscape() {
    _isPortrait = false;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _isImmersive = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _enterPortrait() {
    _isPortrait = true;
    _isImmersive = false;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  void _toggleOrientation() {
    if (_isPortrait) {
      _enterLandscape();
    } else {
      _enterPortrait();
    }
    setState(() {});
    _resetHideTimer();
  }

  void _toggleFullscreen() {
    if (_isImmersive) {
      _isImmersive = false;
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    } else {
      _isImmersive = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _resetHideTimer();
  }

  // ---------------------------------------------------------------------------
  // 生命周期
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _progressTimer?.cancel();
    _hideTimer?.cancel();
    _uiThrottleTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();

    final pos = _position;
    final itemId = widget.itemId;
    final msId = _currentMediaSourceId;
    final sid = _playSessionId;
    final method = _playMethod;
    final client = _client;

    Future(() async {
      _restoreBrightness();
      if (client != null) {
        try {
          await client.reportPlaybackStopped(PlaybackStoppedInfo(
            itemId: itemId,
            mediaSourceId: msId,
            playSessionId: sid,
            positionTicks: pos.inMilliseconds * _ticksPerMs,
            playMethod: method,
          ));
        } catch (_) {}
      }
      await player.dispose();
    });

    _restoreOrientation();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('正在加载播放资源…', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null && !_initialized) {
      return _ErrorView(
        message: _errorMessage!,
        onRetry: () {
          setState(() {
            _errorMessage = null;
            _loading = true;
          });
          _initPlayback();
        },
        onExit: () => _exitPlayer(),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 视频画面。
        RepaintBoundary(
          child: Video(
            controller: controller,
            controls: NoVideoControls,
            fit: _boxFitOptions[_boxFitIndex],
            fill: Colors.black,
          ),
        ),

        // 手势层。
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _isLocked
              ? () => setState(() => _showLockUnlock = !_showLockUnlock)
              : _toggleControls,
          onDoubleTap: _isLocked ? null : _playOrPause,
          onHorizontalDragStart: _isLocked ? null : _onHorizontalDragStart,
          onHorizontalDragUpdate: _isLocked ? null : _onHorizontalDragUpdate,
          onHorizontalDragEnd: _isLocked ? null : _onHorizontalDragEnd,
          onVerticalDragStart: _isLocked ? null : _onVerticalDragStart,
          onVerticalDragUpdate: _isLocked ? null : _onVerticalDragUpdate,
          onVerticalDragEnd: _isLocked ? null : _onVerticalDragEnd,
        ),

        // 缓冲指示（含实时速度）。
        if (_buffering && !_completed && _controlsVisible == false)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      color: Colors.white.withValues(alpha: 0.85),
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '缓冲中…',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

        // 锁定状态：点击屏幕后显示解锁按钮。
        if (_isLocked && _showLockUnlock)
          Center(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isLocked = false;
                  _showLockUnlock = false;
                  _controlsVisible = true;
                });
                _resetHideTimer();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_open, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '解锁',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // 锁定状态：未点击时显示小锁图标提示。
        if (_isLocked && !_showLockUnlock)
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Icon(
                Icons.lock,
                color: Colors.white.withValues(alpha: 0.3),
                size: 28,
              ),
            ),
          ),

        // 拖拽预览。
        if (_isSeeking && _seekPreview != null)
          _SeekPreviewOverlay(
            position: _seekPreview!,
            duration: _duration,
          ),

        // 亮度 / 音量调节指示。
        if (_isVerticalDragging)
          _VerticalIndicator(
            mode: _verticalMode,
            volume: _volume,
            brightnessPercent: (_screenBrightness * 100).round(),
          ),

        // 顶部 / 底部控制栏（锁定时隐藏）。
        if (!_isLocked)
          RepaintBoundary(
            child: IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Column(
                children: [
                  _TopBar(
                    title: _item?.name ?? widget.itemId,
                    isPortrait: _isPortrait,
                    onBack: _confirmExit,
                    onLock: _toggleLock,
                    onOrientation: _toggleOrientation,
                    onFullscreen: _toggleFullscreen,
                  ),
                  const Spacer(),
                  if (_completed)
                    Center(
                      child: IconButton.filledTonal(
                        onPressed: _playOrPause,
                        icon: const Icon(Icons.replay, size: 32),
                      ),
                    ),
                  const Spacer(),
                  _BottomBar(
                    position: _isSeeking ? (_seekPreview ?? _position) : _position,
                    duration: _duration,
                    isPlaying: _isPlaying,
                    buffering: _buffering,
                    speed: _speed,
                    boxFitLabel: _boxFitLabels[_boxFitIndex],
                    audioStreams: _audioStreams,
                    subtitleStreams: _subtitleStreams,
                    selectedAudioIndex: _selectedAudioIndex,
                    selectedSubtitleIndex: _selectedSubtitleIndex,
                    onPlayPause: _playOrPause,
                    onSeek: _seekTo,
                    onSpeed: _setSpeed,
                    onAspectRatio: _cycleAspectRatio,
                    onAudio: () => _showAudioSheet(context),
                    onSubtitle: () => _showSubtitleSheet(context),
                  ),
                ],
              ),
            ),
          ),
          ),

        // 错误浮层（播放过程中出错）。
        if (_errorMessage != null && _initialized)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Material(
              color: Colors.red.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _errorMessage = null),
                      child: const Text('关闭',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showAudioSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      builder: (_) {
        return SafeArea(
          child: RadioGroup<int>(
            groupValue: _selectedAudioIndex,
            onChanged: (v) {
              if (v != null) _selectAudio(v);
              Navigator.of(context).pop();
            },
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '音轨',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                for (final s in _audioStreams)
                  RadioListTile<int>(
                    value: s.index,
                    activeColor: Colors.white,
                    title: Text(
                      s.displayTitle ?? '音轨 ${s.index}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      [
                        if (s.language != null) s.language!,
                        if (s.codec != null) s.codec!,
                      ].join(' · '),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSubtitleSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      builder: (_) {
        return SafeArea(
          child: RadioGroup<int?>(
            groupValue: _selectedSubtitleIndex,
            onChanged: (v) {
              _selectSubtitle(v);
              Navigator.of(context).pop();
            },
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '字幕',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                RadioListTile<int?>(
                  value: null,
                  activeColor: Colors.white,
                  title: const Text('关闭', style: TextStyle(color: Colors.white)),
                ),
                for (final s in _subtitleStreams)
                  RadioListTile<int?>(
                    value: s.index,
                    activeColor: Colors.white,
                    title: Text(
                      s.displayTitle ?? '字幕 ${s.index}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      [
                        if (s.language != null) s.language!,
                        if (s.isExternal) '外挂' else '内嵌',
                        if (s.isForced) '强制',
                      ].join(' · '),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 子组件：顶部栏
// -----------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.isPortrait,
    required this.onBack,
    required this.onLock,
    required this.onOrientation,
    required this.onFullscreen,
  });

  final String title;
  final bool isPortrait;
  final VoidCallback onBack;
  final VoidCallback onLock;
  final VoidCallback onOrientation;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.lock_outline, color: Colors.white),
              onPressed: onLock,
              tooltip: '锁定',
            ),
            IconButton(
              icon: Icon(
                isPortrait
                    ? Icons.screen_rotation
                    : Icons.stay_current_portrait,
                color: Colors.white,
              ),
              onPressed: onOrientation,
              tooltip: isPortrait ? '横屏' : '竖屏',
            ),
            IconButton(
              icon: const Icon(Icons.fullscreen, color: Colors.white),
              onPressed: onFullscreen,
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 子组件：底部控制栏
// -----------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.buffering,
    required this.speed,
    required this.boxFitLabel,
    required this.audioStreams,
    required this.subtitleStreams,
    required this.selectedAudioIndex,
    required this.selectedSubtitleIndex,
    required this.onPlayPause,
    required this.onSeek,
    required this.onSpeed,
    required this.onAspectRatio,
    required this.onAudio,
    required this.onSubtitle,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool buffering;
  final double speed;
  final String boxFitLabel;
  final List<MediaStream> audioStreams;
  final List<MediaStream> subtitleStreams;
  final int? selectedAudioIndex;
  final int? selectedSubtitleIndex;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onSpeed;
  final VoidCallback onAspectRatio;
  final VoidCallback onAudio;
  final VoidCallback onSubtitle;

  @override
  Widget build(BuildContext context) {
    final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
    final value = position.inMilliseconds.toDouble().clamp(0.0, max);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: Colors.redAccent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.redAccent,
              ),
              child: Slider(
                value: value,
                max: max,
                onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: onPlayPause,
                ),
                Text(
                  _formatDuration(position),
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const Text(
                  ' / ',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                Text(
                  _formatDuration(duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const Spacer(),
                IconButton(
                  icon: Text(
                    boxFitLabel,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  onPressed: onAspectRatio,
                  tooltip: '屏幕比例',
                ),
                if (audioStreams.length > 1)
                  IconButton(
                    icon: const Icon(Icons.audiotrack, color: Colors.white),
                    onPressed: onAudio,
                    tooltip: '音轨',
                  ),
                if (subtitleStreams.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.subtitles, color: Colors.white),
                    onPressed: onSubtitle,
                    tooltip: '字幕',
                  ),
                _SpeedMenu(speed: speed, onSelected: onSpeed),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedMenu extends StatelessWidget {
  const _SpeedMenu({required this.speed, required this.onSelected});
  final double speed;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: '倍速',
      color: Colors.black87,
      icon: Text(
        '${speed}x',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final s in _speedOptions)
          PopupMenuItem<double>(
            value: s,
            child: Row(
              children: [
                Text('${s}x',
                    style: const TextStyle(color: Colors.white)),
                if (s == speed) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check, color: Colors.redAccent, size: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 子组件：拖拽预览 / 垂直调节指示
// -----------------------------------------------------------------------------

class _SeekPreviewOverlay extends StatelessWidget {
  const _SeekPreviewOverlay({required this.position, required this.duration});
  final Duration position;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.fast_forward, color: Colors.white, size: 32),
          const SizedBox(height: 6),
          Text(
            '${_formatDuration(position)} / ${_formatDuration(duration)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: Colors.black87, blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerticalIndicator extends StatelessWidget {
  const _VerticalIndicator({
    required this.mode,
    required this.volume,
    required this.brightnessPercent,
  });

  final _VerticalMode mode;
  final double volume;
  final int brightnessPercent;

  @override
  Widget build(BuildContext context) {
    final value = mode == _VerticalMode.volume
        ? volume.round().clamp(0, 100)
        : brightnessPercent;
    return Positioned(
      right: 24,
      top: 0,
      bottom: 0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            mode == _VerticalMode.volume
                ? (value == 0 ? Icons.volume_off : Icons.volume_up)
                : Icons.brightness_6_outlined,
            color: Colors.white,
            size: 28,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 4)],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 120,
            width: 24,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: 4,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  width: 4,
                  height: (value / 100 * 120).clamp(0.0, 120.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$value%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 子组件：错误视图
// -----------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onExit,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onExit,
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: Colors.redAccent, size: 56),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 工具
// -----------------------------------------------------------------------------

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
