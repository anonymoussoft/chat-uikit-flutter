import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:tencent_cloud_chat_common/utils/sdk_const.dart';
import 'package:universal_html/html.dart' as html;

import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_config.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_platform_adapter.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/color_base.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_code_info.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_message/common/for_desktop/file_tools.dart';
import 'package:tencent_cloud_chat_message/common/for_desktop/image_tools.dart';
import 'package:tencent_cloud_chat_message/common/for_desktop/scratch_file_store.dart';
import 'package:tencent_cloud_chat_message/common/text_compiler/tencent_cloud_chat_message_text_compiler.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_controller.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/tencent_cloud_chat_message_draft_coordinator.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/message_reply/tencent_cloud_chat_message_input_reply_container.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/select_mode/tencent_cloud_chat_message_input_select_mode_container.dart';

// Tox protocol max payload for tox_friend_send_message() is 1372 UTF-8 bytes;
// the warning threshold (~80%) gives the user breathing room before the cap.
const int _kToxMaxMessageBytes = 1372;
const int _kToxByteCounterThreshold = 1097;

/// Real-UI automation seam (debug only): set the composer text and invoke the
/// exact production send path (mirrors the Enter-key handler). Lets the L3
/// `l3_composer_send` tool drive the DESKTOP composer purely over the VM service,
/// so a macOS peer paired with an iOS Simulator never needs osascript keyboard
/// focus (which would background the Simulator and get the sim peer RBS-killed).
void Function(String text)? debugRealUiDesktopComposerSendText;

/// Test-only seam: the currently-mounted desktop message composer registers its
/// real Enter-to-send action here (debug builds only) so the headless real-UI
/// harness can drive a genuine composer send WITHOUT a synthetic
/// RawKeyDownEvent (Windows has no OS-level key injection, and synthetic
/// `enterText` cannot reach the FocusNode.onKey Enter path). Invoking it runs
/// the EXACT same code as pressing Enter — real field text, mention state, byte
/// validation, `inputMethods.sendTextMessage`, and field clear. Null whenever no
/// desktop composer is mounted; never set in release builds.
void Function()? debugRealUiDesktopComposerSend;

/// Companion to [debugRealUiDesktopComposerSend] (debug builds only): set the
/// mounted desktop composer's text field DIRECTLY, bypassing synthetic
/// `enterText`. On Windows the headless harness has no OS key injection and
/// flutter_skill `enterText` does not reliably reach this composer's
/// [TextEditingController] (the editable focuses from a coordinate tap macOS
/// can do but the headless Windows path cannot), so a typed-then-Enter flow
/// sends an EMPTY message. This setter writes the controller text + byte count
/// deterministically, so `set-text + send` reproduces a real composer send for
/// multi-line / long / emoji text. Null when no desktop composer is mounted.
void Function(String text)? debugRealUiDesktopComposerSetText;

/// Debug-only: send an @-mention to a group member WITHOUT rendering the mention
/// panel. The panel only appears from real char-by-char "@" typing through
/// `_onTextChanged`, which the headless Windows harness cannot drive; this
/// reproduces the exact data a real select-member-then-send produces — appends
/// `{userID}` to the composer's `_mentionedUsers`, inserts the `@<label>` text,
/// and ships it via the production `_submitDesktopSend` (real `sendTextMessage`
/// with `mentionedUsers`). Null when no desktop composer is mounted.
void Function(String userID, String label, String text)?
    debugRealUiDesktopComposerMentionSend;

/// Debug-only: stage a pasted image from an already-materialized file path and
/// open the production desktop send-image confirm dialog. The OS clipboard +
/// Ctrl/Cmd+V are not headless-automatable on the Windows VM (the driver's
/// clipboard lives in a different window-station), so this invokes the SAME
/// `sendImageOnDesktop` the real `_handlePasteResource` calls, with an image the
/// harness wrote to a path the app can read. Null when no composer is mounted.
void Function(String imagePath)? debugRealUiDesktopPasteImagePath;

/// Debug-only: WHICH conversation the mounted desktop composer is bound to —
/// its `inputData.userID` / `groupID`, read live. The desktop twin of
/// `debugRealUiMobileComposerBinding`: toxee's `l3_composer_send` reports it as
/// `boundUserID` / `boundGroupID` so a driver can gate a send on the composer
/// actually being the target conversation's, instead of trusting
/// `currentConversation` (which the app binds before the composer remounts).
/// Null when no desktop composer is mounted.
({String? userID, String? groupID}) Function()?
    debugRealUiDesktopComposerBinding;

class TencentCloudChatMessageInputDesktop extends StatefulWidget {
  final MessageInputBuilderData inputData;
  final MessageInputBuilderMethods inputMethods;
  final String? statusText;
  final bool debugDraftPersistenceOnly;

  const TencentCloudChatMessageInputDesktop({
    super.key,
    required this.inputData,
    required this.inputMethods,
    this.statusText,
    this.debugDraftPersistenceOnly = false,
  });

  @override
  State<TencentCloudChatMessageInputDesktop> createState() =>
      _TencentCloudChatMessageInputDesktopState();
}

