import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_platform_adapter.dart';
import 'package:tencent_cloud_chat_common/data/message/tencent_cloud_chat_message_data.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_download_utils.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_viewer/tencent_cloud_chat_message_viewer.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_widgets/tencent_cloud_chat_message_item.dart';

// static final int 	V2TIM_IMAGE_TYPE_ORIGIN = 0

// static final int 	V2TIM_IMAGE_TYPE_THUMB = 1

// static final int 	V2TIM_IMAGE_TYPE_LARGE = 2

enum ImageType {
  origin,
  thumb,
  large,
}

enum ImageCurrentRenderType {
  online,
  local,
  path,
}

class ImageCurrentRenderInfo {
  final ImageCurrentRenderType type;
  final String path;

  ImageCurrentRenderInfo({
    required this.path,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return Map.from({
      "type": type.name,
      "path": path,
    });
  }
}

class TencentCloudChatMessageImage extends TencentCloudChatMessageItemBase {
  const TencentCloudChatMessageImage({
    super.key,
    required super.data,
    required super.methods,
  });

  @override
  State<StatefulWidget> createState() => _TencentCloudChatMessageImageState();
}

class _TencentCloudChatMessageImageState extends TencentCloudChatMessageState<TencentCloudChatMessageImage> {
  @override
  void didUpdateWidget(covariant TencentCloudChatMessageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data.sendingMessageData != null) {
      if ((oldWidget.data.sendingMessageData == null || !oldWidget.data.sendingMessageData!.isSendComplete || oldWidget.data.sendingMessageData!.progress != 100) &&
          widget.data.sendingMessageData != null &&
          widget.data.sendingMessageData!.isSendComplete) {
        _getImageUrl();
      }
    }
    // CRITICAL: Check if imageElem.path or imageList.localUrl has changed (for received images)
    // This handles the case where file_done event updates the message path from /tmp/receiving_ to /avatars/
    if (widget.data.message.imageElem != null && oldWidget.data.message.imageElem != null) {
      final oldPath = oldWidget.data.message.imageElem!.path;
      final newPath = widget.data.message.imageElem!.path;
      // Check if path changed (e.g., from /tmp/receiving_ to /avatars/)
      if (oldPath != newPath && newPath != null && (newPath.contains('/avatars/') || newPath.contains('/file_recv/'))) {
        final file = File(newPath);
        if (file.existsSync()) {
          _getImageUrl();
          return;
        }
      }
      // Check if imageList.localUrl changed
      final oldImageList = oldWidget.data.message.imageElem!.imageList;
      final newImageList = widget.data.message.imageElem!.imageList;
      if (oldImageList != newImageList) {
        String? oldLocalUrl;
        String? newLocalUrl;
        if (oldImageList != null) {
          for (final img in oldImageList) {
            if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
              oldLocalUrl = img.localUrl;
              break;
            }
          }
        }
        if (newImageList != null) {
          for (final img in newImageList) {
            if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
              newLocalUrl = img.localUrl;
              break;
            }
          }
        }
        // If localUrl changed from null/empty to a valid path, refresh the image
        if ((oldLocalUrl == null || oldLocalUrl.isEmpty) && newLocalUrl != null && newLocalUrl.isNotEmpty) {
          _getImageUrl();
        }
      }
    }
  }

  final Stream<TencentCloudChatMessageData<dynamic>>? _messageDataStream = TencentCloudChat.instance.eventBusInstance.on<TencentCloudChatMessageData<dynamic>>("TencentCloudChatMessageData");
  late StreamSubscription<TencentCloudChatMessageData<dynamic>>? __messageDataSubscription;
  final String _tag = "TencentCloudChatMessageImage";

  bool isErrorMessage = false;

  bool? onlineRenderResult;
  static int onlineRenderKey = 0;

  int renderRandom = Random().nextInt(100000);

  ImageCurrentRenderInfo? currentRenderImageInfo;

  console(String log) {
    TencentCloudChat.instance.logInstance.console(
      componentName: _tag,
      logs: json.encode(
        {
          "msgID": widget.data.message.msgID,
          "log": log,
        },
      ),
    );
  }

  Map<String, dynamic>? setLocalDelayData;

  DownloadMessageQueueData generateDownloadData({
    required int type,
    required int conversationType,
    required String key,
    V2TimMessage? message,
  }) {
    message ??= widget.data.message;
    return DownloadMessageQueueData(
      conversationType: conversationType,
      msgID: message.msgID ?? "",
      messageType: MessageElemType.V2TIM_ELEM_TYPE_IMAGE,
      imageType: type,
      // download origin image
      isSnapshot: false,
      key: key,
      convID: key,
    );
  }

  addDownloadMessageToQueue({
    required bool isOrigin,
  }) {
    if (isSendingMessage()) {
      console("message is sending. download break.");
      return;
    }

    bool hasLocalImagePath = hasLocalImage(isOrigin: isOrigin);
    if (hasLocalImagePath) {
      console("message has local url. isOrigin:${isOrigin}.");
      return;
    }

    if (TencentCloudChatUtils.checkString(widget.data.message.msgID) != null) {
      String key = TencentCloudChatUtils.checkString(widget.data.message.userID) ?? widget.data.message.groupID ?? "";
      int conversationType = TencentCloudChatUtils.checkString(widget.data.message.userID) == null ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C;
      if (key.isEmpty) {
        console("add to download queue error. key is empty.");
        return;
      }

      int type = ImageType.thumb.index;
      if (isOrigin) {
        type = ImageType.origin.index;
      }

      TencentCloudChatDownloadUtils.addDownloadMessageToQueue(
        data: generateDownloadData(type: type, conversationType: conversationType, key: key),
      );
    }
  }

  bool isSendingMessage() {
    if (widget.data.message.status == 1) {
      return true;
    }
    return false;
  }

  Future<bool> hasSelfClientPath() async {
    if (widget.data.message.imageElem != null && !TencentCloudChatPlatformAdapter().isWeb) {
      if (TencentCloudChatUtils.checkString(widget.data.message.imageElem!.path) != null) {
        final path = widget.data.message.imageElem!.path!;
        // CRITICAL: Don't use /tmp/receiving_ paths as client path - they are temporary
        if (!path.startsWith('/tmp/receiving_') && File(path).existsSync()) {
          return true;
        }
      }
    }
    return false;
  }

  bool hasLocalImage({
    bool? isOrigin,
  }) {
    bool res = false;
    if (widget.data.message.imageElem != null && !TencentCloudChatPlatformAdapter().isWeb) {
      V2TimImageElem images = widget.data.message.imageElem!;
      String localUrl = "";
      List<V2TimImage?> imageLists = images.imageList ?? [];
      if (imageLists.isNotEmpty) {
        for (var i = 0; i < imageLists.length; i++) {
          V2TimImage? image = imageLists[i];
          if (image != null) {
            int type = isOrigin == true ? ImageType.origin.index : ImageType.thumb.index;
            if (image.type == type) {
              if (TencentCloudChatUtils.checkString(image.localUrl) != null) {
                localUrl = image.localUrl!;
              }
              break;
            }
          }
        }
      }
      if (localUrl.isNotEmpty && File(localUrl).existsSync()) {
        res = true;
      }
    }

    return res;
  }

  String getRenderLocalUrlFormImageElem(V2TimImageElem image, int type) {
    String res = '';
    if (image.imageList != null) {
      if (image.imageList!.isNotEmpty) {
        for (var i = 0; i < image.imageList!.length; i++) {
          var img = image.imageList![i];
          if (img != null) {
            if (img.type == type) {
              if (img.localUrl != null) {
                if (img.localUrl!.isNotEmpty) {
                  res = img.localUrl!;
                }
              }
            }
          }
        }
      }
    }
    return res;
  }

  String getOnlineThumbUrl() {
    var res = '';
    var imgElem = widget.data.message.imageElem!;
    var imgList = imgElem.imageList ?? [];
    for (var i = 0; i < imgList.length; i++) {
      var img = imgList[i];
      if (img != null) {
        if (img.type == ImageType.thumb.index) {}
        if (img.url != null) {
          if (img.url!.isNotEmpty) {
            // CRITICAL: Don't use /tmp/receiving_ paths as URL - they are temporary and will fail when used as online URLs
            if (!img.url!.startsWith('/tmp/receiving_')) {
              res = img.url!;
            }
          }
        }
      }
    }
    return res;
  }

  _getImageUrl() async {
    if (TencentCloudChatUtils.checkString(widget.data.message.msgID) != null) {
      // check if exits local url . if not get online url

      bool hasLocal = hasLocalImage();
      bool hasClientPath = await hasSelfClientPath();
      console("hasLocal: $hasLocal, hasClientPath: $hasClientPath");
      if (hasClientPath) {
        var imageInfo = ImageCurrentRenderInfo(path: widget.data.message.imageElem!.path!, type: ImageCurrentRenderType.path);
        safeSetState(() {
          currentRenderImageInfo = imageInfo;
        });

        console("message has self local path. render by path");
      } else if (hasLocal) {
        var localUrl = getRenderLocalUrlFormImageElem(widget.data.message.imageElem!, ImageType.thumb.index);
        var imageInfo = ImageCurrentRenderInfo(path: localUrl, type: ImageCurrentRenderType.local);
        safeSetState(() {
          currentRenderImageInfo = imageInfo;
        });

        console("message has localUrl. render by local.");
      } else if (widget.data.message.imageElem != null) {
        var thumbUrl = getOnlineThumbUrl();
        // CRITICAL: Don't use /tmp/receiving_ paths as online URL - they are temporary and will fail
        if (thumbUrl.isNotEmpty && !thumbUrl.startsWith('/tmp/receiving_')) {
          var imageInfo = ImageCurrentRenderInfo(path: thumbUrl, type: ImageCurrentRenderType.online);
          safeSetState(() {
            currentRenderImageInfo = imageInfo;
          });

          console("message render by online url.");
        } else if (thumbUrl.startsWith('/tmp/receiving_')) {
          // If URL is a temporary path, don't try to render it as online URL
          // The image will be updated when file_done event updates the path
          console("message has temporary receiving path, waiting for file_done event. url: $thumbUrl");
        }
      } else {
        safeSetState(() {
          isErrorMessage = true;
        });
      }
    } else {
      safeSetState(() {
        isErrorMessage = true;
      });
    }
  }

  // --- Local decode retry -------------------------------------------------
  //
  // A RECEIVED image is a race: the transfer lands the bytes and the message's
  // path is republished, but a decode attempted in the same beat can still hit
  // an absent / half-written file. `Image` resolves its provider ONCE per
  // provider identity, and `FileImage(File(p))` for the same `p` compares equal
  // — so a single unlucky failure sticks: the bubble shows the error
  // placeholder forever (the user has to leave and re-enter the chat), and the
  // tappable image is replaced by the placeholder's own InkWell, which is why
  // the full-screen viewer could not be opened from it at all.
  //
  // Fix: on a local decode error, EVICT the cached provider for that file and
  // rebuild with a bumped nonce (so `Image` resolves a fresh provider), a
  // bounded number of times with backoff. A genuinely unreadable file still
  // settles into the error placeholder after the last attempt — this only
  // recovers the transient case, and it never loops.
  // Budget: 8 attempts with backoff capped at 2 s covers ~13 s after the first
  // failure. Measured live (iPhone/iPad Simulator, 2026-08-16): a 4-attempt /
  // ~4.5 s window recovered the bubble in ONE of two runs and ran out in the
  // other, so the shorter budget turned a real self-heal into a coin flip. A
  // genuinely unreadable file still settles into the error placeholder, and the
  // re-decodes are cheap and strictly bounded.
  static const int _kLocalDecodeRetryLimit = 8;
  static const int _kLocalDecodeRetryMaxDelayMs = 2000;
  int _localDecodeRetries = 0;
  int _localRenderNonce = 0;
  String? _localDecodeRetryPath;
  Timer? _localDecodeRetryTimer;

  void _scheduleLocalDecodeRetry(String path) {
    if (path.isEmpty) return;
    // A different file resets the budget (a new message, or a temp -> final
    // path swap); the same file keeps counting down.
    if (_localDecodeRetryPath != path) {
      _localDecodeRetryPath = path;
      _localDecodeRetries = 0;
    }
    if (_localDecodeRetries >= _kLocalDecodeRetryLimit) return;
    if (_localDecodeRetryTimer != null) return;
    final attempt = _localDecodeRetries;
    final delayMs = attempt >= 8
        ? _kLocalDecodeRetryMaxDelayMs
        : min(300 << attempt, _kLocalDecodeRetryMaxDelayMs);
    _localDecodeRetryTimer = Timer(Duration(milliseconds: delayMs), () async {
      _localDecodeRetryTimer = null;
      _localDecodeRetries = attempt + 1;
      try {
        await FileImage(File(path)).evict();
      } catch (e) {
        // evict() only touches the cache; a failure here must not kill the retry.
      }
      if (!mounted) return;
      // Re-resolve the SOURCE as well as the decode. A local failure is just as
      // likely to be a STALE path — the receive-side temp file the transfer
      // deleted after moving it — as a half-written one, and `_getImageUrl`
      // re-reads the elem and re-checks `existsSync` for both candidates.
      _getImageUrl();
      safeSetState(() {
        _localRenderNonce++;
      });
    });
  }

  @override
  void deactivate() {
    _localDecodeRetryTimer?.cancel();
    _localDecodeRetryTimer = null;
    super.deactivate();
  }

  Widget renderLocalImage(String path) {
    console("render local image. path: $path");
    return ClipRRect(
      // Automation anchor (`ForkUiKeys.messageImageRenderPath`): the key CARRIES
      // the path being decoded, so a driver that knows the message's expected
      // file can ask "is the widget even looking at it?" with one probe. Without
      // it a decode-error red cannot distinguish an undecodable file from a
      // STALE path (the receive-side temp file, deleted once the transfer moved
      // it) — two different bugs in two different layers.
      key: ValueKey('message_image_render_path:$path'),
      borderRadius: BorderRadius.all(Radius.circular(getSquareSize(12))),
      child: Image.file(
        // Nonce-keyed so a retry after `evict()` actually re-resolves: `Image`
        // keeps its resolved stream when the provider compares equal, and
        // FileImage equality is (path, scale) only.
        key: ValueKey('$path#$_localRenderNonce'),
        fit: BoxFit.cover,
        width: _imageWidth(),
        File(path),
        errorBuilder: (context, error, stackTrace) {
          console("local image render failed. please check the path is right. path: $path");
          _scheduleLocalDecodeRetry(path);
          return getErrorWidget();
        },
      ),
    );
  }

  getLoadingWidget() {
    // Live theme colours (mode-accurate) without a builder param: same source
    // the TencentCloudChatThemeWidget itself reads from.
    final colorTheme = TencentCloudChat.instance.dataInstance.theme.colorTheme;
    double placeholderWidth = _imageWidth();
    double placeholderHeight = placeholderWidth * 1.33;
    return Container(
      // Automation anchor (`ForkUiKeys.messageImageLoading`): tells a driver
      // "still decoding" apart from "decode FAILED" — both placeholders have
      // the same geometry, so a bounds probe cannot distinguish them and a
      // failing case could only report "the viewer did not open".
      key: ValueKey('message_image_loading:${_imageStateKeyId}'),
      width: getWidth(placeholderWidth),
      height: getHeight(placeholderHeight),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(getSquareSize(12))),
        color: Colors.transparent,
      ),
      child: Center(
        child: SizedBox(
          width: getWidth(20),
          height: getHeight(20),
          child: CircularProgressIndicator(
            strokeWidth: 1,
            color: colorTheme.secondaryTextColor,
          ),
        ),
      ),
    );
  }

  getErrorWidget() {
    console("render image error");
    final colorTheme = TencentCloudChat.instance.dataInstance.theme.colorTheme;
    double placeholderWidth = _imageWidth();
    double placeholderHeight = placeholderWidth * 1.33;
    return InkWell(
      // Automation anchor (`ForkUiKeys.messageImageError`). Its presence is the
      // machine-readable statement "this bubble is showing the DECODE-ERROR
      // placeholder", which is also why the image is untappable: this InkWell
      // wins the gesture arena over the image's parent GestureDetector, so the
      // viewer cannot be opened from an errored bubble no matter how the tap is
      // aimed.
      key: ValueKey('message_image_error:${_imageStateKeyId}'),
      onTap: () {
        if (onlineRenderResult != null && onlineRenderResult == false) {
          onlineRenderResult = true;
          onlineRenderKey++;
          _getImageUrl();
        }
        // A LOCAL decode failure has no url to re-fetch; give the user the same
        // manual escape hatch the automatic retry uses (evict + re-resolve).
        final localPath = currentRenderImageInfo?.path ?? '';
        if (localPath.isNotEmpty) {
          _localDecodeRetries = 0;
          _scheduleLocalDecodeRetry(localPath);
        }
      },
      child: Container(
        width: getWidth(placeholderWidth),
        height: getHeight(placeholderHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(getSquareSize(12))),
          // Theme-driven neutral placeholder fill (secondary text @ ~20%).
          color: colorTheme.secondaryTextColor.withOpacity(0.2),
        ),
        child: Center(
          child: SizedBox(
            width: getWidth(20),
            height: getHeight(20),
            child: const Icon(
              Icons.error,
              color: Color(0xFFD32F2F),
            ),
          ),
        ),
      ),
    );
  }

  bool _isLocalFilePath(String url) {
    if (url.isEmpty) return false;
    if (url.startsWith('http://') || url.startsWith('https://') || url.startsWith('//')) return false;
    if (url.startsWith('/')) return true;
    // Windows absolute path (e.g. C:\Users\...)
    if (url.length > 2 && url[1] == ':') return true;
    return false;
  }

  Widget renderOnlineImage(String url) {
    console("render online image. url: $url");
    if (_isLocalFilePath(url)) {
      return ClipRRect(
        // See renderLocalImage: the key carries the decoded path.
        key: ValueKey('message_image_render_path:$url'),
        borderRadius: BorderRadius.all(Radius.circular(getSquareSize(12))),
        child: Image.file(
          File(url),
          key: ValueKey('$onlineRenderKey#$url#$_localRenderNonce'),
          fit: BoxFit.cover,
          width: _imageWidth(),
          errorBuilder: (context, error, stackTrace) {
            console("local image render failed. path: $url");
            // Same transient-decode recovery as renderLocalImage: this branch
            // also renders a LOCAL file (a local path that reached the "online"
            // slot), so it hits the identical race.
            _scheduleLocalDecodeRetry(url);
            return getErrorWidget();
          },
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.all(Radius.circular(getSquareSize(12))),
      child: CachedNetworkImage(
          key: ValueKey(onlineRenderKey),
          imageUrl: url,
          fit: BoxFit.cover,
          width: _imageWidth(),
          errorWidget: (context, error, stackTrace) {
            console("network image render failed. please check the path is right. url: $url");
            onlineRenderResult = false;
            return getErrorWidget();
          },
          progressIndicatorBuilder: (context, child, loadingProgress) {
            return getLoadingWidget();
          },
        ),
    );
  }

  showImage() {
    String convkey = TencentCloudChatUtils.checkString(widget.data.message.userID) ?? widget.data.message.groupID ?? "";
    int conversationType = TencentCloudChatUtils.checkString(widget.data.message.userID) == null ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C;
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return TencentCloudChatMessageViewer(
          convKey: convkey,
          message: widget.data.message,
          convType: conversationType,
          isSending: widget.data.message.status == 1,
        );
      },
    );
  }

  int onTapDownTime = 0;

  onTapDown(TapDownDetails details) {
    if (!widget.data.inSelectMode) {
      onTapDownTime = DateTime.now().millisecondsSinceEpoch;
    }
  }

  onTapUp(TapUpDetails details) {
    if (widget.data.inSelectMode) {
      return;
    }
    int onTapUpTime = DateTime.now().millisecondsSinceEpoch;
    if (onTapUpTime - onTapDownTime > 300 && onTapDownTime > 0) {
      console("tap to long break.");
      return;
    }
    if (widget.data.renderOnMenuPreview) {
      return;
    }
    onTapDownTime = 0;
    showImage();
  }

  /// Automation anchor for the TAPPABLE image bubble (see
  /// `lib/ui/testing/ui_keys_fork.dart`, `ForkUiKeys.messageImageBubble`).
  ///
  /// WHY IT IS NEEDED. The only handle automation had on an image message was
  /// the ROW key (`message_list_item:<id>`, attached in
  /// tencent_cloud_chat_message_row_container.dart). A row spans the whole chat
  /// pane while the bubble is alignment-offset and capped at
  /// `min(messageRowWidth * 0.7, 198)`, so opening the viewer meant guessing
  /// fractions of the row's width — and, worse, the row key sits on a plain
  /// StatefulWidget that flutter_skill's `interactiveStructured` never reports,
  /// so a bounds lookup through that API returned NOTHING and the retry ladder
  /// dispatched zero taps (the deterministic
  /// `message_viewer_save_and_zoom_surface` red on both iPhone and iPad).
  /// Keying the GestureDetector itself gives a single unambiguous tap target
  /// whose presence ALSO proves the decode resolved — the error/loading
  /// placeholders are different subtrees and carry no such key.
  ///
  /// Mirrors the row container's id fallback so the key is stable before the
  /// server assigns a msgID.
  String get _imageStateKeyId {
    final m = widget.data.message;
    return m.msgID ?? m.id ?? '${m.timestamp}_${m.sender ?? 'unknown'}';
  }

  String get _imageBubbleKey => 'message_image_bubble:$_imageStateKeyId';

  Widget renderImage() {
    if (!TencentCloudChatPlatformAdapter().isWeb && (currentRenderImageInfo?.type == ImageCurrentRenderType.path || currentRenderImageInfo?.type == ImageCurrentRenderType.local)) {
      return GestureDetector(
        key: ValueKey(_imageBubbleKey),
        onTapDown: onTapDown,
        onTapUp: onTapUp,
        child: renderLocalImage(currentRenderImageInfo?.path ?? ""),
      );
    } else {
      return GestureDetector(
        key: ValueKey(_imageBubbleKey),
        onTapDown: onTapDown,
        onTapUp: onTapUp,
        child: renderOnlineImage(currentRenderImageInfo?.path ?? ""),
      );
    }
  }

  Widget imageLayout() {
    if (currentRenderImageInfo == null) {
      return getLoadingWidget();
    }
    if (isErrorMessage) {
      return getErrorWidget();
    } else {
      return renderImage();
    }
  }

  Widget messageInfo() {
    return Row(
      mainAxisAlignment: sentFromSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!sentFromSelf)
          SizedBox(
            width: getWidth(4),
          ),
        if (sentFromSelf) messageStatusIndicator(),
        messageTimeIndicator(
          textColor: Colors.white,
          shadow: [
            const Shadow(
              color: Colors.black,
              offset: Offset(2, 2),
              blurRadius: 4,
            ),
          ],
        ),
        if (sentFromSelf)
          SizedBox(
            width: getWidth(8),
          ),
      ],
    );
  }

  DownloadMessageQueueData? currentDownloadData;

  handleDownloadEvent(TencentCloudChatMessageData data) {
    if (data.currentUpdatedFields == TencentCloudChatMessageDataKeys.downloadMessage) {
      String key = TencentCloudChatUtils.checkString(widget.data.message.userID) ?? widget.data.message.groupID ?? "";
      int conversationType = TencentCloudChatUtils.checkString(widget.data.message.userID) == null ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C;
      if (key.isEmpty) {
        console("add to download queue error. key is empty.");
        return false;
      }
      bool hasThumbLocal = hasLocalImage();
      bool hasOriginLocal = hasLocalImage(isOrigin: true);
      int type = ImageType.thumb.index;
      if (!hasOriginLocal && hasThumbLocal) {
        type = ImageType.origin.index;
      }

      int idx = data.currentDownloadMessage.indexWhere((ele) => ele.getUniqueueKey() == generateDownloadData(type: type, conversationType: conversationType, key: key).getUniqueueKey());

      if (idx > -1) {
        safeSetState(() {
          currentDownloadData = data.currentDownloadMessage[idx];
        });
      }
    } else if (data.currentUpdatedFields == TencentCloudChatMessageDataKeys.networkConnectSuccess) {
        if (onlineRenderResult != null && onlineRenderResult == false) {
          onlineRenderResult = true;
          onlineRenderKey++;
          _getImageUrl();
        }
    }
  }

  void addDownloadListener() {
    __messageDataSubscription = _messageDataStream?.listen(handleDownloadEvent);
  }

  bool isDownloading() {
    if (TencentCloudChatUtils.checkString(widget.data.message.msgID) != null) {
      String key = TencentCloudChatUtils.checkString(widget.data.message.userID) ?? widget.data.message.groupID ?? "";
      int conversationType = TencentCloudChatUtils.checkString(widget.data.message.userID) == null ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C;
      if (key.isEmpty) {
        console("add to download queue error. key is empty.");
        return false;
      }
      bool hasThumbLocal = hasLocalImage();
      bool hasOriginLocal = hasLocalImage(isOrigin: true);
      int type = ImageType.thumb.index;
      if (!hasOriginLocal && hasThumbLocal) {
        type = ImageType.origin.index;
        console("thumb has been download . download origin local");
      }
      return TencentCloudChatDownloadUtils.isDownloading(data: generateDownloadData(type: type, conversationType: conversationType, key: key));
    }
    return false;
  }

  bool isInDownloadQueue() {
    if (TencentCloudChatUtils.checkString(widget.data.message.msgID) != null) {
      String key = TencentCloudChatUtils.checkString(widget.data.message.userID) ?? widget.data.message.groupID ?? "";
      int conversationType = TencentCloudChatUtils.checkString(widget.data.message.userID) == null ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C;
      if (key.isEmpty) {
        console("add to download queue error. key is empty.");
        return false;
      }
      bool hasThumbLocal = hasLocalImage();
      bool hasOriginLocal = hasLocalImage(isOrigin: true);
      int type = ImageType.thumb.index;
      if (!hasOriginLocal && hasThumbLocal) {
        type = ImageType.origin.index;
        console("thumb has been download . download origin local");
      }
      return TencentCloudChatDownloadUtils.isInDownloadQueue(data: generateDownloadData(type: type, conversationType: conversationType, key: key));
    }
    return false;
  }

  removeFromDownloadQueue() {
    bool inQueue = isInDownloadQueue();
    if (inQueue == true && TencentCloudChatUtils.checkString(widget.data.message.msgID) != null) {
      String key = TencentCloudChatUtils.checkString(widget.data.message.userID) ?? widget.data.message.groupID ?? "";
      int conversationType = TencentCloudChatUtils.checkString(widget.data.message.userID) == null ? ConversationType.V2TIM_GROUP : ConversationType.V2TIM_C2C;
      if (key.isEmpty) {
        console("add to download queue error. key is empty.");
        return false;
      }
      bool hasThumbLocal = hasLocalImage();
      bool hasOriginLocal = hasLocalImage(isOrigin: true);
      int type = ImageType.thumb.index;
      if (!hasOriginLocal && hasThumbLocal) {
        type = ImageType.origin.index;
        console("thumb has been download . download origin local");
      }
      TencentCloudChatDownloadUtils.removeFromDownloadQueue(data: generateDownloadData(type: type, conversationType: conversationType, key: key));
      safeSetState(() {
        renderRandom = Random().nextInt(10000);
      });
    }
  }

  Widget getDownloadingWidget({
    required double progress,
    bool? inQueue,
  }) {
    if (progress == 0) {
      return SizedBox(
        width: getSquareSize(22),
        height: getSquareSize(22),
        child: const CircularProgressIndicator(
          strokeWidth: 2,
        ),
      );
    }
    return GestureDetector(
      onTap: removeFromDownloadQueue,
      child: SizedBox(
        width: getSquareSize(22),
        height: getSquareSize(22),
        child: CircularProgressIndicator(
          value: progress,
          backgroundColor: Colors.transparent,
          // Brand blue (#3370FF == colorTheme.primaryColor, identical in light
          // & dark); const here as this helper has no `colorTheme` in scope.
          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3370FF)),
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget downloadStatus() {
    // TODO use theme color

    Widget needDownload = GestureDetector(
      onTap: () {
        addDownloadMessageToQueue(isOrigin: true);
        setState(() {
          renderRandom = Random().nextInt(100000);
        });
      },
      child: Icon(
        Icons.download_for_offline_outlined,
        color: Colors.white,
        size: getSquareSize(20),
      ),
    );

    late Widget finalRenderDownloadStatusWidget;

    if ((hasLocalImage() && hasLocalImage(isOrigin: true)) || isErrorMessage || isSendingMessage() || TencentCloudChatUtils.checkString(widget.data.message.id) != null) {
      return Container();
    } else {
      if (isDownloading()) {
        finalRenderDownloadStatusWidget = getDownloadingWidget(
          progress: currentDownloadData == null ? 0 : (currentDownloadData!.downloadFinish ? 1 : (currentDownloadData!.currentDownloadSize / (currentDownloadData!.totalSize == 0 ? 1 : currentDownloadData!.totalSize))),
        );
      } else if (isInDownloadQueue()) {
        finalRenderDownloadStatusWidget = getDownloadingWidget(progress: 0);
      } else {
        finalRenderDownloadStatusWidget = needDownload;
      }
    }
    return Container(
      width: getSquareSize(20),
      height: getSquareSize(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.all(
          Radius.circular(getSquareSize(15)),
        ),
        color: Colors.black.withOpacity((hasLocalImage() || currentDownloadData?.downloadFinish == true) ? 0 : 0.2),
      ),
      child: finalRenderDownloadStatusWidget,
    );
  }

  bool canrender = false;

  @override
  void initState() {
    super.initState();
    console(widget.data.message.imageElem?.toJson().toString() ?? "no image info");
    _getImageUrl();
    if (!TencentCloudChatPlatformAdapter().isWeb) {
      addDownloadListener();
      addDownloadMessageToQueue(isOrigin: false);
    }
  }

  @override
  void dispose() {
    super.dispose();
    if (!TencentCloudChatPlatformAdapter().isWeb) {
      __messageDataSubscription?.cancel();
    }
  }

  // Bubble interior width measured by the LayoutBuilder in defaultBuilder;
  // infinite until the first layout.
  double _bubbleInnerMaxWidth = double.infinity;

  // On a 320 px phone with both avatar slots reserved the bubble interior is
  // ~186 px, so the bare 198 px cap overflowed; bound by the measured interior.
  double _imageWidth() {
    final double capped = min(widget.data.messageRowWidth * 0.7, 198).toDouble();
    return _bubbleInnerMaxWidth.isFinite ? min(capped, _bubbleInnerMaxWidth) : capped;
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    final maxBubbleWidth = widget.data.messageRowWidth * 0.8;
    return LayoutBuilder(builder: (context, constraints) {
      // Bubble padding (4+4) and border (1+1) come off the incoming width.
      _bubbleInnerMaxWidth = constraints.maxWidth.isFinite
          ? max(0.0, constraints.maxWidth - getWidth(4) * 2 - 2)
          : double.infinity;
      return TencentCloudChatThemeWidget(build: (context, colorTheme, textStyle) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: getWidth(4), vertical: getHeight(4)),
        decoration: BoxDecoration(
          color: showHighlightStatus ? colorTheme.info : (sentFromSelf ? colorTheme.selfMessageBubbleColor : colorTheme.othersMessageBubbleColor),
          border: Border.all(
            color: sentFromSelf ? colorTheme.selfMessageBubbleBorderColor : colorTheme.othersMessageBubbleBorderColor,
          ),
          borderRadius: BorderRadius.all(Radius.circular(getSquareSize(12))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                  Stack(
                    children: [
                      Positioned(
                        child: imageLayout(),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        left: 0,
                        child: messageInfo(),
                      ),
                      if (!TencentCloudChatPlatformAdapter().isWeb)
                        Positioned(
                          top: getHeight(4),
                          left: getWidth(4),
                          child: downloadStatus(),
                        )
                    ],
                  ),
              ],
            ),
            messageReactionList(),
          ],
        ),
      );
      });
    });
  }
}
