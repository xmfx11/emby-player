import 'package:dio/dio.dart';

import '../models/emby_models.dart';

/// Emby 服务端 API 客户端，基于 [Dio]。
///
/// 通过 [EmbyServer] 配置构造，自动设置 baseUrl 与默认请求头
/// （`X-Emby-Token`、`X-Emby-Authorization`）。所有网络请求均返回
/// `Future<T>`，遇到错误时直接抛出 [DioException] 或解析异常。
class EmbyClient {
  /// 底层 Dio 实例，可直接用于自定义请求。
  late final Dio dio;

  /// 已规范化的服务器地址（保证以 `/` 结尾）。
  final String baseUrl;

  /// 登录后获得的 AccessToken。
  final String token;

  /// 当前登录用户 Id。
  final String userId;

  /// 设备标识。
  final String deviceId;

  /// 默认客户端标识，用于认证头。
  static const String defaultClient = 'Emby Flutter';

  /// 默认版本号，用于认证头。
  static const String defaultVersion = '1.0.0';

  EmbyClient(EmbyServer server)
      : baseUrl = normalizeUrl(server.url),
        token = server.token,
        userId = server.userId,
        deviceId = server.deviceId {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
      headers: {
        'Accept': 'application/json',
        'X-Emby-Token': server.token,
        'X-Emby-Authorization':
            authHeader(server.deviceId, token: server.token),
      },
    ));
  }

  // -------------------------------------------------------------------------
  // 静态工具方法
  // -------------------------------------------------------------------------

  /// 构造 Emby 认证头。
  ///
  /// 格式：`MediaBrowser Client="...", Device="...", DeviceId="...", Version="..."`
  /// 当 [token] 非空时会追加 `Token="..."`。
  static String authHeader(
    String deviceId, {
    String client = defaultClient,
    String device = defaultClient,
    String version = defaultVersion,
    String? token,
  }) {
    final parts = <String>[
      'Client="$client"',
      'Device="$device"',
      'DeviceId="$deviceId"',
      'Version="$version"',
    ];
    if (token != null && token.isNotEmpty) {
      parts.add('Token="$token"');
    }
    return 'MediaBrowser ${parts.join(', ')}';
  }

  /// 规范化服务器地址：去除首尾空白，补全 `http://` 前缀与 `/` 结尾。
  static String normalizeUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (!url.endsWith('/')) {
      url = '$url/';
    }
    return url;
  }

  /// 通过用户名密码登录指定服务器。
  ///
  /// 调用 `POST /Users/AuthenticateByName`，返回 [AuthResult]。
  /// 登录前无需 token，认证头仅携带设备信息。
  static Future<AuthResult> login(
    String serverUrl,
    String username,
    String password,
    String deviceId,
  ) async {
    final normalized = normalizeUrl(serverUrl);
    final dio = Dio(BaseOptions(
      baseUrl: normalized,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
      headers: {
        'Accept': 'application/json',
        'X-Emby-Authorization': authHeader(deviceId),
        'Content-Type': 'application/json',
      },
    ));

    final response = await dio.post(
      'Users/AuthenticateByName',
      data: <String, dynamic>{
        'Username': username,
        'Pw': password,
      },
    );
    return AuthResult.fromJson(_asMap(response.data));
  }

  // -------------------------------------------------------------------------
  // 浏览与查询
  // -------------------------------------------------------------------------

  /// 获取用户视图（媒体库列表）：`GET /Users/{userId}/Views`。
  Future<ItemsResponse> getViews() async {
    _ensureUserId();
    final response = await dio.get('Users/$userId/Views');
    return ItemsResponse.fromJson(_asMap(response.data));
  }

  /// 获取媒体项列表：`GET /Users/{userId}/Items`。
  ///
  /// 支持按 [types]（IncludeItemTypes）、[genres]、[tags] 等过滤。
  Future<ItemsResponse> getItems(
    String parentId, {
    List<String>? types,
    bool? recursive,
    int? startIndex,
    int? limit,
    List<String>? genres,
    List<String>? tags,
    String? sortBy,
    String? sortOrder,
    List<String>? fields,
  }) async {
    _ensureUserId();
    final query = <String, dynamic>{
      'ParentId': parentId,
    };
    if (types != null && types.isNotEmpty) {
      query['IncludeItemTypes'] = types.join(',');
    }
    if (recursive != null) query['Recursive'] = recursive;
    if (startIndex != null) query['StartIndex'] = startIndex;
    if (limit != null) query['Limit'] = limit;
    if (genres != null && genres.isNotEmpty) query['Genres'] = genres.join(',');
    if (tags != null && tags.isNotEmpty) query['Tags'] = tags.join(',');
    if (sortBy != null && sortBy.isNotEmpty) query['SortBy'] = sortBy;
    if (sortOrder != null && sortOrder.isNotEmpty) query['SortOrder'] = sortOrder;
    if (fields != null && fields.isNotEmpty) query['Fields'] = fields.join(',');

    final response = await dio.get('Users/$userId/Items', queryParameters: query);
    return ItemsResponse.fromJson(_asMap(response.data));
  }

  /// 获取单个媒体项详情：`GET /Users/{userId}/Items/{itemId}`。
  ///
  /// 传入 [fields]（如 `['Overview','MediaSources','Backdrop']`）以获取扩展信息。
  Future<BaseItem> getItem(String itemId, {List<String>? fields}) async {
    _ensureUserId();
    final query = <String, dynamic>{};
    if (fields != null && fields.isNotEmpty) {
      query['Fields'] = fields.join(',');
    }
    final response = await dio.get(
      'Users/$userId/Items/$itemId',
      queryParameters: query,
    );
    return BaseItem.fromJson(_asMap(response.data));
  }

  /// 按标签 / 类型 / 风格搜索：`GET /Users/{userId}/Items`（Recursive=true）。
  Future<ItemsResponse> getItemsByFilter({
    String? genre,
    String? tag,
    List<String>? includeTypes,
    String? parentId,
    int? startIndex,
    int? limit,
    List<String>? fields,
  }) async {
    _ensureUserId();
    final query = <String, dynamic>{
      'Recursive': true,
    };
    if (parentId != null && parentId.isNotEmpty) query['ParentId'] = parentId;
    if (genre != null && genre.isNotEmpty) query['Genres'] = genre;
    if (tag != null && tag.isNotEmpty) query['Tags'] = tag;
    if (includeTypes != null && includeTypes.isNotEmpty) {
      query['IncludeItemTypes'] = includeTypes.join(',');
    }
    if (startIndex != null) query['StartIndex'] = startIndex;
    if (limit != null) query['Limit'] = limit;
    if (fields != null && fields.isNotEmpty) query['Fields'] = fields.join(',');

    final response = await dio.get('Users/$userId/Items', queryParameters: query);
    return ItemsResponse.fromJson(_asMap(response.data));
  }

  /// 获取指定演员参与的影视作品：`GET /Users/{userId}/Items?PersonId=...`。
  Future<ItemsResponse> getItemsByPerson(
    String personId, {
    int? limit,
    int? startIndex,
    List<String>? fields,
  }) async {
    _ensureUserId();
    final query = <String, dynamic>{
      'Recursive': true,
      'PersonIds': personId,
    };
    if (limit != null) query['Limit'] = limit;
    if (startIndex != null) query['StartIndex'] = startIndex;
    if (fields != null && fields.isNotEmpty) query['Fields'] = fields.join(',');

    final response = await dio.get('Users/$userId/Items', queryParameters: query);
    return ItemsResponse.fromJson(_asMap(response.data));
  }

  /// 获取继续观看：`GET /Users/{userId}/Items/Resume`。
  Future<ItemsResponse> getResumeItems({
    int? limit,
    int? startIndex,
    List<String>? types,
    List<String>? fields,
  }) async {
    _ensureUserId();
    final query = <String, dynamic>{};
    if (limit != null) query['Limit'] = limit;
    if (startIndex != null) query['StartIndex'] = startIndex;
    if (types != null && types.isNotEmpty) {
      query['IncludeItemTypes'] = types.join(',');
    }
    if (fields != null && fields.isNotEmpty) query['Fields'] = fields.join(',');

    final response = await dio.get(
      'Users/$userId/Items/Resume',
      queryParameters: query,
    );
    return ItemsResponse.fromJson(_asMap(response.data));
  }

  /// 获取最新内容：`GET /Users/{userId}/Items/Latest`。
  ///
  /// 该接口返回的是 JSON 数组而非分页对象。
  Future<List<BaseItem>> getLatestItems({
    String? parentId,
    int? limit,
    List<String>? types,
    List<String>? fields,
  }) async {
    _ensureUserId();
    final query = <String, dynamic>{};
    if (parentId != null && parentId.isNotEmpty) query['ParentId'] = parentId;
    if (limit != null) query['Limit'] = limit;
    if (types != null && types.isNotEmpty) {
      query['IncludeItemTypes'] = types.join(',');
    }
    if (fields != null && fields.isNotEmpty) query['Fields'] = fields.join(',');

    final response = await dio.get(
      'Users/$userId/Items/Latest',
      queryParameters: query,
    );
    final data = response.data;
    if (data is! List) {
      return const [];
    }
    return data
        .map((e) => BaseItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 关键词搜索：`GET /Users/{userId}/Items`（带 SearchTerm）。
  Future<ItemsResponse> search(
    String query, {
    int? limit,
    int? startIndex,
    List<String>? includeTypes,
    List<String>? fields,
  }) async {
    _ensureUserId();
    final params = <String, dynamic>{
      'SearchTerm': query,
      'Recursive': true,
    };
    if (limit != null) params['Limit'] = limit;
    if (startIndex != null) params['StartIndex'] = startIndex;
    if (includeTypes != null && includeTypes.isNotEmpty) {
      params['IncludeItemTypes'] = includeTypes.join(',');
    }
    if (fields != null && fields.isNotEmpty) params['Fields'] = fields.join(',');

    final response = await dio.get(
      'Users/$userId/Items',
      queryParameters: params,
    );
    return ItemsResponse.fromJson(_asMap(response.data));
  }

  // -------------------------------------------------------------------------
  // 播放信息
  // -------------------------------------------------------------------------

  /// 获取播放信息：多级回退策略，适配 STRM 等特殊文件。
  Future<PlaybackInfo> getPlaybackInfo(String itemId) async {
    final errors = <String>[];

    // 1. POST 带完整 DeviceProfile
    try {
      return await _tryPostWithProfile(itemId);
    } catch (e) {
      errors.add('POST(profile): $e');
    }

    // 2. POST 最简参数
    try {
      return await _tryPostSimple(itemId);
    } catch (e) {
      errors.add('POST(simple): $e');
    }

    // 3. GET 带 UserId
    try {
      return await _tryGetWithUserId(itemId);
    } catch (e) {
      errors.add('GET(userId): $e');
    }

    // 4. GET 无参数
    try {
      final response = await dio.get('Items/$itemId/PlaybackInfo');
      return PlaybackInfo.fromJson(_asMap(response.data));
    } catch (e) {
      errors.add('GET(simple): $e');
      throw DioException(
        requestOptions: RequestOptions(path: 'Items/$itemId/PlaybackInfo'),
        message: '所有播放信息获取方式均失败:\n${errors.join('\n')}',
      );
    }
  }

  Future<PlaybackInfo> _tryPostWithProfile(String itemId) async {
    final request = PlaybackInfoRequest(
      userId: userId,
      maxStreamingBitrate: 100000000,
      isPlayback: false,
      autoOpenLiveStream: false,
      enableDirectPlay: true,
      enableDirectStream: true,
      enableTranscoding: true,
      allowVideoStreamCopy: true,
      allowAudioStreamCopy: true,
      deviceProfile: _defaultDeviceProfile(),
    );
    final response = await dio.post(
      'Items/$itemId/PlaybackInfo',
      data: request.toJson(),
    );
    return PlaybackInfo.fromJson(_asMap(response.data));
  }

  Future<PlaybackInfo> _tryPostSimple(String itemId) async {
    final response = await dio.post(
      'Items/$itemId/PlaybackInfo',
      data: <String, dynamic>{
        'UserId': userId,
        'IsPlayback': false,
        'AutoOpenLiveStream': false,
        'EnableDirectPlay': true,
        'EnableDirectStream': true,
        'EnableTranscoding': false,
      },
    );
    return PlaybackInfo.fromJson(_asMap(response.data));
  }

  Future<PlaybackInfo> _tryGetWithUserId(String itemId) async {
    final response = await dio.get(
      'Items/$itemId/PlaybackInfo',
      queryParameters: {'UserId': userId},
    );
    return PlaybackInfo.fromJson(_asMap(response.data));
  }

  /// 获取剧照：`GET /Users/{userId}/Items/{itemId}`，带 `Fields=Backdrop`。
  ///
  /// 返回的 [BaseItem.backdropImageTags] 将被填充。
  Future<BaseItem> getBackdropImages(String itemId) async {
    return getItem(itemId, fields: const ['Backdrop']);
  }

  /// 获取媒体项的所有可用图片信息：`GET /Items/{itemId}/Images`。
  ///
  /// 返回图片类型与标签的列表，用于剧照画廊等场景。
  Future<List<RemoteImageInfo>> getImages(String itemId) async {
    try {
      final response = await dio.get('Items/$itemId/Images');
      final data = response.data;
      if (data is! List) return const [];
      return data
          .map((e) => RemoteImageInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // 收藏
  // -------------------------------------------------------------------------

  /// 标记收藏：`POST /Users/{userId}/FavoriteItems/{itemId}`。
  Future<void> markFavorite(String itemId) async {
    _ensureUserId();
    await dio.post('Users/$userId/FavoriteItems/$itemId');
  }

  /// 取消收藏：`DELETE /Users/{userId}/FavoriteItems/{itemId}`。
  Future<void> unmarkFavorite(String itemId) async {
    _ensureUserId();
    await dio.delete('Users/$userId/FavoriteItems/$itemId');
  }

  // -------------------------------------------------------------------------
  // 播放上报
  // -------------------------------------------------------------------------

  /// 上报开始播放：`POST /Sessions/Playing`。
  Future<void> reportPlaybackStart(PlaybackStartInfo info) async {
    await dio.post('Sessions/Playing', data: info.toJson());
  }

  /// 上报播放进度：`POST /Sessions/Playing/Progress`。
  Future<void> reportPlaybackProgress(PlaybackProgressInfo info) async {
    await dio.post('Sessions/Playing/Progress', data: info.toJson());
  }

  /// 上报停止播放：`POST /Sessions/Playing/Stopped`。
  Future<void> reportPlaybackStopped(PlaybackStoppedInfo info) async {
    await dio.post('Sessions/Playing/Stopped', data: info.toJson());
  }

  // -------------------------------------------------------------------------
  // URL 构造
  // -------------------------------------------------------------------------

  /// 构造图片 URL（api_key 由 Header 传递）。
  String imageUrl(
    String itemId, {
    String? tag,
    String type = 'Primary',
    int? maxHeight,
    int? imageIndex,
  }) {
    final path = imageIndex != null
        ? '${Uri.encodeComponent(type)}/${Uri.encodeComponent(imageIndex.toString())}'
        : Uri.encodeComponent(type);
    final parts = <String>[];
    if (maxHeight != null) parts.add('maxHeight=$maxHeight');
    parts.add('quality=90');
    if (tag != null && tag.isNotEmpty) {
      parts.add('tag=${Uri.encodeComponent(tag)}');
    }
    return '${baseUrl}Items/${Uri.encodeComponent(itemId)}/Images/'
        '$path?${parts.join('&')}';
  }

  /// 直链播放地址（api_key 由 Header 传递）。
  String directStreamUrl(String itemId, String mediaSourceId) {
    return '${baseUrl}Videos/${Uri.encodeComponent(itemId)}/stream'
        '?static=true&mediaSourceId=${Uri.encodeComponent(mediaSourceId)}';
  }

  /// HLS 转码地址。
  String hlsUrl(String itemId, String mediaSourceId) {
    return '${baseUrl}Videos/${Uri.encodeComponent(itemId)}/master.m3u8'
        '?mediaSourceId=${Uri.encodeComponent(mediaSourceId)}';
  }

  /// 兜底直链。
  String fallbackStreamUrl(String itemId) {
    return '${baseUrl}Videos/${Uri.encodeComponent(itemId)}/stream?static=true';
  }

  /// 字幕地址。
  String subtitleUrl(String itemId, String mediaSourceId, int index) {
    return '${baseUrl}Videos/${Uri.encodeComponent(itemId)}/'
        '${Uri.encodeComponent(mediaSourceId)}/Subtitles/'
        '${Uri.encodeComponent(index.toString())}/Stream.srt';
  }

  // -------------------------------------------------------------------------
  // 内部辅助
  // -------------------------------------------------------------------------

  void _ensureUserId() {
    if (userId.isEmpty) {
      throw StateError('EmbyClient.userId 未设置，请先完成登录。');
    }
  }

  // -------------------------------------------------------------------------
  // 资源管理
  // -------------------------------------------------------------------------

  /// 释放 Dio 实例，关闭所有连接。
  void dispose() {
    dio.close();
  }
  static Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.cast<String, dynamic>();
    throw FormatException('期望 JSON 对象，但收到: ${data.runtimeType}');
  }

  /// 构造最小化 DeviceProfile：常见容器直链 + HLS 转码回退。
  DeviceProfile _defaultDeviceProfile() {
    return const DeviceProfile(
      name: 'Emby Flutter Player',
      maxStreamingBitrate: 100000000,
      maxStaticBitrate: 100000000,
      maxStaticMusicBitrate: 320000,
      directPlayProfiles: [
        DirectPlayProfile(
          container:
              'mp4,mkv,ts,mpegts,m2ts,avi,mov,wmv,flv,webm,iso,m4v,3gp',
          type: 'Video',
          videoCodec:
              'h264,h265,hevc,vp8,vp9,av1,mpeg4,mpeg2video,mpeg1video,vc1,wmv3,wmv2',
          audioCodec:
              'aac,mp3,ac3,eac3,dca,truehd,opus,vorbis,flac,pcm,alac,mp2,aac_latm',
        ),
        DirectPlayProfile(
          container: 'mp3,flac,aac,m4a,ogg,opus,wav,wma',
          type: 'Audio',
          audioCodec: 'mp3,flac,aac,opus,vorbis,pcm,alac,wma',
        ),
        DirectPlayProfile(
          container: 'jpg,jpeg,png,gif,webp,bmp',
          type: 'Photo',
        ),
      ],
      transcodingProfiles: [
        TranscodingProfile(
          container: 'ts',
          type: 'Video',
          videoCodec: 'h264',
          audioCodec: 'aac',
          protocol: 'hls',
          estimateContentLength: false,
          transcodeSeekInfo: 'Auto',
          breakOnNonKeyFrames: true,
        ),
        TranscodingProfile(
          container: 'aac',
          type: 'Audio',
          audioCodec: 'aac',
          protocol: 'hls',
        ),
      ],
      subtitleProfiles: [
        SubtitleProfile(format: 'srt', method: 'External'),
        SubtitleProfile(format: 'vtt', method: 'External'),
        SubtitleProfile(format: 'ass', method: 'External'),
        SubtitleProfile(format: 'ssa', method: 'External'),
        SubtitleProfile(format: 'sub', method: 'External'),
        SubtitleProfile(format: 'smi', method: 'External'),
      ],
    );
  }
}
