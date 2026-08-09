/// Emby API 数据模型
///
/// 所有模型与 Emby Server 的 JSON 响应格式（PascalCase 字段名）对齐。
///
/// 采用手写 `fromJson` 构造函数，统一使用
/// `json['FieldName'] as Type? ?? defaultValue` 模式解析，避免对
/// `json_serializable` / `build_runner` 的运行时依赖。请求体与播放上报
/// 模型额外提供 `toJson`，输出 PascalCase 键。
library;

// ---------------------------------------------------------------------------
// 辅助函数
// ---------------------------------------------------------------------------

/// 移除 Map 中值为 `null` 的键，用于构造干净的请求体。
Map<String, dynamic> _omitNulls(Map<String, dynamic> map) {
  return Map<String, dynamic>.from(map)
    ..removeWhere((_, dynamic v) => v == null);
}

/// 安全地将任意 JSON 值转换为 `String?`。
///
/// Emby Server 对某些字段（如 `Id`、`SeriesId`、`ErrorCode` 等）可能返回
/// `int` 而非 `String`，直接使用 `as String?` 会抛出类型转换异常。
String? _asString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// 安全地将 JSON 数组转换为 `List<String>`，跳过 `null` 元素。
List<String> _asStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((dynamic e) => e?.toString())
      .where((s) => s != null && s.isNotEmpty)
      .cast<String>()
      .toList();
}

// ---------------------------------------------------------------------------
// 服务器配置
// ---------------------------------------------------------------------------

/// 本地保存的 Emby 服务器配置。
///
/// 该模型并非直接来自 Emby API 响应，但提供 `fromJson` / `toJson`
/// 以便通过 SharedPreferences 等方式持久化。
class EmbyServer {
  const EmbyServer({
    required this.id,
    required this.url,
    required this.name,
    required this.userId,
    required this.token,
    required this.deviceId,
    required this.username,
  });

  /// 唯一标识（用于本地管理多服务器）
  final String id;

  /// 服务器地址，如 `https://emby.example.com`
  final String url;

  /// 服务器名称
  final String name;

  /// 当前用户 Id
  final String userId;

  /// 访问令牌（请求头 X-Emby-Token）
  final String token;

  /// 设备 Id（鉴权与播放会话标识）
  final String deviceId;

  /// 登录用户名
  final String username;

  factory EmbyServer.fromJson(Map<String, dynamic> json) {
    return EmbyServer(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      name: json['name'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      token: json['token'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      username: json['username'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'userId': userId,
        'token': token,
        'deviceId': deviceId,
        'username': username,
      };

  EmbyServer copyWith({
    String? id,
    String? url,
    String? name,
    String? userId,
    String? token,
    String? deviceId,
    String? username,
  }) {
    return EmbyServer(
      id: id ?? this.id,
      url: url ?? this.url,
      name: name ?? this.name,
      userId: userId ?? this.userId,
      token: token ?? this.token,
      deviceId: deviceId ?? this.deviceId,
      username: username ?? this.username,
    );
  }
}

// ---------------------------------------------------------------------------
// 认证（登录）
// ---------------------------------------------------------------------------

/// 登录请求体（POST /Users/AuthenticateByName）。
///
/// JSON 字段：`Username`、`Pw`。
class AuthRequest {
  const AuthRequest({
    required this.username,
    this.pw,
  });

  final String username;
  final String? pw;

  Map<String, dynamic> toJson() => {
        'Username': username,
        'Pw': pw,
      };
}

/// 登录响应（POST /Users/AuthenticateByName 返回）。
///
/// JSON 字段：`User`、`AccessToken`、`SessionInfo`。
class AuthResult {
  const AuthResult({
    this.user,
    this.accessToken = '',
    this.sessionInfo,
  });

  /// 登录用户信息
  final UserInfo? user;

  /// 访问令牌
  final String accessToken;

  /// 会话信息（原始 JSON，按需解析）
  final Map<String, dynamic>? sessionInfo;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      user: json['User'] != null
          ? UserInfo.fromJson(json['User'] as Map<String, dynamic>)
          : null,
      accessToken: json['AccessToken'] as String? ?? '',
      sessionInfo: json['SessionInfo'] as Map<String, dynamic>?,
    );
  }
}

/// 用户信息。
///
/// JSON 字段：`Id`、`Name`、`PrimaryImageTag`。
class UserInfo {
  const UserInfo({
    required this.id,
    required this.name,
    this.primaryImageTag,
  });

  final String id;
  final String name;
  final String? primaryImageTag;

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: _asString(json['Id']) ?? '',
      name: _asString(json['Name']) ?? '',
      primaryImageTag: _asString(json['PrimaryImageTag']),
    );
  }
}

