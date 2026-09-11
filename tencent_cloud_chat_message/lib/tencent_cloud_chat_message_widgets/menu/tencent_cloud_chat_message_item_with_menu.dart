// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_platform_adapter.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/data/message/tencent_cloud_chat_message_data.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/color_base.dart';
import 'package:tencent_cloud_chat_common/data/theme/text_style/text_style.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/widgets/desktop_column_menu/tencent_cloud_chat_column_menu.dart';
import 'dart:ui' as ui;
import 'package:flutter_svg/svg.dart';

class TencentCloudChatMessageItemWithMenu extends StatefulWidget {
  final MessageItemMenuBuilderWidgets? widgets;
  final MessageItemMenuBuilderData data;
  final MessageItemMenuBuilderMethods methods;

  const TencentCloudChatMessageItemWithMenu({
    super.key,
    this.widgets,
    required this.data,
    required this.methods,
  });

  @override
  State<TencentCloudChatMessageItemWithMenu> createState() => _TencentCloudChatMessageItemWithMenuState();
}

class _TencentCloudChatMessageItemWithMenuState extends TencentCloudChatState<TencentCloudChatMessageItemWithMenu>
    with TickerProviderStateMixin {
  final Stream<TencentCloudChatMessageData<dynamic>>? _messageDataStream =
  TencentCloudChat.instance.eventBusInstance.on<TencentCloudChatMessageData>("TencentCloudChatMessageData");
  late StreamSubscription<TencentCloudChatMessageData<dynamic>>? _messageDataSubscription;

  final isDesktopScreen = TencentCloudChatScreenAdapter.deviceScreenType == DeviceScreenType.desktop;
  String? _selectedText;

  OverlayEntry? _mobileMenuOverlayEntry;
  OverlayEntry? _desktopMenuOverlayEntry;

  final GlobalKey _messageGestureKey = GlobalKey();
  final GlobalKey? _messageKey = null;
  final GlobalKey _selectionAreaKey = GlobalKey();
  final GlobalKey _reactionKey = GlobalKey();
  final GlobalKey _menuKey = GlobalKey();
  bool _showActions = false;
  double? _menuHeight; // Store the actual menu height
  double? _menuWidth;

  double? _reactionHeight; // Store the actual menu height
  double? _reactionWidth;
  late AnimationController _messageActionsAnimationController;
  late AnimationController _listMessageScaleAnimationController;
  late AnimationController _overlayMessageScaleAnimationController;
  late AnimationController _menuAnimationController;

  late Animation<double> _listMessageScaleAnimation;
  late Animation<double> _menuAnimation;
  late Animation<double> _overlayMessageScaleAnimation;

  String? listenerID;

  List<TencentCloudChatMessageGeneralOptionItem> _menuOptions = [];

  void _messageDataHandler(TencentCloudChatMessageData messageData) {
    final msgID = widget.data.message.msgID ?? "";
    final TencentCloudChatMessageDataKeys messageDataKeys = messageData.currentUpdatedFields;
    final messageNeedUpdate = TencentCloudChat.instance.dataInstance.messageData.messageNeedUpdate;

    switch (messageDataKeys) {
      case TencentCloudChatMessageDataKeys.messageNeedUpdate:
        if (messageNeedUpdate != null && (
              (TencentCloudChatUtils.checkString(msgID) != null && msgID == messageNeedUpdate.msgID) ||
                  (TencentCloudChatUtils.checkString(messageNeedUpdate.id) != null && widget.data.message.id == messageNeedUpdate.id)
        )) {
          if (messageNeedUpdate.status == MessageStatus.V2TIM_MSG_STATUS_LOCAL_REVOKED) {
            if(!isDesktopScreen){
              _closeMobileMenu();
            } else {
              _removeDesktopMenu();
            }
          }
        }
      default:
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    _addUIKitListener();
    if (isDesktopScreen) {
      if (TencentCloudChatPlatformAdapter().isMobile) {
        _mobileInit();
      }
    } else {
      _mobileInit();
    }

    _messageDataSubscription = _messageDataStream?.listen(_messageDataHandler);
  }

  @override
  void dispose() {
    _removeUIKitListener();
    _messageDataSubscription?.cancel();
    if (!isDesktopScreen) {
      _mobileDispose();
    }

    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TencentCloudChatMessageItemWithMenu oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newOptions = widget.methods.getMenuOptions(selectedText: _selectedText);
    if (_menuOptions.length != newOptions.length && _menuHeight != null) {
      _menuHeight = null;
    }
    _menuOptions = newOptions;
  }

  void _addUIKitListener() {
    if(widget.data.useMessageReaction){
      listenerID ??= TencentCloudChat.instance.chatSDKInstance.messageSDK.addUIKitListener(listener: _uikitListener);
      return;
    }
  }

  void _removeUIKitListener() {
    if(listenerID != null && widget.data.useMessageReaction){
      TencentCloudChat.instance.chatSDKInstance.messageSDK.removeUIKitListener(listenerID: listenerID!);
    }
  }

  void _uikitListener(Map<String, dynamic> data) {
    if (data.containsKey("eventType")) {
      if (data["eventType"] == "onClickReactionSelector") {
        if (isDesktopScreen) {
          _removeDesktopMenu();
        } else {
          _cancelMobileMessageActions();
        }
      } else if (_showActions && data["eventType"] == "onShowMessageReactionDetail") {
        if (isDesktopScreen) {
          _removeDesktopMenu();
        } else {
          _cancelMobileMessageActions();
        }
      }
    }
  }

  void _closeMobileMenu() {
    safeSetState(() {
      _showActions = false;
    });
    _mobileMenuOverlayEntry?.remove();
    _mobileMenuOverlayEntry = null;
  }

  void _mobileInit() {
    _listMessageScaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _messageActionsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _overlayMessageScaleAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _menuAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _messageActionsAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _menuAnimationController.forward();
      } else if (status == AnimationStatus.dismissed) {
        _menuAnimationController.reverse();
      }
    });

    final menuCurve = CurvedAnimation(parent: _menuAnimationController, curve: Curves.ease);
    _menuAnimation = Tween<double>(begin: 0, end: 1).animate(menuCurve);
    _listMessageScaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(_listMessageScaleAnimationController);
    _overlayMessageScaleAnimation = Tween<double>(begin: 0.9, end: 1).animate(_overlayMessageScaleAnimationController);
  }

  void _mobileDispose() {
    _messageActionsAnimationController.dispose();
    _listMessageScaleAnimationController.dispose();
    _menuAnimationController.dispose();
    _overlayMessageScaleAnimationController.dispose();
  }

  // Function to build the Message Reaction bar
  Widget _buildReactionBar({GlobalKey? key}) {
    return TencentCloudChatUtils.checkString(widget.data.message.msgID) != null ? Container(
      color: Colors.transparent,
      key: key,
      child: TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) {
          final Map<String, String> data = {};
          data["msgID"] = widget.data.message.msgID!;
          data["backgroundColor"] = colorTheme.backgroundColor.value.toString();
          data["borderColor"] = colorTheme.dividerColor.value.toString();
          data["platformMode"] = isDesktopScreen ? "desktop" : "mobile";
          return widget.data.messageReactionPluginInstance?.getWidgetSync(
            methodName: "messageReactionSelector",
            data: data,
          ) ?? const SizedBox(
            width: 0,
            height: 0,
          );
        },
      ),
    ) : const SizedBox(
      width: 0,
      height: 0,
    );
  }

  // [keyed] controls whether the per-item automation ValueKeys
  // (`message_menu_item:<action>`) are attached. The desktopBuilder renders a
  // HIDDEN measurement copy of this menu (an Offstage child used only to size
  // the popup); that copy must pass `keyed: false` so it does NOT duplicate the
  // visible overlay menu's keys. Without this, two `message_menu_item:recall`
  // (etc.) widgets exist whenever a message is mounted, and key-based UI
  // automation (flutter_skill matches OFFSTAGE subtrees too) can resolve/tap the
  // stale offstage copy instead of the real menu — the tap then lands on the
  // dismiss barrier and the action (recall/forward/…) silently never fires.
  Widget _buildDesktopMenu({GlobalKey? key, bool keyed = true}) {
    final list = widget.methods.getMenuOptions(selectedText: _selectedText);
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => TencentCloudChatColumnMenu(
        key: key,
        data: list
            .map((e) => TencentCloudChatMessageGeneralOptionItem(
          label: e.label,
          // Preserve id so the action token resolves the same as mobile.
          id: e.id,
          // Stable test/automation handle for the desktop context-menu entry.
          // Mirrors the mobile long-press menu key contract. Suppressed on the
          // offstage measurement copy (see [keyed] above) to avoid duplicates.
          valueKey: keyed ? tencentCloudChatMessageMenuKeyForOption(e) : null,
          onTap: ({Offset? offset}) {
            _removeDesktopMenu();
            e.onTap();
          },
          iconAsset: e.iconAsset,
          icon: e.icon,
        ))
            .toList(),
      ),
    );
  }

  List<TableRow> _buildMobileMenuItems({
    required TencentCloudChatThemeColors colorTheme,
    required TencentCloudChatTextStyle textStyle,
    // See [_buildDesktopMenu]'s `keyed`: the mobile menu is ALSO built twice
    // (visible overlay + an offstage measurement copy), so the measurement copy
    // must pass keyed:false to avoid duplicating the `message_menu_item:<action>`
    // automation keys (flutter_skill matches offstage subtrees → the stale copy
    // could be tapped instead of the real menu).
    bool keyed = true,
  }) {
    List<TableRow> menuItems = [];

    final menuOptions = widget.methods.getMenuOptions();
    for (int i = 0; i < menuOptions.length; i++) {
      final e = menuOptions[i];

      menuItems.add(
        TableRow(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                // Stable test/automation handle for the long-press menu entry.
                // Action token is derived from the option id (e.g. copy, reply,
                // multiSelect, forward, delete, recall) so it survives locale changes.
                // Suppressed on the offstage measurement copy (see [keyed]).
                key: keyed ? tencentCloudChatMessageMenuKeyForOption(e) : null,
                onTap: () {
                  _closeMobileMenu();
                  e.onTap();
                },
                child: Container(
                  decoration: (i < menuOptions.length - 1)
                      ? BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: colorTheme.dividerColor, width: 0.5),
                          ),
                        )
                      : null,
                  padding: EdgeInsets.symmetric(vertical: getSquareSize(8), horizontal: getSquareSize(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        e.label,
                        style: TextStyle(
                          decoration: TextDecoration.none,
                          color: colorTheme.primaryTextColor.withOpacity(0.94),
                          fontSize: textStyle.standardText,
                        ),
                      ),
                      Builder(builder: (ctx) {
                        if (e.iconAsset != null) {
                          final type = e.iconAsset!.path.split(".")[e.iconAsset!.path.split(".").length - 1];
                          if (type == "svg") {
                            return SvgPicture.asset(
                              e.iconAsset!.path,
                              package: e.iconAsset!.package,
                              width: 16,
                              height: 16,
                              colorFilter: ui.ColorFilter.mode(
                                colorTheme.primaryTextColor.withOpacity(0.9),
                                ui.BlendMode.srcIn,
                              ),
                            );
                          }
                          return Image.asset(
                            e.iconAsset!.path,
                            package: e.iconAsset!.package,
                            width: getFontSize(16),
                            height: getFontSize(16),
                            color: colorTheme.primaryTextColor.withOpacity(0.9),
                          );
                        }
                        if (e.icon != null) {
                          return Icon(
                            e.icon,
                            size: getFontSize(16),
                          );
                        }
                        return Container();
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return menuItems;
  }

  // [maxHeight] bounds the option list so a tall menu scrolls instead of
  // running past the safe area; null (the offstage measuring copy) keeps the
  // intrinsic height so _menuHeight stays the full size.
  Widget _buildMobileMenuWidget({Key? key, bool keyed = true, double? maxHeight}) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: getWidth(200)),
                child: Container(
                  key: key,
                  decoration: BoxDecoration(
                    // boxShadow: const [
                    //   BoxShadow(
                    //     color: Color(0xCCbebebe),
                    //     offset: Offset(2, 2),
                    //     blurRadius: 10,
                    //     spreadRadius: 1,
                    //   ),
                    // ],
                    border: Border.all(
                      width: 1,
                      color: colorTheme.dividerColor,
                    ),
                    color: colorTheme.backgroundColor.withOpacity(0.8),
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
                    child: SingleChildScrollView(
                      child: Table(
                        columnWidths: const <int, TableColumnWidth>{
                          0: IntrinsicColumnWidth(),
                        },
                        children: _buildMobileMenuItems(colorTheme: colorTheme, textStyle: textStyle, keyed: keyed),
                      ),
                    ),
                  ),
                ),
              ),
            ));
  }

  void _cancelMobileMessageActions() {
    try {
      _menuAnimationController.reverse();
      _messageActionsAnimationController.reverse().then((_) {
        safeSetState(() {
          _showActions = false;
        });
        _mobileMenuOverlayEntry!.remove();
        _mobileMenuOverlayEntry = null;
      });
    } catch (e) {
      try {
        _messageActionsAnimationController.reverse().then((_) {
          safeSetState(() {
            _showActions = false;
          });
          _mobileMenuOverlayEntry!.remove();
          _mobileMenuOverlayEntry = null;
        });
      } catch (e) {
        safeSetState(() {
          _showActions = false;
        });
        _mobileMenuOverlayEntry!.remove();
        _mobileMenuOverlayEntry = null;
      }
    }
  }

  void _showMobileMessageActions() {
    if (_mobileMenuOverlayEntry == null) {
      if (_menuHeight == null || _menuWidth == null) {
        // Get the menu height using GlobalKey
        final RenderBox menuBox = _reactionKey.currentContext!.findRenderObject() as RenderBox;
        _menuHeight = menuBox.size.height;
        _menuWidth = menuBox.size.width;
      }

      final textDirection = Directionality.of(context);

      // Everything below is Positioned in the ROOT Overlay, so bounds come
      // from ITS MediaQuery (safe insets included) — the message's own
      // context may sit under a Scaffold that already removed some padding.
      final BuildContext overlayContext = Overlay.of(context).context;
      final EdgeInsets safeInsets = MediaQuery.paddingOf(overlayContext);
      final Size screenSize = MediaQuery.sizeOf(overlayContext);
      final double screenWidth = screenSize.width;
      const double gap = 16;
      final double topBound = safeInsets.top + 8;
      final double bottomBound = screenSize.height - safeInsets.bottom - 8;
      final double leftBound = safeInsets.left + 8;
      final double rightBound = screenWidth - safeInsets.right - 8;
      final double available = max(0.0, bottomBound - topBound);

      RenderBox messageBox = context.findRenderObject() as RenderBox;
      Offset messagePosition = messageBox.localToGlobal(Offset.zero);
      Size messageSize = messageBox.size;

      double reactionBarHeight = widget.data.useMessageReaction ? 54 : 0;
      double reactionBarWidth = widget.data.useMessageReaction ? min(800, screenWidth * 0.76) : 0;
      final double reactionSlot = widget.data.useMessageReaction ? reactionBarHeight + gap : 0;

      // Size menu and preview TOGETHER so the stack always fits the safe
      // area: the menu keeps its intrinsic height as long as the preview can
      // keep a 44-px strip (it scrolls when even that does not fit), then the
      // preview is clipped to whatever is left. Pushing the menu off-screen
      // was the old failure mode (390-px-tall screen, 500-px message).
      final double minPreviewHeight = min(messageSize.height, 44.0);
      final double menuShownHeight = max(
          0.0, min(_menuHeight!, available - reactionSlot - gap - minPreviewHeight));
      final double previewShownHeight =
          max(0.0, min(messageSize.height, available - reactionSlot - gap - menuShownHeight));
      final bool previewClipped = previewShownHeight < messageSize.height;

      // Reaction bar goes above when it still fits there after the shift the
      // menu needs to stay on-screen; otherwise it goes below the menu.
      final double overflowBelow =
          messagePosition.dy + previewShownHeight + gap + menuShownHeight - bottomBound;
      final bool showReactionBarAbove = widget.data.useMessageReaction &&
          messagePosition.dy - max(0.0, overflowBelow) >= topBound + reactionSlot;

      final double minPreviewTop = topBound + (showReactionBarAbove ? reactionSlot : 0);
      final double maxPreviewTop = max(
          minPreviewTop,
          bottomBound - previewShownHeight - gap - menuShownHeight - (showReactionBarAbove ? 0 : reactionSlot));
      final double previewTop = messagePosition.dy.clamp(minPreviewTop, maxPreviewTop).toDouble();
      // Positive shifts the preview up (the original behaviour); negative
      // pulls a message that sits above the safe area back into view.
      final double messageOffset = messagePosition.dy - previewTop;

      if (messageOffset == 0) {
        _menuAnimationController.forward();
      }

      final double menuTop = previewTop + previewShownHeight + gap;
      final double menuMaxHeight = menuShownHeight;

      final double reactionBarTop = showReactionBarAbove
          ? previewTop - gap - reactionBarHeight
          : menuTop + menuShownHeight + gap;

      double menuLeft = textDirection == TextDirection.ltr
          ? ((widget.data.message.isSelf ?? true)
              ? messagePosition.dx + messageBox.size.width - _menuWidth!
              : messagePosition.dx)
          : ((widget.data.message.isSelf ?? true)
              ? messagePosition.dx
              : messagePosition.dx + messageBox.size.width - _menuWidth!);
      menuLeft = menuLeft.clamp(leftBound, max(leftBound, rightBound - _menuWidth!)).toDouble();

      double reactionBarLeft = textDirection == TextDirection.ltr
          ? ((widget.data.message.isSelf ?? true)
          ? messagePosition.dx + messageBox.size.width - reactionBarWidth
          : messagePosition.dx)
          : ((widget.data.message.isSelf ?? true)
          ? messagePosition.dx
          : messagePosition.dx + messageBox.size.width - reactionBarWidth);
      reactionBarLeft = reactionBarLeft.clamp(leftBound, max(leftBound, rightBound - reactionBarWidth)).toDouble();

      Animation<double> messageTopTween = Tween<double>(
        begin: messagePosition.dy,
        end: previewTop,
      ).animate(CurvedAnimation(parent: _messageActionsAnimationController, curve: Curves.easeOut));

      final Widget previewItem = SelectionArea(
        child: widget.methods.getMessageItemWidget(
          renderOnMenuPreview: true,
        ),
      );

      _mobileMenuOverlayEntry = OverlayEntry(builder: (BuildContext context) {
        return AnimatedBuilder(
            animation: _messageActionsAnimationController,
            builder: (BuildContext context, Widget? child) => TencentCloudChatThemeWidget(
                build: (context, colorTheme, textStyle) => Stack(
                      children: [
                        AnimatedOpacity(
                          opacity: _messageActionsAnimationController.value,
                          duration: _messageActionsAnimationController.duration!,
                          child: GestureDetector(
                            onTap: () {
                              _cancelMobileMessageActions();
                            },
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                color: Colors.black.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: messagePosition.dx,
                          top: messageTopTween.value,
                          child: ScaleTransition(
                            alignment: Alignment.topCenter,
                            scale: _overlayMessageScaleAnimation,
                            child: Material(
                              color: Colors.transparent,
                              // A preview taller than its share is clipped to
                              // previewShownHeight and scrolls, so it can never
                              // paint over the menu below it.
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: messageSize.width,
                                  maxHeight: previewClipped ? previewShownHeight : double.infinity,
                                ),
                                child: previewClipped
                                    ? SingleChildScrollView(child: previewItem)
                                    : previewItem,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                            left: menuLeft,
                            top: menuTop,
                            child: ScaleTransition(
                              scale: _menuAnimation,
                              child: _buildMobileMenuWidget(maxHeight: menuMaxHeight),
                            )),
                        Positioned(
                          left: reactionBarLeft,
                          top: reactionBarTop,
                          child: ScaleTransition(
                            scale: _menuAnimation,
                            child: _buildReactionBar(),
                          ),
                        ),
                      ],
                    )));
      });

      safeSetState(() {
        _showActions = true;
      });
      Overlay.of(context).insert(_mobileMenuOverlayEntry!);
      _messageActionsAnimationController.forward();
      _overlayMessageScaleAnimationController.forward(from: 0);
    } else {
      _messageActionsAnimationController.reverse().then((_) {
        safeSetState(() {
          _showActions = false;
        });
        _mobileMenuOverlayEntry!.remove();
        _mobileMenuOverlayEntry = null;
      });
    }
  }

  _onLongPressMessageOnMobile() async {
    if (widget.data.isMergeMessage) {
      return;
    }
    if (widget.data.inSelectMode) {
      widget.methods.onSelectMessage();
      return;
    }

    _listMessageScaleAnimationController.forward();
    // show menu
    _showMobileMessageActions();
    // hide keyboard
    FocusScope.of(context).requestFocus(FocusNode());
  }

  /// Mirror of [_onLongPressMessageOnMobile] for desktop secondary-tap (right-click).
  /// Routes through the same action-sheet path so right-click on a message bubble
  /// in non-desktop screen modes opens the standard message menu.
  void _onSecondaryTapMessageOnMobile(TapUpDetails details) {
    if (widget.data.isMergeMessage) {
      return;
    }
    if (widget.data.inSelectMode) {
      widget.methods.onSelectMessage();
      return;
    }

    _listMessageScaleAnimationController.forward();
    _showMobileMessageActions();
    FocusScope.of(context).requestFocus(FocusNode());
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: _showActions ? 0 : 1,
          child: GestureDetector(
            key: _messageGestureKey,
            onLongPress: _onLongPressMessageOnMobile,
            onSecondaryTapUp: _onSecondaryTapMessageOnMobile,
            child: ScaleTransition(
              scale: _listMessageScaleAnimation,
              child: widget.methods.getMessageItemWidget(
                renderOnMenuPreview: false,
                key: _messageKey,
              ),
            ),
          ),
        ),
        Offstage(
          offstage: true,
          // Measurement-only copy: NO automation keys (see [_buildMobileMenuItems]
          // keyed param) so it never duplicates the visible menu's
          // `message_menu_item:<action>` handles.
          child: _buildMobileMenuWidget(key: _reactionKey, keyed: false),
        ),
      ],
    );
  }

  void _removeDesktopMenu() {
    _desktopMenuOverlayEntry?.remove();
    _desktopMenuOverlayEntry = null;
  }

  void _openDesktopMessageMenu(tapDownDetails) async {
    if (_desktopMenuOverlayEntry != null) {
      _removeDesktopMenu();
    }
    if (_menuHeight == null || _menuWidth == null) {
      // Get the menu height using GlobalKey
      final RenderBox menuBox = _menuKey.currentContext!.findRenderObject() as RenderBox;
      _menuHeight = menuBox.size.height;
      _menuWidth = menuBox.size.width;
    }

    if (_reactionHeight == null || _reactionWidth == null) {
      // Get the reaction height using GlobalKey
      final RenderBox reactionBox = _reactionKey.currentContext!.findRenderObject() as RenderBox;
      _reactionHeight = reactionBox.size.height;
      _reactionWidth = reactionBox.size.width;
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final tapDetails = tapDownDetails;

    final double menuDx = min(tapDetails.dx, screenWidth - (_menuWidth ?? 100));
    final double menuDy = min(tapDetails.dy as double, screenHeight - (_menuHeight ?? 320)).toDouble();

    final double reactionDx = min(screenWidth - (_reactionWidth ?? 254) , max(tapDetails.dx - (_reactionWidth ?? 254) + _menuWidth, (_reactionWidth ?? 254) + 4));
    // Floor at the top safe inset: in a 600 px-tall window a menu pinned to
    // the bottom put the reaction bar above y=0.
    final double reactionDy = max(
        MediaQuery.paddingOf(context).top + 8,
        min((menuDy - (_reactionHeight ?? 50) - 4), max(tapDetails.dy - (_reactionHeight ?? 50) - 4, 8.toDouble())));

    _desktopMenuOverlayEntry = OverlayEntry(
        builder: (context) => TencentCloudChatThemeWidget(
            build: (context, colorTheme, textStyle) => Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        _removeDesktopMenu();
                      },
                      onSecondaryTap: () {
                        _removeDesktopMenu();
                      },
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                    Positioned(left: menuDx, top: menuDy, child: _buildDesktopMenu()),
                    Positioned(left: reactionDx, top: reactionDy, child: _buildReactionBar()),

                  ],
                )));
    Overlay.of(context).insert(_desktopMenuOverlayEntry!);
  }

  @override
  Widget desktopBuilder(BuildContext context) {
    return Column(
      children: [
        Listener(
          onPointerDown: (PointerDownEvent event) {
            if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) {
              _openDesktopMessageMenu(event.position);
            }
          },
          child: widget.methods.getMessageItemWidget(
            renderOnMenuPreview: false,
            key: _messageKey,
          ),
        ),
        Offstage(
          offstage: true,
          // Measurement-only copy: NO automation keys (see [_buildDesktopMenu]
          // keyed param) so it never duplicates the visible menu's
          // `message_menu_item:<action>` handles.
          child: _buildDesktopMenu(key: _menuKey, keyed: false),
        ),
        Offstage(
          offstage: true,
          child: _buildReactionBar(key: _reactionKey),
        ),
      ],
    );
  }

  @override
  Widget tabletAppBuilder(BuildContext context) {
    return defaultBuilder(context);
  }
}