class _TencentCloudChatMessageInputDesktopState
    extends TencentCloudChatState<TencentCloudChatMessageInputDesktop> {
  final List<({String userID, String label})> _mentionedUsers = [];
  late ScrollController _scrollController;
  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _textEditingFocusNode = FocusNode();
  String _inputText = "";
  bool _isComposingText = false;
  bool _isEditingAtSearchWords = false;
  int _atTagIndex = -1;
  double _inputWidth = 900;
  int _maxLines = 6;
  int _byteCount = 0;
  String listenerUUID = "";
  late final TencentCloudChatMessageDraftCoordinator _draftCoordinator;

  @override
  void initState() {
    super.initState();
    _draftCoordinator = TencentCloudChatMessageDraftCoordinator(
      updateConversationPreview: _setConversationDraft,
    );
    _cancelEditingMemberMentionStatus();
    _textEditingFocusNode.onKey = _handleKeyEvent;
    if (kDebugMode) {
      // Expose this composer's real Enter-send to the headless real-UI harness.
      debugRealUiDesktopComposerSend = _desktopSendTearoff;
      debugRealUiDesktopComposerSetText = _desktopSetTextTearoff;
      debugRealUiDesktopComposerMentionSend = _desktopMentionSendTearoff;
      debugRealUiDesktopPasteImagePath = _desktopPasteImagePathTearoff;
      debugRealUiDesktopComposerBinding = _desktopBindingTearoff;
    }
    _textEditingFocusNode.requestFocus();
    _scrollController = ScrollController();
    _textEditingController.addListener(() {
      _isComposingText = _textEditingController.value.composing.start != -1;
    });
    if (listenerUUID.isNotEmpty) {
      removeUIKitListener();
    }
    if (!widget.debugDraftPersistenceOnly) {
      addUIKitListener();
    }
    _initPasteOnWeb();
    if (kDebugMode) {
      // Real-UI L3 composer-SEND seam: set the text then invoke the exact
      // production send path (same as the Enter-key handler below). Lets a macOS
      // peer send via the VM service without osascript keyboard focus.
      // A stored tearoff (not an inline closure) so dispose can clear the slot
      // only while it is still OURS — on a conversation switch the successor
      // composer mounts and registers BEFORE this one is disposed.
      debugRealUiDesktopComposerSendText = _desktopSendTextTearoff;
    }
    _setDraftContext();
    unawaited(_loadDraft());
  }

  void uikitListener(Map<String, dynamic> data) {
    if (data.containsKey("eventType")) {
      if (data["eventType"] == "stickClick") {
        if (data["type"] == 0) {
          var space = "";
          if (_textEditingController.text == "") {
            space = " ";
          }
          _textEditingController.text =
              "$space${_textEditingController.text}${data["name"]}";
          _textEditingFocusNode.requestFocus();
        }
        widget.inputMethods.closeSticker();
      }
    }
  }

  String addUIKitListener() {
    var id = TencentCloudChat.instance.chatSDKInstance.messageSDK
        .addUIKitListener(listener: uikitListener);
    listenerUUID = id;
    return id;
  }

  void removeUIKitListener() {
    if (listenerUUID.isNotEmpty) {
      return TencentCloudChat.instance.chatSDKInstance.messageSDK
          .removeUIKitListener(listenerID: listenerUUID);
    }
  }

  @override
  void dispose() {
    if (identical(debugRealUiDesktopComposerSend, _desktopSendTearoff)) {
      debugRealUiDesktopComposerSend = null;
    }
    if (identical(debugRealUiDesktopComposerSetText, _desktopSetTextTearoff)) {
      debugRealUiDesktopComposerSetText = null;
    }
    if (identical(debugRealUiDesktopComposerMentionSend,
        _desktopMentionSendTearoff)) {
      debugRealUiDesktopComposerMentionSend = null;
    }
    if (identical(
        debugRealUiDesktopPasteImagePath, _desktopPasteImagePathTearoff)) {
      debugRealUiDesktopPasteImagePath = null;
    }
    if (identical(debugRealUiDesktopComposerBinding, _desktopBindingTearoff)) {
      debugRealUiDesktopComposerBinding = null;
    }
    if (identical(
        debugRealUiDesktopComposerSendText, _desktopSendTextTearoff)) {
      debugRealUiDesktopComposerSendText = null;
    }
    super.dispose();
    _textEditingController.dispose();
    _textEditingFocusNode.dispose();
    removeUIKitListener();
  }

  // Stable tearoff so dispose can verify ownership before clearing the global
  // hook (a later composer may have overwritten it).
  late final void Function() _desktopSendTearoff = _submitDesktopSend;
  late final void Function(String) _desktopSetTextTearoff = _setDesktopText;
  late final void Function(String, String, String) _desktopMentionSendTearoff =
      _mentionSend;
  late final void Function(String) _desktopPasteImagePathTearoff =
      _pasteImagePath;
  late final void Function(String) _desktopSendTextTearoff = _sendDesktopText;
  late final ({String? userID, String? groupID}) Function()
      _desktopBindingTearoff = _desktopBinding;

  /// Body of [debugRealUiDesktopComposerSendText]: set the text then invoke
  /// the exact production send path (same as the Enter-key handler). Lets a
  /// macOS peer send via the VM service without osascript keyboard focus.
  void _sendDesktopText(String text) {
    if (!mounted) return;
    _setDesktopText(text);
    _submitDesktopSend();
  }

  ({String? userID, String? groupID}) _desktopBinding() =>
      (userID: widget.inputData.userID, groupID: widget.inputData.groupID);

  /// Send an @-mention to [userID] (display [label]) followed by [text], exactly
  /// as a real select-member-then-send would: the userID rides in
  /// `mentionedUsers` and the visible bubble text carries the `@<label>` tag.
  void _mentionSend(String userID, String label, String text) {
    _mentionedUsers.add((userID: userID, label: label));
    _setDesktopText('@$label $text');
    _submitDesktopSend();
  }

  /// Stage [imagePath] through the production desktop send-image confirm dialog
  /// (same call the real Ctrl/Cmd+V paste handler makes).
  void _pasteImagePath(String imagePath) {
    TencentCloudChatDesktopImageTools.sendImageOnDesktop(
      context: context,
      imagePath: imagePath,
      currentConversationShowName:
          widget.inputData.currentConversationShowName,
      sendImageMessage: widget.inputMethods.sendImageMessage,
    );
  }

  /// Deterministically populate the composer's text field (used by the headless
  /// real-UI harness via [debugRealUiDesktopComposerSetText]). Mirrors the state
  /// a real keystroke sequence leaves: controller text, the mirrored `_inputText`
  /// the byte-count UI reads, focus, and `_byteCount`.
  void _setDesktopText(String text) {
    _textEditingController.text = text;
    _textEditingController.selection =
        TextSelection.collapsed(offset: text.length);
    _inputText = text;
    _draftCoordinator.markEdited();
    _updateDraft(text);
    _textEditingFocusNode.requestFocus();
    safeSetState(() {
      _byteCount = utf8.encode(text).length;
    });
  }

  /// The exact Enter-to-send action of the desktop composer, factored out so the
  /// headless real-UI harness can invoke it via [debugRealUiDesktopComposerSend]
  /// without an OS/synthetic key event. Identical behaviour to pressing Enter.
  void _submitDesktopSend() {
    final text = _textEditingController.text;
    if (text.isEmpty || utf8.encode(text).length > _kToxMaxMessageBytes) {
      return;
    }
    final mentionedUsers = _mentionedUsers.map((e) => e.userID).toList();
    _draftCoordinator.sendAndClear(
      text: text,
      sendMessage: () => widget.inputMethods.sendTextMessage(
        text: text,
        mentionedUsers: mentionedUsers,
      ),
      currentText: () => _textEditingController.text,
      isActive: () => mounted,
      clearComposer: () {
        _mentionedUsers.clear();
        _replaceComposerText("");
        _cancelEditingMemberMentionStatus();
      },
      onError: (error) {
        debugPrint('Failed to send text message: $error');
      },
    );
  }

  @override
  void didUpdateWidget(TencentCloudChatMessageInputDesktop oldWidget) {
    super.didUpdateWidget(oldWidget);
    final draftContextChanged = _setDraftContext();
    if (draftContextChanged) {
      _mentionedUsers.clear();
      _replaceComposerText(widget.inputData.specifiedMessageText ?? "");
      unawaited(_loadDraft());
    }
    if (!draftContextChanged &&
        widget.inputData.specifiedMessageText !=
        oldWidget.inputData.specifiedMessageText) {
      _draftCoordinator.invalidateLoad();
      _replaceComposerText(widget.inputData.specifiedMessageText ?? "");
      _mentionedUsers.clear();
      _mentionedUsers
          .addAll((widget.inputData.membersNeedToMention ?? []).map(((e) {
        final targetMemberLabel = _getShowName(e);
        return (label: targetMemberLabel, userID: e.userID);
      })));
      _textEditingFocusNode.requestFocus();
    } else if (!identical(widget.inputData.membersNeedToMention,
            oldWidget.inputData.membersNeedToMention) &&
        widget.inputData.membersNeedToMention != null) {
      // toxee: `membersNeedToMention` is an EVENT — the layout container hands
      // the composer a fresh list per panel selection and never clears it.
      // Comparing by value ignored a second selection of the same member
      // (identical list contents) and silently inserted nothing; comparing by
      // identity consumes every selection exactly once.
      _addMentionedUsers(
          groupMembersInfo: widget.inputData.membersNeedToMention);
    }

    if (widget.inputData.enableReplyWithMention &&
        oldWidget.inputData.repliedMessage != widget.inputData.repliedMessage &&
        widget.inputData.repliedMessage != null &&
        TencentCloudChatUtils.checkString(
                widget.inputData.repliedMessage!.sender) !=
            null) {
      if (!(widget.inputData.repliedMessage?.isSelf ?? true) &&
          TencentCloudChatUtils.checkString(widget.inputData.groupID) != null) {
        _addMentionedUsers(message: widget.inputData.repliedMessage!);
      } else {
        _textEditingFocusNode.requestFocus();
      }
    }
  }

  _initPasteOnWeb() {
    try {
      if (TencentCloudChatPlatformAdapter().isWeb) {
        html.window.addEventListener('paste', (event) {
          _handlePasteOnWeb(event as html.ClipboardEvent);
        });
      }
    } catch (e) {
      // ignore: avoid_print
      debugPrint(e.toString());
    }
  }

  Future<void> _handlePasteOnWeb(html.ClipboardEvent event) async {
    try {
      if (event.clipboardData!.files!.isNotEmpty) {
        html.File imageFile = event.clipboardData!.files![0];
        _sendFileUseJs(imageFile);
      }
    } catch (e) {
      // ignore: avoid_print
      debugPrint("Paste image failed: ${e.toString()}");
    }
  }

  _sendFileUseJs(html.File file) {
    final mimeType = file.type.split('/');
    final type = mimeType[0];
    final blobUrl = html.Url.createObjectUrl(file);
    if (type == 'image') {
      TencentCloudChatDesktopImageTools.sendImageOnDesktop(
        context: context,
        imagePath: blobUrl,
        imageSize: const Size(500, 500),
        imageName: file.name,
        currentConversationShowName:
            widget.inputData.currentConversationShowName,
        sendImageMessage: widget.inputMethods.sendImageMessage,
      );
    }
  }

  Offset _getAtPosition(String text, int atPlace) {
    final textBeforeAt = text.substring(0, atPlace + 1);
    final textPainter = TextPainter(
      text: TextSpan(text: textBeforeAt, style: const TextStyle(fontSize: 14)),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    textPainter.layout(maxWidth: _inputWidth);
    final TextPosition lastLineOffset = textPainter
        .getPositionForOffset(Offset(textPainter.width, textPainter.height));
    final Offset caretPosition =
        textPainter.getOffsetForCaret(lastLineOffset, Rect.zero);
    final dx = min(_inputWidth - 180, caretPosition.dx + 16);
    final dy = max(24, 21 * _maxLines - caretPosition.dy).toDouble();

    return Offset(dx, dy);
  }

  void _onTextChanged(String newText) async {
    widget.inputMethods.closeSticker();
    final newText = _textEditingController.text;
    _draftCoordinator.markEdited();

    /// Dealing with mentioning member in group
    if (TencentCloudChatUtils.checkString(widget.inputData.groupID) != null) {
      final ({String character, int index, bool isAddText}) compareResult =
          TencentCloudChatUtils.compareString(
        _inputText,
        newText,
      );

      /// Add word
      if (compareResult.isAddText) {
        if (compareResult.character == "@") {
          final atPosition = _getAtPosition(newText, compareResult.index);
          widget.inputMethods.setDesktopMentionBoxPositionX(atPosition.dx);
          widget.inputMethods.setDesktopMentionBoxPositionY(atPosition.dy);
          _isEditingAtSearchWords = true;
          _atTagIndex = compareResult.index;
        }
      } else if (!compareResult.isAddText) {
        /// Delete word
        final atIndex =
            _inputText.lastIndexOf('@', max(0, compareResult.index - 1));
        final removedLabelList = [];
        if (atIndex != -1 && compareResult.character != '@') {
          removedLabelList
              .add(_inputText.substring(atIndex + 1, compareResult.index));

          int spaceIndex = compareResult.index;
          int count = 0;

          while (spaceIndex != -1 && count < 5) {
            spaceIndex = _inputText.indexOf(' ', spaceIndex + 1);
            if (spaceIndex != -1) {
              removedLabelList
                  .add(_inputText.substring(atIndex + 1, spaceIndex));
              count++;
            } else {
              removedLabelList.add(_inputText.substring(atIndex + 1));
            }
          }

          final mentionedUserExist = _mentionedUsers
              .any((user) => removedLabelList.contains(user.label));

          if (mentionedUserExist) {
            final mentionedUser = _mentionedUsers
                .firstWhere((user) => removedLabelList.contains(user.label));
            final updatedText = newText.replaceRange(
                atIndex, atIndex + 1 + mentionedUser.label.length, '');
            _textEditingController.text = updatedText;
            _textEditingController.selection =
                TextSelection.collapsed(offset: atIndex);
            _mentionedUsers
                .removeWhere((user) => user.label == mentionedUser.label);
          }
        }
      }

      /// Deal with editing mention member keyword
      if (_isEditingAtSearchWords &&
          _atTagIndex > -1 &&
          (compareResult.isAddText
              ? compareResult.index >= _atTagIndex
              : compareResult.index > _atTagIndex)) {
        String keyword = newText.substring(_atTagIndex + 1,
            compareResult.index + (compareResult.isAddText ? 1 : 0));

        List<V2TimGroupMemberFullInfo> showAtMemberList =
            widget.inputData.groupMemberList
                .where((element) {
                  final showName = (_getShowName(element)).toLowerCase();
                  return showName.contains(keyword.toLowerCase()) &&
                      TencentCloudChatUtils.checkString(showName) != null;
                })
                .whereType<V2TimGroupMemberFullInfo>()
                .toList();
        if (showAtMemberList.isEmpty &&
            widget.inputData.groupMemberList.isEmpty) {
          TencentCloudChat.instance.callbacks.onUserNotificationEvent(
            TencentCloudChatComponentsEnum.message,
            TencentCloudChatCodeInfo.retrievingGroupMembers,
          );
        }
        showAtMemberList.sort(
            (V2TimGroupMemberFullInfo userA, V2TimGroupMemberFullInfo userB) {
          final isUserAIsGroupAdmin = userA.role == 300;
          final isUserAIsGroupOwner = userA.role == 400;

          final isUserBIsGroupAdmin = userB.role == 300;
          final isUserBIsGroupOwner = userB.role == 400;

          final String userAName = _getShowName(userA);
          final String userBName = _getShowName(userB);

          if (isUserAIsGroupOwner != isUserBIsGroupOwner) {
            return isUserAIsGroupOwner ? -1 : 1;
          }

          if (isUserAIsGroupAdmin != isUserBIsGroupAdmin) {
            return isUserAIsGroupAdmin ? -1 : 1;
          }

          return userAName.compareTo(userBName);
        });

        if (widget.inputData.isGroupAdmin &&
            showAtMemberList.isNotEmpty &&
            keyword.isEmpty) {
          showAtMemberList = [
            V2TimGroupMemberFullInfo(
                userID: SDKConst.sdkAtAllUserID, nickName: tL10n.all),
            ...showAtMemberList,
          ];
        }

        widget.inputMethods
            .setCurrentFilteredMembersListForMention(showAtMemberList);
        widget.inputMethods.setActiveMentionIndex(0);
      } else {
        _cancelEditingMemberMentionStatus();
      }
    }

    /// End
    _inputText = _textEditingController.text;

    final nextByteCount = utf8.encode(_inputText).length;
    if (nextByteCount != _byteCount) {
      safeSetState(() {
        _byteCount = nextByteCount;
      });
    }
    _updateDraft(_inputText);
  }

  bool _setDraftContext() {
    return _draftCoordinator.updateContext(
      topicID: widget.inputData.topicID,
      userID: widget.inputData.userID,
      groupID: widget.inputData.groupID,
    );
  }

  Future<void> _loadDraft() {
    final initialText = _textEditingController.text;
    return _draftCoordinator.loadDraft(
      initialText: initialText,
      currentText: () => _textEditingController.text,
      isActive: () => mounted,
      applyText: _replaceComposerText,
    );
  }

  void _replaceComposerText(String text) {
    _textEditingController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputText = text;
    safeSetState(() {
      _byteCount = utf8.encode(text).length;
    });
  }

  void _updateDraft(String draftText) {
    _draftCoordinator.saveDraft(draftText);
  }

  void _setConversationDraft(String conversationID, String draft) {
    final controller = widget.inputMethods.controller;
    if (controller is TencentCloudChatMessageController) {
      unawaited(controller.setDraft(conversationID, draft));
    }
  }

  final GlobalKey desktopInputKey = GlobalKey();

  List<Widget> _generateBarIcons(TencentCloudChatThemeColors theme) {
    return widget.inputData.attachmentOptions.map((e) {
      final GlobalKey toolbarKey = GlobalKey();
      final Widget iconContainer = Container(
        key: toolbarKey,
        margin: const EdgeInsets.only(right: 10),
        child: InkWell(
          onTapUp: (TapUpDetails detail) {
            RenderBox? renderBox =
                desktopInputKey.currentContext?.findRenderObject() as RenderBox;
            RenderBox? toolBarRenderBox =
                toolbarKey.currentContext?.findRenderObject() as RenderBox;
            var offset = detail.localPosition;
            // The panel is a Positioned child of the message-pane Stack, so
            // its X must be pane-relative. detail.localPosition is ICON-local
            // (0..~24), which parked the panel at the pane's left edge. This
            // input root spans the pane width, so its local space == pane space.
            final RenderObject? inputRoot = context.findRenderObject();
            final double paneX = inputRoot is RenderBox
                ? inputRoot
                    .globalToLocal(
                        toolBarRenderBox.localToGlobal(Offset.zero))
                    .dx
                : offset.dx;

            e.onTap(
              offset: Offset(
                  paneX,
                  renderBox.size.height +
                      toolBarRenderBox.size.height +
                      20), // 20 为margin
            );
          },
          child: Tooltip(
            preferBelow: false,
            message: e.label,
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(2)),
              padding: const EdgeInsets.all(4),
              child: () {
                if (e.iconAsset != null) {
                  final type = e.iconAsset!.path
                      .split(".")[e.iconAsset!.path.split(".").length - 1];
                  if (type == "svg") {
                    return SvgPicture.asset(
                      e.iconAsset!.path,
                      package: e.iconAsset!.package,
                      width: 16,
                      height: 16,
                      colorFilter: ui.ColorFilter.mode(
                        theme.secondaryTextColor,
                        ui.BlendMode.srcIn,
                      ),
                    );
                  }
                  return Image.asset(
                    e.iconAsset!.path,
                    package: e.iconAsset!.package,
                    width: 16,
                    height: 16,
                  );
                }
                if (e.icon != null) {
                  return Icon(
                    e.icon,
                    color: theme.inputAreaIconColor.withOpacity(0.6),
                    size: 20,
                  );
                }
              }(),
            ),
          ),
        ),
      );
      // Wrap data-driven toolbar options with stable selectors for real-UI
      // automation, while preserving the load-bearing `toolbarKey` GlobalKey used
      // for panel offset math.
      final automationKey = switch (e.iconAsset?.path) {
        "lib/assets/send_file.svg" =>
          const ValueKey('message_attachment_file_button'),
        "lib/assets/send_image.svg" =>
          const ValueKey('message_attachment_image_button'),
        "lib/assets/message_search.svg" =>
          const ValueKey('message_attachment_search_button'),
        "lib/assets/send_face.svg" => const ValueKey('sticker_panel_button'),
        _ => null,
      };
      final appAutomationKey = automationKey ??
          switch (e.icon) {
            Icons.attach_file =>
              const ValueKey('message_attachment_file_button'),
            Icons.photo_outlined =>
              const ValueKey('message_attachment_photo_button'),
            Icons.videocam_outlined =>
              const ValueKey('message_attachment_video_button'),
            Icons.qr_code_2 =>
              const ValueKey('message_attachment_personal_card_button'),
            _ => null,
          };
      if (appAutomationKey != null) {
        return KeyedSubtree(
          key: appAutomationKey,
          child: iconContainer,
        );
      }
      return iconContainer;
    }).toList();
  }

  List<Widget> _generateControlBar(TencentCloudChatThemeColors theme) {
    return _generateBarIcons(theme);
  }

  String _getShowName(V2TimGroupMemberFullInfo? item) {
    return TencentCloudChatUtils.checkStringWithoutSpace(item?.nameCard) ??
        TencentCloudChatUtils.checkStringWithoutSpace(item?.nickName) ??
        TencentCloudChatUtils.checkStringWithoutSpace(item?.userID) ??
        "";
  }

  void _cancelEditingMemberMentionStatus() {
    _isEditingAtSearchWords = false;
    _atTagIndex = -1;
    widget.inputMethods.setCurrentFilteredMembersListForMention([]);
    widget.inputMethods.setActiveMentionIndex(-1);
  }

  void _addMentionedUsers(
      {V2TimMessage? message,
      List<V2TimGroupMemberFullInfo>? groupMembersInfo}) {
    final currentText = _textEditingController.text;
    final isValid = (groupMembersInfo ?? []).isNotEmpty ||
        TencentCloudChatUtils.checkString(message?.sender) != null;
    if (isValid) {
      if (_isEditingAtSearchWords && groupMembersInfo?.length == 1) {
        final showName = _getShowName(groupMembersInfo!.first);
        _replaceAtTag(showName);
        _mentionedUsers
            .add((label: showName, userID: groupMembersInfo.first.userID));
        _cancelEditingMemberMentionStatus();
        _textEditingFocusNode.requestFocus();
      } else {
        String addText = "";
        groupMembersInfo?.forEach((element) {
          final targetMemberLabel = _getShowName(element);
          _mentionedUsers
              .add((label: targetMemberLabel, userID: element.userID));
          addText += "@$targetMemberLabel ";
        });
        if (message?.sender != null) {
          final String targetMemberLabel =
              TencentCloudChatUtils.checkString(message?.nameCard) ??
                  TencentCloudChatUtils.checkString(message?.nickName) ??
                  message!.sender!;
          _mentionedUsers
              .add((label: targetMemberLabel, userID: message!.sender!));
          addText += "@$targetMemberLabel ";
        }

        /// Insert mentionText after the "@" character
        ///
        final cursorPosition = max(0, _textEditingController.selection.start);
        final updatedText = currentText.substring(0, cursorPosition) +
            addText +
            currentText.substring(cursorPosition);
        _textEditingController.text = updatedText;
        _inputText = updatedText;
        _textEditingController.selection =
            TextSelection.collapsed(offset: cursorPosition + addText.length);
        _textEditingFocusNode.requestFocus();
      }
    }
  }

  void _replaceAtTag(String selectedMember) {
    // toxee: the selection is NOT guaranteed valid here. Tapping a row of the
    // mention panel can move focus off the field, and a programmatic
    // `controller.text = …` leaves the selection at -1; the old code then
    // called `lastIndexOf('@', -2)`, which throws RangeError inside the
    // gesture callback and inserts nothing. Fall back to the caret at the end
    // of the text and to the LAST '@' in the text.
    final text = _textEditingController.text;
    final selection = _textEditingController.selection;
    final hasCursor = selection.isValid &&
        selection.baseOffset >= 0 &&
        selection.baseOffset <= text.length;
    final cursorPosition = hasCursor ? selection.baseOffset : text.length;
    int atIndex =
        cursorPosition > 0 ? text.lastIndexOf('@', cursorPosition - 1) : -1;
    if (atIndex < 0) atIndex = text.lastIndexOf('@');
    if (atIndex < 0) return;
    final replaceEnd = cursorPosition > atIndex ? cursorPosition : text.length;
    final beforeAt = text.substring(0, atIndex);
    final afterAt = text.substring(replaceEnd);
    final updated = '$beforeAt@$selectedMember $afterAt';
    _textEditingController.value = TextEditingValue(
      text: updated,
      selection:
          TextSelection.collapsed(offset: atIndex + selectedMember.length + 2),
    );
    _inputText = updated;
  }

  void _handleMentionUser(V2TimGroupMemberFullInfo memberFullInfo) {
    final String showName = _getShowName(memberFullInfo);
    _mentionedUsers.add((label: showName, userID: memberFullInfo.userID));
    _replaceAtTag(showName);
    _cancelEditingMemberMentionStatus();
    _textEditingFocusNode.requestFocus();
  }

  _handlePasteResource() async {
    final imageBytes = await Pasteboard.image;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      var uuid = DateTime.now().microsecondsSinceEpoch;
      final fileName = 'paste_image_$uuid.png';
      final filePath = await resolveChatScratchFileProvider().writeScratchBytes(
        category: 'clipboard_images',
        suggestedFileName: fileName,
        bytes: imageBytes,
      );

      TencentCloudChatDesktopImageTools.sendImageOnDesktop(
        context: context,
        imagePath: filePath,
        currentConversationShowName:
            widget.inputData.currentConversationShowName,
        sendImageMessage: widget.inputMethods.sendImageMessage,
      );
    } else {
      final List<String> fileList = await Pasteboard.files();

      if (fileList.isNotEmpty) {
        TencentCloudChatDesktopFileTools.sendFileWithConfirmation(
          filesPath: fileList,
          currentConversationShowName:
              widget.inputData.currentConversationShowName,
          sendFileMessage: widget.inputMethods.sendFileMessage,
          context: context,
        );
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, RawKeyEvent event) {
    final isPressEnter = (event.physicalKey == PhysicalKeyboardKey.enter) ||
        (event.physicalKey == PhysicalKeyboardKey.numpadEnter);

    final activeIndex = widget.inputData.activeMentionIndex;
    final showMemberList =
        widget.inputData.currentFilteredMembersListForMention;

    if (TencentCloudChatPlatformAdapter().isDesktop &&
        ((event.isKeyPressed(LogicalKeyboardKey.controlLeft) &&
                event.logicalKey == LogicalKeyboardKey.keyV) ||
            (event.isMetaPressed &&
                event.logicalKey == LogicalKeyboardKey.keyV))) {
      _handlePasteResource();
      return KeyEventResult.ignored;
    } else if (event.runtimeType == RawKeyDownEvent) {
      if (event.physicalKey == PhysicalKeyboardKey.backspace) {
        if (_textEditingController.text.isEmpty && _inputText.isEmpty) {
          widget.inputMethods.clearRepliedMessage();
          return KeyEventResult.handled;
        }
      } else if ((event.isShiftPressed ||
              event.isAltPressed ||
              event.isControlPressed ||
              event.isMetaPressed) &&
          isPressEnter) {
        final offset = _textEditingController.selection.baseOffset;
        _textEditingController.text =
            '${_inputText.substring(0, offset)}\n${_inputText.substring(offset)}';
        _textEditingController.selection =
            TextSelection.fromPosition(TextPosition(offset: offset + 1));
        _inputText = _textEditingController.text;

        return KeyEventResult.handled;
      } else if (isPressEnter) {
        if (!_isComposingText) {
          if (!_isEditingAtSearchWords || showMemberList.isEmpty) {
            _submitDesktopSend();
          } else {
            final V2TimGroupMemberFullInfo? memberInfo =
                showMemberList[activeIndex];
            if (memberInfo != null) {
              _handleMentionUser(memberInfo);
            }
          }
          return KeyEventResult.handled;
        }
      }

      if (event.isKeyPressed(LogicalKeyboardKey.arrowUp) &&
          _isEditingAtSearchWords &&
          showMemberList.isNotEmpty) {
        final newIndex = max(activeIndex - 1, 0);
        widget.inputMethods.setActiveMentionIndex(newIndex);
        widget.inputMethods.desktopInputMemberSelectionPanelScroll
            .scrollToIndex(newIndex, preferPosition: AutoScrollPosition.middle);
        return KeyEventResult.handled;
      }

      if (event.isKeyPressed(LogicalKeyboardKey.arrowDown) &&
          _isEditingAtSearchWords &&
          showMemberList.isNotEmpty) {
        final newIndex = min(activeIndex + 1, showMemberList.length - 1);
        widget.inputMethods.setActiveMentionIndex(newIndex);
        widget.inputMethods.desktopInputMemberSelectionPanelScroll
            .scrollToIndex(newIndex, preferPosition: AutoScrollPosition.middle);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    if (widget.debugDraftPersistenceOnly) {
      return Text(
        _textEditingController.text,
        key: const ValueKey('draft_persistence_text'),
      );
    }
    final TencentCloudChatMessageConfig config =
        TencentCloudChatMessageDataProviderInherited.of(context).config;
    final maxLines = config.desktopMessageInputLines(
      userID: TencentCloudChatMessageDataProviderInherited.of(context).userID,
      groupID: TencentCloudChatMessageDataProviderInherited.of(context).groupID,
      topicID: TencentCloudChatMessageDataProviderInherited.of(context).topicID,
    );
    _maxLines = maxLines;

    return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
      _inputWidth = constraints.maxWidth;
      return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Container(
          color: colorTheme.backgroundColor,
          child: AnimatedSwitcher(
            switchInCurve: Curves.ease,
            switchOutCurve: Curves.ease,
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: const Offset(0, 0),
                ).animate(animation),
                child: child,
              );
            },
            child: widget.inputData.inSelectMode
                ? const TencentCloudChatMessageInputSelectModeContainer()
                : Column(
                    children: [
                      if (widget.inputData.repliedMessage != null)
                        TencentCloudChatMessageInputReplyContainer(
                          repliedMessage: widget.inputData.repliedMessage,
                        ),
                      SizedBox(
                          height: 1,
                          child: Container(color: colorTheme.dividerColor)),
                      if (TencentCloudChatUtils.checkString(
                              widget.statusText) ==
                          null)
                        Container(
                          color: colorTheme.backgroundColor,
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            // toxee: the desktop voice-recording (Audio) button
                            // was removed — desktop keeps only the unified file
                            // attach + other control-bar icons. Mobile keeps its
                            // own voice recorder.
                            children: [
                              ..._generateControlBar(colorTheme),
                            ],
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 6),
                        constraints: const BoxConstraints(minHeight: 50),
                        child: Row(
                          children: [
                            if (TencentCloudChatUtils.checkString(
                                    widget.statusText) !=
                                null)
                              Expanded(
                                  child: Container(
                                // minHeight: a wrapped status text must grow
                                // the bar, not clip.
                                constraints: const BoxConstraints(minHeight: 35),
                                color: colorTheme.backgroundColor,
                                alignment: Alignment.center,
                                child: Text(
                                  widget.statusText!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: colorTheme.secondaryTextColor,
                                  ),
                                ),
                              )),
                            if (TencentCloudChatUtils.checkString(
                                    widget.statusText) ==
                                null)
                              Expanded(
                                child: Container(
                                  // Flat composer surface (Feishu reference):
                                  // the text area blends into the input panel
                                  // with no outline box and no focus ring (the
                                  // field's border states are disabled below so
                                  // it never inherits the app-wide blue
                                  // focused-border ring).
                                  decoration: BoxDecoration(
                                    color: colorTheme.inputAreaBackground,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  child: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      ExtendedTextField(
                                        key: desktopInputKey,
                                        scrollController: _scrollController,
                                        autofocus: true,
                                        onChanged: _onTextChanged,
                                        maxLines: maxLines,
                                        minLines: maxLines,
                                        focusNode: _textEditingFocusNode,
                                        keyboardType: TextInputType.multiline,
                                        onEditingComplete: () {
                                          //   // widget.onSubmitted();
                                        },
                                        textAlignVertical:
                                            TextAlignVertical.top,
                                        style: const TextStyle(fontSize: 14),
                                        decoration: InputDecoration(
                                          hoverColor: Colors.transparent,
                                          // Disable every border state so the
                                          // composer never picks up the
                                          // app-wide blue focused-border ring
                                          // (form fields keep it; the chat
                                          // composer is flat in the reference).
                                          border: InputBorder.none,
                                          enabledBorder: InputBorder.none,
                                          focusedBorder: InputBorder.none,
                                          disabledBorder: InputBorder.none,
                                          errorBorder: InputBorder.none,
                                          focusedErrorBorder: InputBorder.none,
                                          // Same placeholder the mobile
                                          // composer shows; without it the
                                          // flat, borderless desktop field
                                          // reads as an empty white band.
                                          hintText: tL10n.sendAMessage,
                                          hintStyle: TextStyle(
                                            color:
                                                colorTheme.secondaryTextColor,
                                          ),
                                          // Fill comes from the flat wrapper.
                                          fillColor: Colors.transparent,
                                          filled: true,
                                          isDense: true,
                                        ),
                                        cursorColor: colorTheme.primaryColor,
                                        controller: _textEditingController,
                                        specialTextSpanBuilder:
                                            TencentCloudChatSpecialTextSpanBuilder(
                                          onTapUrl: (_) {},
                                          stickerPluginInstance: widget
                                              .inputData.stickerPluginInstance,
                                        ),
                                        onTap: () {
                                          widget.inputMethods.closeSticker();
                                        },
                                      ),
                                      if (_byteCount >=
                                          _kToxByteCounterThreshold)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              right: 6, bottom: 2),
                                          child: Text(
                                            '$_byteCount / $_kToxMaxMessageBytes',
                                            style: TextStyle(
                                              fontSize: 11,
                                              // Over the hard cap -> error;
                                              // nearing it -> warning tone
                                              // (#FF8800, no colorTheme warning
                                              // slot).
                                              color: _byteCount >
                                                      _kToxMaxMessageBytes
                                                  ? colorTheme.error
                                                  : const Color(0xFFFF8800),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      );
    });
  }
}