// ---------------------------------------------------------------------------
// 列表与媒体项
// ---------------------------------------------------------------------------

/// 通用列表响应（如 /Items、/Users/{Id}/Items）。
///
/// JSON 字段：`Items`、`TotalRecordCount`、`StartIndex`。
class ItemsResponse {
  const ItemsResponse({
    this.items = const <BaseItem>[],
    this.totalRecordCount = 0,
    this.startIndex = 0,
  });

  /// 当前页的媒体项列表
  final List<BaseItem> items;

  /// 服务端记录总数
  final int totalRecordCount;

  /// 起始索引（分页）
  final int startIndex;

  factory ItemsResponse.fromJson(Map<String, dynamic> json) {
    return ItemsResponse(
      items: (json['Items'] as List<dynamic>?)
              ?.map((dynamic e) => BaseItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <BaseItem>[],
      totalRecordCount: (json['TotalRecordCount'] as num?)?.toInt() ?? 0,
      startIndex: (json['StartIndex'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 媒体项（Emby BaseItemDto）。
///
/// 字段名与 Emby Server 返回的 PascalCase 一致。
class BaseItem {
  const BaseItem({
    required this.id,
    required this.name,
    required this.type,
    this.collectionType,
    this.imageTags = const ImageTags(),
    this.backdropImageTags = const <String>[],
    this.overview,
    this.runTimeTicks,
    this.productionYear,
    this.communityRating,
    this.officialRating,
    this.genres = const <String>[],
    this.tags = const <String>[],
    this.studios = const <Studio>[],
    this.people = const <Person>[],
    this.indexNumber,
    this.parentIndexNumber,
    this.seriesName,
    this.seriesId,
    this.userData,
    this.mediaType,
    this.dateCreated,
    this.childCount,
    this.recursiveItemCount,
    this.datePlayed,
    this.mediaSources = const <MediaSource>[],
  });

  /// Item Id
  final String id;

  /// 名称
  final String name;

  /// 类型，如 `Movie`、`Series`、`Episode`、`MusicAlbum`、`Audio`、`CollectionFolder`
  final String type;

  /// 虚拟文件夹的集合类型，如 `movies`、`tvshows`、`music`
  final String? collectionType;

  /// 各类图片标签
  final ImageTags imageTags;

  /// 背景图片标签列表
  final List<String> backdropImageTags;

  /// 剧情简介
  final String? overview;

  /// 运行时长（Ticks，1 秒 = 10,000,000 Ticks）
  final int? runTimeTicks;

  /// 发行年份
  final int? productionYear;

  /// 社区评分
  final double? communityRating;

  /// 官方分级，如 `PG-13`
  final String? officialRating;

  /// 风格列表
  final List<String> genres;

  /// 标签列表
  final List<String> tags;

  /// 制作工作室
  final List<Studio> studios;

  /// 演职人员
  final List<Person> people;

  /// 集号（剧集）
  final int? indexNumber;

  /// 季号（剧集）
  final int? parentIndexNumber;

  /// 剧集所属剧集名称
  final String? seriesName;

  /// 剧集所属剧集 Id
  final String? seriesId;

  /// 当前用户对该项的数据
  final UserData? userData;

  /// 媒体类型，如 `Video`、`Audio`
  final String? mediaType;

  /// 创建时间（原始 ISO 字符串）
  final String? dateCreated;

  /// 子项数量
  final int? childCount;

  /// 递归子项数量（用于文件夹）
  final int? recursiveItemCount;

  /// 上次播放时间（原始 ISO 字符串）
  final String? datePlayed;

  /// 媒体源列表（需 Fields=MediaSources 才返回）
  final List<MediaSource> mediaSources;

  factory BaseItem.fromJson(Map<String, dynamic> json) {
    return BaseItem(
      id: _asString(json['Id']) ?? '',
      name: _asString(json['Name']) ?? '',
      type: _asString(json['Type']) ?? '',
      collectionType: _asString(json['CollectionType']),
      imageTags: json['ImageTags'] != null
          ? ImageTags.fromJson(json['ImageTags'] as Map<String, dynamic>)
          : const ImageTags(),
      backdropImageTags: _asStringList(json['BackdropImageTags']),
      overview: _asString(json['Overview']),
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      productionYear: (json['ProductionYear'] as num?)?.toInt(),
      communityRating: (json['CommunityRating'] as num?)?.toDouble(),
      officialRating: _asString(json['OfficialRating']),
      genres: _asStringList(json['Genres']),
      tags: _asStringList(json['Tags']),
      studios: (json['Studios'] as List<dynamic>?)
              ?.map((dynamic e) => Studio.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <Studio>[],
      people: (json['People'] as List<dynamic>?)
              ?.map((dynamic e) => Person.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <Person>[],
      indexNumber: (json['IndexNumber'] as num?)?.toInt(),
      parentIndexNumber: (json['ParentIndexNumber'] as num?)?.toInt(),
      seriesName: _asString(json['SeriesName']),
      seriesId: _asString(json['SeriesId']),
      userData: json['UserData'] != null
          ? UserData.fromJson(json['UserData'] as Map<String, dynamic>)
          : null,
      mediaType: _asString(json['MediaType']),
      dateCreated: _asString(json['DateCreated']),
      childCount: (json['ChildCount'] as num?)?.toInt(),
      recursiveItemCount: (json['RecursiveItemCount'] as num?)?.toInt(),
      datePlayed: _asString(json['DatePlayed']),
      mediaSources: (json['MediaSources'] as List<dynamic>?)
              ?.map((dynamic e) => MediaSource.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <MediaSource>[],
    );
  }
}

/// 图片标签集合（BaseItem.ImageTags）。
///
/// JSON 字段：`Primary`、`Banner`、`Thumb`、`Logo`、`Backdrop`。
class ImageTags {
  const ImageTags({
    this.primary,
    this.banner,
    this.thumb,
    this.logo,
    this.backdrop,
  });

  final String? primary;
  final String? banner;
  final String? thumb;
  final String? logo;
  final String? backdrop;

  factory ImageTags.fromJson(Map<String, dynamic> json) {
    return ImageTags(
      primary: _asString(json['Primary']),
      banner: _asString(json['Banner']),
      thumb: _asString(json['Thumb']),
      logo: _asString(json['Logo']),
      backdrop: _asString(json['Backdrop']),
    );
  }
}

/// 工作室。
///
/// JSON 字段：`Id`、`Name`。
class Studio {
  const Studio({
    this.id,
    this.name,
  });

  final String? id;
  final String? name;

  factory Studio.fromJson(Map<String, dynamic> json) {
    return Studio(
      id: _asString(json['Id']),
      name: _asString(json['Name']),
    );
  }
}

/// 演职人员。
///
/// JSON 字段：`Id`、`Name`、`Role`、`Type`、`PrimaryImageTag`。
class Person {
  const Person({
    this.id,
    this.name,
    this.role,
    this.type,
    this.primaryImageTag,
  });

  final String? id;
  final String? name;
  final String? role;

  /// 人员类型，如 `Actor`、`Director`、`Composer`
  final String? type;
  final String? primaryImageTag;

  factory Person.fromJson(Map<String, dynamic> json) {
    return Person(
      id: _asString(json['Id']),
      name: _asString(json['Name']),
      role: _asString(json['Role']),
      type: _asString(json['Type']),
      primaryImageTag: _asString(json['PrimaryImageTag']),
    );
  }
}

/// 用户对某个媒体项的数据。
///
/// JSON 字段：`Played`、`PlayCount`、`IsFavorite`、`PlaybackPositionTicks`、
/// `PlayedPercentage`。
class UserData {
  const UserData({
    this.played = false,
    this.playCount = 0,
    this.isFavorite = false,
    this.playbackPositionTicks,
    this.playedPercentage,
  });

  /// 是否已播放完成
  final bool played;

  /// 播放次数
  final int playCount;

  /// 是否收藏
  final bool isFavorite;

  /// 上次播放位置（Ticks）
  final int? playbackPositionTicks;

  /// 已播放百分比（0.0 - 100.0）
  final double? playedPercentage;

  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      played: json['Played'] as bool? ?? false,
      playCount: (json['PlayCount'] as num?)?.toInt() ?? 0,
      isFavorite: json['IsFavorite'] as bool? ?? false,
      playbackPositionTicks: (json['PlaybackPositionTicks'] as num?)?.toInt(),
      playedPercentage: (json['PlayedPercentage'] as num?)?.toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// 播放信息
// ---------------------------------------------------------------------------

/// 播放信息响应（POST /Items/{Id}/PlaybackInfo）。
///
/// JSON 字段：`MediaSources`、`PlaySessionId`、`ErrorCode`。
class PlaybackInfo {
  const PlaybackInfo({
    this.mediaSources = const <MediaSource>[],
    this.playSessionId,
    this.errorCode,
  });

  /// 可用的媒体源
  final List<MediaSource> mediaSources;

  /// 播放会话 Id
  final String? playSessionId;

  /// 错误码（无错误时为 null）
  final String? errorCode;

  factory PlaybackInfo.fromJson(Map<String, dynamic> json) {
    return PlaybackInfo(
      mediaSources: (json['MediaSources'] as List<dynamic>?)
              ?.map((dynamic e) => MediaSource.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <MediaSource>[],
      playSessionId: _asString(json['PlaySessionId']),
      errorCode: _asString(json['ErrorCode']),
    );
  }
}

/// 媒体源（MediaSourceInfo）。
class MediaSource {
  const MediaSource({
    this.id,
    this.name,
    this.container,
    this.path,
    this.protocol,
    this.isRemote = false,
    this.runTimeTicks,
    this.supportsDirectStream = false,
    this.supportsDirectPlay = false,
    this.supportsTranscoding = false,
    this.directStreamUrl,
    this.transcodingUrl,
    this.transcodingSubProtocol,
    this.transcodingContainer,
    this.mediaStreams = const <MediaStream>[],
    this.requiresOpening = false,
    this.requiresClosing = false,
    this.liveStreamId,
    this.bufferMs,
  });

  final String? id;
  final String? name;

  /// 容器格式，如 `mkv`、`mp4`
  final String? container;
  final String? path;

  /// 协议，如 `File`、`Http`、`Rtmp`
  final String? protocol;

  /// 是否为远程源
  final bool isRemote;

  final int? runTimeTicks;

  /// 是否支持直接流
  final bool supportsDirectStream;

  /// 是否支持直接播放
  final bool supportsDirectPlay;

  /// 是否支持转码
  final bool supportsTranscoding;

  /// 直接流地址
  final String? directStreamUrl;

  /// 转码地址
  final String? transcodingUrl;

  /// 转码子协议，如 `hls`
  final String? transcodingSubProtocol;

  /// 转码容器，如 `ts`
  final String? transcodingContainer;

  /// 媒体流（视频/音频/字幕）
  final List<MediaStream> mediaStreams;

  final bool requiresOpening;
  final bool requiresClosing;

  /// 直播流 Id
  final String? liveStreamId;

  /// 缓冲毫秒
  final int? bufferMs;

  factory MediaSource.fromJson(Map<String, dynamic> json) {
    return MediaSource(
      id: _asString(json['Id']),
      name: _asString(json['Name']),
      container: _asString(json['Container']),
      path: _asString(json['Path']),
      protocol: _asString(json['Protocol']),
      isRemote: json['IsRemote'] as bool? ?? false,
      runTimeTicks: (json['RunTimeTicks'] as num?)?.toInt(),
      supportsDirectStream: json['SupportsDirectStream'] as bool? ?? false,
      supportsDirectPlay: json['SupportsDirectPlay'] as bool? ?? false,
      supportsTranscoding: json['SupportsTranscoding'] as bool? ?? false,
      directStreamUrl: _asString(json['DirectStreamUrl']),
      transcodingUrl: _asString(json['TranscodingUrl']),
      transcodingSubProtocol: _asString(json['TranscodingSubProtocol']),
      transcodingContainer: _asString(json['TranscodingContainer']),
      mediaStreams: (json['MediaStreams'] as List<dynamic>?)
              ?.map((dynamic e) => MediaStream.fromJson(e as Map<String, dynamic>))
              .toList() ??
          <MediaStream>[],
      requiresOpening: json['RequiresOpening'] as bool? ?? false,
      requiresClosing: json['RequiresClosing'] as bool? ?? false,
      liveStreamId: _asString(json['LiveStreamId']),
      bufferMs: (json['BufferMs'] as num?)?.toInt(),
    );
  }
}

/// 媒体流（视频/音频/字幕/数据）。
class MediaStream {
  const MediaStream({
    this.index = 0,
    required this.type,
    this.codec,
    this.language,
    this.displayTitle,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    this.deliveryUrl,
    this.width,
    this.height,
    this.bitRate,
    this.channelLayout,
  });

  /// 流索引
  final int index;

  /// 流类型，如 `Video`、`Audio`、`Subtitle`、`Data`
  final String type;

  /// 编解码器，如 `h264`、`aac`
  final String? codec;

  /// 语言，如 `eng`、`chi`
  final String? language;

  /// 显示标题
  final String? displayTitle;

  final bool isDefault;
  final bool isForced;

  /// 是否为外部流（外挂字幕/音轨）
  final bool isExternal;

  /// 外部流交付地址
  final String? deliveryUrl;

  final int? width;
  final int? height;

  /// 码率
  final int? bitRate;

  /// 声道布局，如 `5.1`
  final String? channelLayout;

  factory MediaStream.fromJson(Map<String, dynamic> json) {
    return MediaStream(
      index: (json['Index'] as num?)?.toInt() ?? 0,
      type: _asString(json['Type']) ?? '',
      codec: _asString(json['Codec']),
      language: _asString(json['Language']),
      displayTitle: _asString(json['DisplayTitle']),
      isDefault: json['IsDefault'] as bool? ?? false,
      isForced: json['IsForced'] as bool? ?? false,
      isExternal: json['IsExternal'] as bool? ?? false,
      deliveryUrl: _asString(json['DeliveryUrl']),
      width: (json['Width'] as num?)?.toInt(),
      height: (json['Height'] as num?)?.toInt(),
      bitRate: (json['BitRate'] as num?)?.toInt(),
      channelLayout: _asString(json['ChannelLayout']),
    );
  }
}

/// 远程图片信息（`GET /Items/{Id}/Images` 返回的数组元素）。
///
/// JSON 字段：`ImageType`、`ImageTag`、`Size`、`Width`、`Height`。
class RemoteImageInfo {
  const RemoteImageInfo({
    required this.imageType,
    this.imageTag,
    this.size,
    this.width,
    this.height,
  });

  /// 图片类型，如 `Primary`、`Backdrop`、`Thumb`、`Logo`
  final String imageType;

  /// 图片标签（用于构造图片 URL）
  final String? imageTag;

  /// 文件大小（字节）
  final int? size;

  final int? width;
  final int? height;

  factory RemoteImageInfo.fromJson(Map<String, dynamic> json) {
    return RemoteImageInfo(
      imageType: _asString(json['ImageType']) ?? '',
      imageTag: _asString(json['ImageTag']),
      size: (json['Size'] as num?)?.toInt(),
      width: (json['Width'] as num?)?.toInt(),
      height: (json['Height'] as num?)?.toInt(),
    );
  }
}

// ---------------------------------------------------------------------------
// 播放信息请求与设备配置
// ---------------------------------------------------------------------------

/// POST /Items/{Id}/PlaybackInfo 请求体。
///
/// JSON 字段：`UserId`、`MaxStreamingBitrate`、`StartTimeTicks`、
/// `AudioStreamIndex`、`SubtitleStreamIndex`、`MediaSourceId`、
/// `EnableDirectPlay`、`EnableDirectStream`、`EnableTranscoding`、
/// `IsPlayback`、`AutoOpenLiveStream`、`DeviceProfile`。
class PlaybackInfoRequest {
  const PlaybackInfoRequest({
    this.userId,
    this.maxStreamingBitrate,
    this.startTimeTicks,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.mediaSourceId,
    this.enableDirectPlay,
    this.enableDirectStream,
    this.enableTranscoding,
    this.isPlayback,
    this.autoOpenLiveStream,
    this.allowVideoStreamCopy,
    this.allowAudioStreamCopy,
    this.deviceProfile,
  });

  final String? userId;
  final int? maxStreamingBitrate;
  final int? startTimeTicks;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final String? mediaSourceId;
  final bool? enableDirectPlay;
  final bool? enableDirectStream;
  final bool? enableTranscoding;
  final bool? isPlayback;
  final bool? autoOpenLiveStream;
  final bool? allowVideoStreamCopy;
  final bool? allowAudioStreamCopy;
  final DeviceProfile? deviceProfile;

  Map<String, dynamic> toJson() {
    return _omitNulls(<String, dynamic>{
      'UserId': userId,
      'MaxStreamingBitrate': maxStreamingBitrate,
      'StartTimeTicks': startTimeTicks,
      'AudioStreamIndex': audioStreamIndex,
      'SubtitleStreamIndex': subtitleStreamIndex,
      'MediaSourceId': mediaSourceId,
      'EnableDirectPlay': enableDirectPlay,
      'EnableDirectStream': enableDirectStream,
      'EnableTranscoding': enableTranscoding,
      'IsPlayback': isPlayback,
      'AutoOpenLiveStream': autoOpenLiveStream,
      'AllowVideoStreamCopy': allowVideoStreamCopy,
      'AllowAudioStreamCopy': allowAudioStreamCopy,
      'DeviceProfile': deviceProfile?.toJson(),
    });
  }
}

/// 设备配置（用于协商播放能力）。
///
/// JSON 字段：`Name`、`MaxStreamingBitrate`、`DirectPlayProfiles`、
/// `TranscodingProfiles`、`SubtitleProfiles`。
class DeviceProfile {
  const DeviceProfile({
    this.name,
    this.maxStreamingBitrate,
    this.maxStaticBitrate,
    this.maxStaticMusicBitrate,
    this.directPlayProfiles = const <DirectPlayProfile>[],
    this.transcodingProfiles = const <TranscodingProfile>[],
    this.subtitleProfiles = const <SubtitleProfile>[],
  });

  final String? name;
  final int? maxStreamingBitrate;
  final int? maxStaticBitrate;
  final int? maxStaticMusicBitrate;
  final List<DirectPlayProfile> directPlayProfiles;
  final List<TranscodingProfile> transcodingProfiles;
  final List<SubtitleProfile> subtitleProfiles;

  Map<String, dynamic> toJson() {
    return _omitNulls(<String, dynamic>{
      'Name': name,
      'MaxStreamingBitrate': maxStreamingBitrate,
      'MaxStaticBitrate': maxStaticBitrate,
      'MaxStaticMusicBitrate': maxStaticMusicBitrate,
      'DirectPlayProfiles': directPlayProfiles
          .map((DirectPlayProfile e) => e.toJson())
          .toList(),
      'TranscodingProfiles': transcodingProfiles
          .map((TranscodingProfile e) => e.toJson())
          .toList(),
      'SubtitleProfiles': subtitleProfiles
          .map((SubtitleProfile e) => e.toJson())
          .toList(),
    });
  }
}

/// 直接播放配置子项。
///
/// JSON 字段：`Container`、`Type`、`VideoCodec`、`AudioCodec`。
class DirectPlayProfile {
  const DirectPlayProfile({
    this.container,
    this.type,
    this.videoCodec,
    this.audioCodec,
  });

  final String? container;

  /// 类型，如 `Video`、`Audio`
  final String? type;
  final String? videoCodec;
  final String? audioCodec;

  Map<String, dynamic> toJson() {
    return _omitNulls(<String, dynamic>{
      'Container': container,
      'Type': type,
      'VideoCodec': videoCodec,
      'AudioCodec': audioCodec,
    });
  }
}

/// 转码配置子项。
///
/// JSON 字段：`Container`、`Type`、`VideoCodec`、`AudioCodec`、`Protocol`、
/// `Context`、`MaxAudioChannels`、`MinSegments`、`BreakOnNonKeyFrames`、
/// `DirectPlayProfiles`。
class TranscodingProfile {
  const TranscodingProfile({
    this.container,
    this.type,
    this.videoCodec,
    this.audioCodec,
    this.protocol,
    this.context,
    this.maxAudioChannels,
    this.minSegments,
    this.breakOnNonKeyFrames,
    this.estimateContentLength,
    this.transcodeSeekInfo,
    this.directPlayProfiles = const <DirectPlayProfile>[],
  });

  final String? container;
  final String? type;
  final String? videoCodec;
  final String? audioCodec;
  final String? protocol;

  /// 上下文，如 `Streaming`、`Static`
  final String? context;
  final int? maxAudioChannels;
  final int? minSegments;
  final bool? breakOnNonKeyFrames;
  final bool? estimateContentLength;

  /// 转码寻址信息，如 `Auto`、`Bytes`
  final String? transcodeSeekInfo;
  final List<DirectPlayProfile> directPlayProfiles;

  Map<String, dynamic> toJson() {
    return _omitNulls(<String, dynamic>{
      'Container': container,
      'Type': type,
      'VideoCodec': videoCodec,
      'AudioCodec': audioCodec,
      'Protocol': protocol,
      'Context': context,
      'MaxAudioChannels': maxAudioChannels,
      'MinSegments': minSegments,
      'BreakOnNonKeyFrames': breakOnNonKeyFrames,
      'EstimateContentLength': estimateContentLength,
      'TranscodeSeekInfo': transcodeSeekInfo,
      'DirectPlayProfiles': directPlayProfiles
          .map((DirectPlayProfile e) => e.toJson())
          .toList(),
    });
  }
}

/// 字幕配置子项。
///
/// JSON 字段：`Format`、`Method`、`DidLoad`、`Fallback`。
class SubtitleProfile {
  const SubtitleProfile({
    this.format,
    this.method,
    this.didLoad,
    this.fallback,
  });

  /// 字幕格式，如 `srt`、`ass`、`vtt`
  final String? format;

  /// 交付方式，如 `Encode`、`Embed`、`External`、`Hls`
  final String? method;
  final bool? didLoad;

  /// 回退格式
  final String? fallback;

  Map<String, dynamic> toJson() {
    return _omitNulls(<String, dynamic>{
      'Format': format,
      'Method': method,
      'DidLoad': didLoad,
      'Fallback': fallback,
    });
  }
}

// ---------------------------------------------------------------------------
// 播放上报
// ---------------------------------------------------------------------------

/// 播放开始上报（POST /Sessions/Playing）。
///
/// JSON 字段：`ItemId`、`MediaSourceId`、`PlaySessionId`、`PositionTicks`、
/// `AudioStreamIndex`、`SubtitleStreamIndex`、`PlayMethod`、
/// `MaxStreamingBitrate`、`CanSeek`、`PlaylistItemId`。
class PlaybackStartInfo {
  const PlaybackStartInfo({
    required this.itemId,
    this.mediaSourceId,
    this.playSessionId,
    this.positionTicks,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.playMethod,
    this.maxStreamingBitrate,
    this.canSeek,
    this.playlistItemId,
  });

  final String itemId;
  final String? mediaSourceId;
  final String? playSessionId;
  final int? positionTicks;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;

  /// 播放方式，如 `DirectPlay`、`DirectStream`、`Transcode`
  final String? playMethod;
  final int? maxStreamingBitrate;
  final bool? canSeek;
  final String? playlistItemId;

  Map<String, dynamic> toJson() {
    return _omitNulls(<String, dynamic>{
      'ItemId': itemId,
      'MediaSourceId': mediaSourceId,
      'PlaySessionId': playSessionId,
      'PositionTicks': positionTicks,
      'AudioStreamIndex': audioStreamIndex,
      'SubtitleStreamIndex': subtitleStreamIndex,
      'PlayMethod': playMethod,
      'MaxStreamingBitrate': maxStreamingBitrate,
      'CanSeek': canSeek,
      'PlaylistItemId': playlistItemId,
    });
  }
}

/// 播放进度上报（POST /Sessions/Playing/Progress）。
///
/// JSON 字段：`ItemId`、`MediaSourceId`、`PositionTicks`、`PlaySessionId`、
/// `IsPaused`、`IsMuted`、`AudioStreamIndex`、`SubtitleStreamIndex`、
/// `PlayMethod`、`RepeatMode`、`PlaybackRate`、`PlaylistItemId`。
class PlaybackProgressInfo {
  const PlaybackProgressInfo({
    required this.itemId,
    this.mediaSourceId,
    this.positionTicks,
    this.playSessionId,
    this.isPaused = false,
    this.isMuted = false,
    this.audioStreamIndex,
    this.subtitleStreamIndex,
    this.playMethod,
    this.repeatMode,
    this.playbackRate,
    this.playlistItemId,
  });

  final String itemId;
  final String? mediaSourceId;
  final int? positionTicks;
  final String? playSessionId;

  /// 是否暂停
  final bool isPaused;

  /// 是否静音
  final bool isMuted;
  final int? audioStreamIndex;
  final int? subtitleStreamIndex;
  final String? playMethod;

  /// 重复模式，如 `RepeatNone`、`RepeatAll`、`RepeatOne`
  final String? repeatMode;

  /// 播放速率，正常为 1.0
  final double? playbackRate;
  final String? playlistItemId;

  Map<String, dynamic> toJson() {
    return _omitNulls(<String, dynamic>{
      'ItemId': itemId,
      'MediaSourceId': mediaSourceId,
      'PositionTicks': positionTicks,
      'PlaySessionId': playSessionId,
      'IsPaused': isPaused,
      'IsMuted': isMuted,
      'AudioStreamIndex': audioStreamIndex,
      'SubtitleStreamIndex': subtitleStreamIndex,
      'PlayMethod': playMethod,
      'RepeatMode': repeatMode,
      'PlaybackRate': playbackRate,
      'PlaylistItemId': playlistItemId,
    });
  }
}

/// 播放停止上报（POST /Sessions/Playing/Stopped）。
///
/// JSON 字段：`ItemId`、`MediaSourceId`、`PositionTicks`、`PlaySessionId`、
/// `Failed`、`PlayMethod`、`PlaylistItemId`。
class PlaybackStoppedInfo {
  const PlaybackStoppedInfo({
    required this.itemId,
    this.mediaSourceId,
    this.positionTicks,
    this.playSessionId,
    this.failed = false,
    this.playMethod,
    this.playlistItemId,
  });

  final String itemId;
  final String? mediaSourceId;

  /// 停止时的播放位置（Ticks）
  final int? positionTicks;
  final String? playSessionId;

  /// 是否因错误停止
  final bool failed;
  final String? playMethod;
  final String? playlistItemId;

  Map<String, dynamic> toJson() {
    return _omitNulls(<String, dynamic>{
      'ItemId': itemId,
      'MediaSourceId': mediaSourceId,
      'PositionTicks': positionTicks,
      'PlaySessionId': playSessionId,
      'Failed': failed,
      'PlayMethod': playMethod,
      'PlaylistItemId': playlistItemId,
    });
  }
}