/// Maps a message-menu option to a stable, locale-independent action token used
/// in `ValueKey('message_menu_item:<action>')` for UI automation.
///
/// The built-in UIKit options carry an `id` like `_uikit_copy_message`; this
/// strips the `_uikit_` prefix and `_message` suffix and normalizes a few names
/// to the canonical action vocabulary the harness targets
/// ({delete, copy, forward, reply, recall, multiSelect, ...}). Returns `null`
/// for custom options added via `additionalMessageMenuOptions`: their id/label
/// is arbitrary and two such entries could collide into duplicate sibling
/// ValueKeys (a Flutter error), so only the known built-ins are keyed.
String? tencentCloudChatMessageMenuActionForOption(
    TencentCloudChatMessageGeneralOptionItem option) {
  final String? id = option.id;
  switch (id) {
    case '_uikit_copy_message':
      return 'copy';
    case '_uikit_quote_message':
      return 'reply';
    case '_uikit_multi_message':
      return 'multiSelect';
    case '_uikit_forward_message':
      return 'forward';
    case '_uikit_delete_message':
      return 'delete';
    case '_uikit_revoke_message':
      return 'recall';
    case '_uikit_read_receipt':
      return 'readReceipt';
    case '_uikit_translate':
      return 'translate';
    case '_uikit_convert_to_text':
      return 'convertToText';
    case '_uikit_reveal_file_location':
      return 'revealFileLocation';
    default:
      // Custom / additional options are intentionally NOT keyed (see above):
      // arbitrary id/label can produce duplicate sibling keys.
      return null;
  }
}

/// The stable automation [Key] for a built-in message-menu option, or `null`
/// for a custom/additional option (left unkeyed to avoid duplicate siblings).
Key? tencentCloudChatMessageMenuKeyForOption(
    TencentCloudChatMessageGeneralOptionItem option) {
  final action = tencentCloudChatMessageMenuActionForOption(option);
  return action == null ? null : ValueKey('message_menu_item:$action');
}
