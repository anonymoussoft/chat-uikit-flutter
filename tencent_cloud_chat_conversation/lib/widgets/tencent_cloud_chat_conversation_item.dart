import 'dart:math';

import 'package:adaptive_action_sheet/adaptive_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/color_base.dart';
import 'package:tencent_cloud_chat_common/data/theme/text_style/text_style.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_navigator.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/builders/tencent_cloud_chat_common_builders.dart';
import 'package:tencent_cloud_chat_common/utils/face_manager.dart';
import 'package:tencent_cloud_chat_common/widgets/avatar/tencent_cloud_chat_avatar.dart';
import 'package:tencent_cloud_chat_common/widgets/desktop_popup/tencent_cloud_chat_desktop_popup.dart';
import 'package:tencent_cloud_chat_common/widgets/gesture/tencent_cloud_chat_gesture.dart';
import 'package:tencent_cloud_chat_conversation/model/tencent_cloud_chat_conversation_presenter.dart';

class TencentCloudChatConversationItem extends StatefulWidget {
  final V2TimConversation conversation;
  final bool isOnline;
  final bool isSelected;

  const TencentCloudChatConversationItem({
    super.key,
    required this.conversation,
    required this.isOnline,
    this.isSelected = false,
  });

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatConversationItemState();
}

class TencentCloudChatConversationItemState
    extends TencentCloudChatState<TencentCloudChatConversationItem> {
  bool get useDesktopMode {
    final config =
        TencentCloudChat.instance.dataInstance.conversation.conversationConfig;
    return config.useDesktopMode &&
        (TencentCloudChatScreenAdapter.deviceScreenType ==
                DeviceScreenType.desktop ||
            config.forceDesktopLayout);
  }

  TencentCloudChatConversationPresenter conversationPresenter =
      TencentCloudChatConversationPresenter();

  _navigateToMessage() async {
    final options = TencentCloudChatMessageOptions(
      userID: widget.conversation.groupID == null
          ? widget.conversation.userID
          : null,
      groupID: widget.conversation.groupID,
      draftText: widget.conversation.draftText,
    );

    final res = await TencentCloudChat.instance.dataInstance.conversation
            .conversationEventHandlers?.uiEventHandlers.onTapConversationItem
            ?.call(
          conversation: widget.conversation,
          messageOptions: options,
          inDesktopMode: useDesktopMode,
        ) ??
        false;
    if (res) {
      return;
    }

    if (useDesktopMode &&
        TencentCloudChat.instance.dataInstance.basic.usedComponents
            .contains(TencentCloudChatComponentsEnum.message)) {
      // Desktop combined navigator
      TencentCloudChat.instance.dataInstance.conversation.currentConversation =
          widget.conversation;
    } else if (TencentCloudChat.instance.dataInstance.basic.usedComponents
        .contains(TencentCloudChatComponentsEnum.message)) {
      // Mobile navigator
      navigateToMessage(
        context: context,
        options: options,
      );
    } else {
      // Custom onTap event
    }
  }

  isPin() {
    return widget.conversation.isPinned ?? false;
  }

  Future<void> _handleSecondaryTap(
      TapDownDetails details, bool isDesktopScreen) async {
    final handler = TencentCloudChat
        .instance
        .dataInstance
        .conversation
        .conversationEventHandlers
        ?.uiEventHandlers
        .onSecondaryTapConversationItem;
    final handled = await handler?.call(
          conversation: widget.conversation,
          position: details.globalPosition,
        ) ??
        false;
    if (handled) {
      return;
    }
    if (isDesktopScreen) {
      _showDesktopMenu(details);
    }
  }

  Future<void> _handleLongPress(
    LongPressStartDetails startDetails,
    bool isDesktopScreen,
    BuildContext actionContext,
    TencentCloudChatTextStyle fontSize,
    TencentCloudChatThemeColors colors,
  ) async {
    // `LongPressStartDetails.globalPosition` is reliable on both touch and
    // desktop mouse, unlike caching the last `onTapDown` (mouse long-press
    // does not always fire `onTapDown` first, which previously left the
    // cached value null and anchored the menu at `Offset.zero`).
    final position = startDetails.globalPosition;
    final handler = TencentCloudChat.instance.dataInstance.conversation
        .conversationEventHandlers?.uiEventHandlers.onLongPressConversationItem;
    final handled = await handler?.call(
          conversation: widget.conversation,
          position: position,
        ) ??
        false;
    if (handled) {
      return;
    }
    if (!isDesktopScreen) {
      await showMoreItemAction(actionContext, fontSize, colors);
      return;
    }
    _showDesktopMenu(TapDownDetails(globalPosition: position));
  }

  _showDesktopMenu(TapDownDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;

    final items = [
      TencentCloudChatMessageGeneralOptionItem(
        label: isPin() ? tL10n.unpin : tL10n.pin,
        onTap: _pinConversation,
      ),
      TencentCloudChatMessageGeneralOptionItem(
        label: tL10n.markAsRead,
        onTap: _markAsRead,
      ),
      TencentCloudChatMessageGeneralOptionItem(
        label: tL10n.hide,
        onTap: _hideConversation,
      ),
      TencentCloudChatMessageGeneralOptionItem(
        label: tL10n.delete,
        onTap: _deleteConversation,
      ),
    ];

    final tapDetails = details;
    // Keep the menu on screen: 38 ≈ one column-menu row (14 px label + 8 px
    // vertical padding), 350 is the column menu's max width.
    final double dy = max(
            8.0,
            min(tapDetails.globalPosition.dy,
                screenHeight - (items.length * 38)))
        .toDouble();
    final double dx = max(
            8.0,
            min(tapDetails.globalPosition.dx + 10,
                MediaQuery.of(context).size.width - 350 - 8))
        .toDouble();

    TencentCloudChatDesktopPopup.showColumnMenu(
      context: context,
      offset: Offset(dx, dy),
      items: items,
    );
  }

  _markAsRead({Offset? offset}) {
    TencentCloudChat.instance.chatSDKInstance.manager
        .getConversationManager()
        .cleanConversationUnreadMessageCount(
          conversationID: widget.conversation.conversationID,
          cleanTimestamp: 0,
          cleanSequence: 0,
        );
  }

  showMoreItemAction(BuildContext context, TencentCloudChatTextStyle fontSize,
      TencentCloudChatThemeColors colors) async {
    TextStyle style = TextStyle(
      fontSize: fontSize.fontsize_16,
      fontWeight: FontWeight.w400,
      color: colors.conversationItemMoreActionItemNormalTextColor,
    );
    TextStyle deleteStyle = TextStyle(
      fontSize: fontSize.fontsize_16,
      fontWeight: FontWeight.w400,
      color: colors.conversationItemMoreActionItemDeleteTextColor,
    );
    TextStyle cancelStyle = TextStyle(
      fontSize: fontSize.fontsize_16,
      fontWeight: FontWeight.w600,
      color: colors.conversationItemMoreActionItemNormalTextColor,
    );
    // One-shot guard against a double-fired action (real fast double-tap or a
    // test harness that dispatches a synthetic pointer AND directly invokes
    // onPressed). Without it the second `hideMoreItemAction()` pop unwinds the
    // page under the sheet and blanks the app. These callbacks capture the
    // State context (not the sheet builder context), so a one-shot flag at the
    // call site is the right tool rather than `popDialogIfCurrent`.
    var handled = false;
    final actions = <BottomSheetAction>[
      BottomSheetAction(
          title: Text(
            tL10n.hide,
            style: style,
          ),
          onPressed: (context) async {
            if (handled) return;
            handled = true;
            await _hideConversation();
            hideMoreItemAction();
          }),
      BottomSheetAction(
          title: Text(
            tL10n.delete,
            style: deleteStyle,
          ),
          onPressed: (context) async {
            if (handled) return;
            handled = true;
            await _deleteConversation();
            hideMoreItemAction();
          }),
    ];

    if (widget.conversation.unreadCount! > 0) {
      actions.insert(
          0,
          BottomSheetAction(
              title: Text(
                tL10n.markAsRead,
                style: style,
              ),
              onPressed: (context) {
                if (handled) return;
                handled = true;
                _markAsRead();
                hideMoreItemAction();
              }));
    }

    await showAdaptiveActionSheet(
      context: context,
      title: Text(tL10n.more),
      androidBorderRadius: 30,
      actions: actions,
      cancelAction: CancelAction(
        title: Text(
          tL10n.cancel,
          style: cancelStyle,
        ),
        // Without an explicit onPressed the library default-dismisses with a raw
        // Navigator.pop — vulnerable to the same double-fire blank. Route it
        // through the shared one-shot flag so a double-tap pops exactly once.
        onPressed: (ctx) {
          if (handled) return;
          handled = true;
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Widget conversationInner(BuildContext actionContext,
      TencentCloudChatThemeColors colors, TencentCloudChatTextStyle fontSize) {
    bool pinned = isPin();
    final isDesktopScreen = TencentCloudChatScreenAdapter.deviceScreenType ==
        DeviceScreenType.desktop;

    // Selected/active row tint per the reference design (DesignTokens
    // selectedLight #E5ECF4 / selectedDark #21314A). Picked by brightness;
    // UIKit cannot import toxee's DesignTokens, so the values are inlined here.
    final bool isDark = Theme.of(actionContext).brightness == Brightness.dark;
    const Color selectedRowTintLight = Color(0xFFE5ECF4);
    const Color selectedRowTintDark = Color(0xFF21314A);

    // Reference design separates conversation rows by whitespace, with no
    // hairline divider between them.
    return Ink(
      decoration: BoxDecoration(
        color: widget.isSelected
            ? (isDark ? selectedRowTintDark : selectedRowTintLight)
            : (pinned
                ? colors.conversationItemIsPinedBgColor
                : colors.conversationItemNormalBgColor),
      ),
      child: TencentCloudChatGesture(
        onTap: _navigateToMessage,
        onSecondaryTapDown: (details) =>
            _handleSecondaryTap(details, isDesktopScreen),
        // Use `onLongPressStart` (not `onLongPress`) so the handler gets the
        // exact press globalPosition. Desktop mouse long-press may not fire
        // `onTapDown` first, so caching tap-down details is unreliable —
        // `LongPressStartDetails` carries `globalPosition` directly.
        onLongPressStart: (startDetails) => _handleLongPress(
            startDetails, isDesktopScreen, actionContext, fontSize, colors),
        child: Padding(
          // Reference design row metrics: desktop ≈58 (avatar 40 + 9*2),
          // mobile ≈72 (avatar 48 + 12*2).
          padding: EdgeInsets.symmetric(
            vertical: getHeight(isDesktopScreen ? 9 : 12),
            horizontal: getWidth(8),
          ),
          child: Row(
            children: [
              TencentCloudChat
                  .instance.dataInstance.conversation.conversationBuilder
                  ?.getConversationItemAvatarBuilder(
                widget.conversation,
                widget.isOnline,
              ),
              TencentCloudChat
                  .instance.dataInstance.conversation.conversationBuilder
                  ?.getConversationItemContentBuilder(
                widget.conversation,
              ),
              TencentCloudChat
                  .instance.dataInstance.conversation.conversationBuilder
                  ?.getConversationItemInfoBuilder(
                widget.conversation,
              ),
            ],
          ),
        ),
      ),
    );
  }

  hideMoreItemAction({Offset? offset}) {
    Navigator.of(context).pop();
  }

  _hideConversation({Offset? offset}) async {
    await TencentCloudChat.instance.chatSDKInstance.manager
        .getConversationManager()
        .markConversation(
            markType: 8,
            enableMark: true,
            conversationIDList: [widget.conversation.conversationID]);
  }

  _deleteConversation({Offset? offset}) async {
    var result = await conversationPresenter.cleanConversation(
        conversationIDList: [widget.conversation.conversationID],
        clearMessage: true);

    if (result.code == 0) {
      TencentCloudChat.instance.dataInstance.messageData.clearMessageList(
          userID: widget.conversation.userID,
          groupID: widget.conversation.groupID);
    }
  }

  _pinConversation({Offset? offset}) async {
    await TencentCloudChat.instance.chatSDKInstance.conversationSDK
        .pinConversation(
      conversationID: widget.conversation.conversationID,
      isPinned: isPin() ? false : true,
    );
  }

  bool _isHidden() {
    // V2TIM_CONVERSATION_MARK_TYPE_HIDE = 0x1 << 3
    return widget.conversation.markList?.contains(8) ?? false;
  }

  @override
  Widget desktopBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (ctx, colors, fontSize) =>
          conversationInner(ctx, colors, fontSize),
    );
  }

  @override
  Widget tabletAppBuilder(BuildContext context) {
    return defaultBuilder(context);
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return _isHidden()
        ? const SizedBox()
        : TencentCloudChatThemeWidget(
            build: (ctx, colors, fontSize) => SwipeActionCell(
              key: ObjectKey(widget.conversation.conversationID),
              trailingActions: <SwipeAction>[
                SwipeAction(
                  title: isPin() ? tL10n.unpin : tL10n.pin,
                  onTap: (CompletionHandler handler) async {
                    await _pinConversation();
                  },
                  color: colors.conversationItemSwipeActionOneBgColor,
                  icon: Icon(
                    isPin()
                        ? Icons.vertical_align_bottom_rounded
                        : Icons.vertical_align_top_rounded,
                    color: colors.conversationItemSwipeActionOneTextColor,
                  ),
                  style: TextStyle(
                    fontSize: fontSize.fontsize_12,
                    color: colors.conversationItemSwipeActionOneTextColor,
                  ),
                ),
                SwipeAction(
                  title: tL10n.more,
                  onTap: (CompletionHandler handler) async {
                    await showMoreItemAction(ctx, fontSize, colors);
                  },
                  color: colors.conversationItemSwipeActionTwoBgColor,
                  icon: Icon(
                    Icons.expand_circle_down_outlined,
                    color: colors.conversationItemSwipeActionTwoTextColor,
                  ),
                  style: TextStyle(
                    fontSize: fontSize.fontsize_12,
                    color: colors.conversationItemSwipeActionTwoTextColor,
                  ),
                ),
              ],
              backgroundColor: Colors.transparent,
              child: conversationInner(ctx, colors, fontSize),
            ),
          );
  }
}

class TencentCloudChatConversationItemAvatar extends StatefulWidget {
  final V2TimConversation conversation;
  final bool isOnline;

  const TencentCloudChatConversationItemAvatar({
    super.key,
    required this.conversation,
    required this.isOnline,
  });

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatConversationItemAvatarState();
}

class TencentCloudChatConversationItemAvatarState
    extends TencentCloudChatState<TencentCloudChatConversationItemAvatar> {
  List<String> getAvatar() {
    return [widget.conversation.faceUrl ?? ''];
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    final isDesktop = TencentCloudChatScreenAdapter.deviceScreenType ==
        DeviceScreenType.desktop;
    // Reference design: desktop avatar 40, mobile avatar 48.
    final double avatarSize = isDesktop ? 40 : 48;
    // Avatar shape by conversation type: group → rounded square (≈28% of
    // size), person → circle (size / 2).
    final bool isGroup =
        widget.conversation.type == ConversationType.V2TIM_GROUP;
    final double avatarRadius = isGroup ? avatarSize * 0.28 : avatarSize / 2;
    return TencentCloudChatThemeWidget(
      build: (ctx, colors, fonts) => Padding(
        padding: EdgeInsets.symmetric(
          horizontal: getWidth(isDesktop ? 10 : 8),
        ),
        child: SizedBox(
          width: getSquareSize(avatarSize),
          height: getSquareSize(avatarSize),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: TencentCloudChatCommonBuilders.getCommonAvatarBuilder(
                  imageList: getAvatar(),
                  width: getSquareSize(avatarSize),
                  height: getSquareSize(avatarSize),
                  borderRadius: getSquareSize(avatarRadius),
                  scene: TencentCloudChatAvatarScene.conversationList,
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: SizedBox(
                  key: ValueKey(
                    'conversation_item_online_dot:${widget.conversation.conversationID}:'
                    '${widget.isOnline ? 'online' : 'offline'}',
                  ),
                  width: getSquareSize(isDesktop ? 9 : 10),
                  height: getSquareSize(isDesktop ? 9 : 10),
                  child: Container(
                    key: ValueKey(
                      'conversation_item_online_dot:${widget.conversation.conversationID}',
                    ),
                    decoration: BoxDecoration(
                      color: widget.isOnline
                          ? colors.conversationItemUserStatusBgColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.all(
                        Radius.circular(
                          getSquareSize(5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TencentCloudChatConversationItemContent extends StatefulWidget {
  final V2TimConversation conversation;

  const TencentCloudChatConversationItemContent({
    super.key,
    required this.conversation,
  });

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatConversationItemContentState();
}

class TencentCloudChatConversationItemContentState
    extends TencentCloudChatState<TencentCloudChatConversationItemContent> {
  String getDraftText() {
    String draft = "";
    if (widget.conversation.draftText != null) {
      draft = widget.conversation.draftText!;
    }
    if (draft.isNotEmpty) {
      draft = "[${tL10n.draft}]$draft";
    }
    return draft;
  }

  Widget getLastMessageStatus(TencentCloudChatThemeColors colorTheme) {
    Widget? wid;
    if (widget.conversation.lastMessage != null) {
      var message = widget.conversation.lastMessage!;
      if (message.status == 1) {
        // sending
        wid = Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            Icons.arrow_circle_left,
            size: getSquareSize(14),
            color: colorTheme.conversationItemSendingIconColor,
          ),
        );
      }
      if (message.status == 3) {
        // failed
        wid = Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Icon(
            Icons.error_rounded,
            size: getSquareSize(14),
            color: colorTheme.conversationItemSendFailedIconColor,
          ),
        );
      }
    }
    wid ??= Container();
    return wid;
  }

  /// The one-line preview beside the status icon: the `[Draft]…` text, the
  /// group-@ tips and the last-message summary rendered as ONE ellipsized
  /// rich Text in ONE flex slot.
  ///
  /// They used to be three separate bare `Text`s in the preview Row, so any
  /// of them could push the Row past its bounds: a multi-line composer draft
  /// laid itself out at its widest line's intrinsic width ("RIGHT OVERFLOWED
  /// BY 67 PIXELS" on the conversation list), and `[@All] [Someone @ me]`
  /// could do the same on a narrow phone or at a large text scale. A single
  /// `Expanded` text cannot — and it keeps the whole width for whichever
  /// parts exist (the summary is empty whenever a draft exists, see
  /// TencentCloudChatUtils.getMessageSummary). Newlines and runs of
  /// whitespace in the draft are collapsed so the preview stays one line.
  Widget getPreviewWidget(TencentCloudChatTextStyle textStyle,
      TencentCloudChatThemeColors colorTheme) {
    final draft = getDraftText().replaceAll(RegExp(r'\s+'), ' ').trim();
    final atTips = getGroupAtTipsText();
    final summary = getLastMessageText();
    if (draft.isEmpty && atTips.isEmpty && summary.isEmpty) {
      return const SizedBox.shrink();
    }
    final base = TextStyle(
      fontSize: textStyle.fontsize_12,
      fontWeight: FontWeight.w400,
    );
    return Expanded(
      child: Text.rich(
        TextSpan(children: [
          if (draft.isNotEmpty)
            TextSpan(
              text: draft,
              style: base.copyWith(
                  color: colorTheme.conversationItemDraftTextColor),
            ),
          if (atTips.isNotEmpty)
            TextSpan(
              text: atTips,
              style: base.copyWith(
                  color: colorTheme.conversationItemGroupAtInfoTextColor),
            ),
          if (summary.isNotEmpty)
            TextSpan(
              text: summary,
              style: base.copyWith(
                  color: colorTheme.conversationItemLastMessageTextColor),
            ),
        ]),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  /// Last-message summary with emoji short-codes expanded; empty when there
  /// is nothing to show (no message, or a draft takes precedence).
  String getLastMessageText() {
    final laseMessage = widget.conversation.lastMessage;
    String originalText = TencentCloudChatUtils.getMessageSummary(
      message: laseMessage,
      messageReceiveOption: widget.conversation.recvOpt,
      unreadCount: widget.conversation.unreadCount,
      draftText: widget.conversation.draftText,
    );

    return FaceManager.emojiMap.keys.fold(originalText, (previous, key) {
      return previous.replaceAll(key, FaceManager.emojiMap[key]!);
    });
  }

  int? _getShowAtType(List<V2TimGroupAtInfo> mentionedInfoList) {
    // 1 TIM_AT_ME = 1
    // 2 TIM_AT_ALL = 2
    // 3 TIM_AT_ALL_AT_ME = 3
    int? atType;
    if (mentionedInfoList.isNotEmpty) {
      atType = mentionedInfoList.first.atType;
      for (var info in mentionedInfoList.skip(1)) {
        if (info.atType != atType) {
          atType = 3;
          break;
        }
      }
    }

    return atType;
  }

  /// `"[@All] [Someone @ me] "`-style tips for the pending group mentions,
  /// or an empty string. Rendered inside [getPreviewWidget].
  String getGroupAtTipsText() {
    String atTips = '';
    if (widget.conversation.groupAtInfoList != null) {
      if (widget.conversation.groupAtInfoList!.isNotEmpty) {
        List<V2TimGroupAtInfo> mentionedInfoList = [];

        for (var element in widget.conversation.groupAtInfoList!) {
          if (element != null) {
            mentionedInfoList.add(element);
          }
        }

        int? atType = _getShowAtType(mentionedInfoList);
        if (atType != null) {
          switch (atType) {
            case 1:
              atTips = "[${tL10n.atMeTips}] ";
              break;
            case 2:
              atTips = "[${tL10n.atAllTips}] ";
              break;
            case 3:
              atTips = "[${tL10n.atAllTips}] [${tL10n.atMeTips}] ";
              break;
            default:
              print("error: invalid atType!");
              break;
          }
        }
      }
    }
    return atTips;
  }

  @override
  Widget desktopBuilder(BuildContext context) {
    final hasUnread = (widget.conversation.unreadCount ?? 0) > 0;
    final titleWeight = hasUnread ? FontWeight.w600 : FontWeight.w500;
    return Expanded(
      child:
          TencentCloudChatThemeWidget(build: (context, colorTheme, textStyle) {
        Widget status = getLastMessageStatus(colorTheme);
        Widget preview = getPreviewWidget(textStyle, colorTheme);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Text(
              widget.conversation.showName ??
                  widget.conversation.conversationID,
              style: TextStyle(
                fontSize: textStyle.fontsize_13,
                fontWeight: titleWeight,
                color: colorTheme.conversationItemShowNameTextColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(
              height: getHeight(4),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                status,
                preview,
              ],
            )
          ],
        );
      }),
    );
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    final hasUnread = (widget.conversation.unreadCount ?? 0) > 0;
    final titleWeight = hasUnread ? FontWeight.w600 : FontWeight.w500;
    return Expanded(
      child:
          TencentCloudChatThemeWidget(build: (context, colorTheme, textStyle) {
        Widget status = getLastMessageStatus(colorTheme);
        Widget preview = getPreviewWidget(textStyle, colorTheme);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Text(
              widget.conversation.showName ??
                  widget.conversation.conversationID,
              style: TextStyle(
                fontSize: textStyle.fontsize_14,
                fontWeight: titleWeight,
                color: colorTheme.conversationItemShowNameTextColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                status,
                preview,
              ],
            )
          ],
        );
      }),
    );
  }
}

class TencentCloudChatConversationItemInfoUnreadCount extends StatefulWidget {
  final V2TimConversation conversation;

  const TencentCloudChatConversationItemInfoUnreadCount(
      {super.key, required this.conversation});

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatConversationItemInfoUnreadCountState();
}

class TencentCloudChatConversationItemInfoUnreadCountState
    extends TencentCloudChatState<
        TencentCloudChatConversationItemInfoUnreadCount> {
  bool hasUnreadCount() {
    bool has = false;
    if (widget.conversation.unreadCount != null) {
      if (widget.conversation.unreadCount! > 0) {
        has = true;
      }
    }
    return has;
  }

  String unReadCountDisplayText() {
    String text = "";
    int count = widget.conversation.unreadCount ?? 0;
    if (count > 99) {
      text = "99+";
    } else {
      text = "$count";
    }
    return text;
  }

  Widget unreadCountWidget(
      context, TencentCloudChatThemeColors colorTheme, textStyle) {
    String text = unReadCountDisplayText();
    return Container(
      // Min-size pill instead of a fixed 16/26 px box so "99+" still fits when
      // the text scale grows; the shape/radius is unchanged.
      constraints: BoxConstraints(minWidth: getWidth(16), minHeight: getHeight(16)),
      padding: EdgeInsets.symmetric(horizontal: text.length == 1 ? 0 : getWidth(4)),
      decoration: BoxDecoration(
        color: colorTheme.conversationItemUnreadCountBgColor,
        borderRadius: BorderRadius.all(
          Radius.circular(
            getSquareSize(8),
          ),
        ),
      ),
      // Shrink-wrap: without the factors Center would fill the loose parent
      // constraints now that the box has no fixed width.
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: getFontSize(10),
            fontWeight: FontWeight.w600,
            color: colorTheme.conversationItemUnreadCountTextColor,
          ),
        ),
      ),
    );
  }

  Widget noUnreadPlaceHolderWidget() {
    return SizedBox(
      height: getHeight(16),
    );
  }

  Widget notificationOffWidget(TencentCloudChatThemeColors colorTheme) {
    return Icon(
      Icons.notifications_off,
      size: getSquareSize(14),
      color: colorTheme.conversationItemNoReceiveIconColor,
    );
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    bool hasUnread = hasUnreadCount();
    int receiveOption = widget.conversation.recvOpt ?? 0;
    return TencentCloudChatThemeWidget(build: (context, colorTheme, textStyle) {
      if (receiveOption != 0) {
        return notificationOffWidget(colorTheme);
      } else {
        if (hasUnread) {
          return unreadCountWidget(context, colorTheme, textStyle);
        } else {
          return noUnreadPlaceHolderWidget();
        }
      }
    });
  }
}

class TencentCloudChatConversationItemInfoTimeAndStatus extends StatefulWidget {
  final V2TimConversation conversation;

  const TencentCloudChatConversationItemInfoTimeAndStatus({
    super.key,
    required this.conversation,
  });

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatConversationItemInfoTimeAndStatusState();
}

class TencentCloudChatConversationItemInfoTimeAndStatusState
    extends TencentCloudChatState<
        TencentCloudChatConversationItemInfoTimeAndStatus> {
  bool hasLastMessage() {
    return widget.conversation.lastMessage != null;
  }

  String getLastMessageTimeText() {
    String text = '';
    if (widget.conversation.lastMessage != null) {
      if (widget.conversation.lastMessage!.timestamp != null) {
        text = TencentCloudChatIntl.formatTimestampToHumanReadable(
          widget.conversation.lastMessage!.timestamp!,
          context,
        );
      }
    }
    return text;
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    String timeText = getLastMessageTimeText();
    if (!hasLastMessage()) {
      return Container();
    }
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Flexible: the column is a fixed 96 px, and long weekday names in
          // other locales (or large text scale) otherwise overflow it.
          Flexible(
            child: Text(
              timeText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: textStyle.fontsize_12,
                fontWeight: FontWeight.w400,
                color: colorTheme.conversationItemTimeTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TencentCloudChatConversationItemInfo extends StatefulWidget {
  final V2TimConversation conversation;

  const TencentCloudChatConversationItemInfo({
    super.key,
    required this.conversation,
  });

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatConversationItemInfoState();
}

class TencentCloudChatConversationItemInfoState
    extends TencentCloudChatState<TencentCloudChatConversationItemInfo> {
  @override
  Widget defaultBuilder(BuildContext context) {
    return SizedBox(
      width: getWidth(96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          TencentCloudChatConversationItemInfoUnreadCount(
            conversation: widget.conversation,
          ),
          TencentCloudChatConversationItemInfoTimeAndStatus(
            conversation: widget.conversation,
          ),
        ],
      ),
    );
  }
}
