import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_platform_adapter.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_permission_handlers.dart';
import 'package:tencent_cloud_chat_message/common/text_compiler/tencent_cloud_chat_message_text_compiler.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_controller.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/tencent_cloud_chat_message_draft_coordinator.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/message_reply/tencent_cloud_chat_message_input_reply_container.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_attachment_options.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/mobile/tencent_cloud_chat_message_input_recording.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/select_mode/tencent_cloud_chat_message_input_select_mode_container.dart';

// Tox protocol max payload for tox_friend_send_message() is 1372 UTF-8 bytes;
// the warning threshold (~80%) gives the user breathing room before the cap.
const int _kToxMaxMessageBytes = 1372;
const int _kToxByteCounterThreshold = 1097;

/// L3 real-UI test seam (debug builds only). The mobile composer is an
/// `ExtendedTextField` whose `ExtendedEditableText` does NOT pick up
/// flutter_skill's synthetic `enterText` (setEditingState), so the controller
/// listener (`_onTextChanged`) never fires and the send button never appears —
/// making a real-UI message send undriveable on a phone. The mounted input
/// registers this setter so an automation seam (toxee `l3_composer_set_text`)
/// can populate the field through the controller directly, which DOES fire
/// `_onTextChanged` → reveals `chat_send_button` for a REAL tap. Null in release
/// and whenever no mobile input is mounted.
void Function(String text)? debugRealUiMobileComposerSetText;

/// L3 real-UI test seam (debug builds only): set the composer text AND send it
/// through the SAME `inputMethods.sendTextMessage` path the `chat_send_button`
/// onTap invokes, then clear the composer. On a compact phone the synthetic tap
/// on the send button does not reliably fire its `InkWell.onTap` (the message
/// then never leaves the composer), so this seam performs the real send call
/// directly — the send LOGIC stays the production path; only the final tap
/// gesture is synthesized. Used by toxee `l3_composer_send`. Null in release and
/// whenever no mobile input is mounted.
void Function(String text)? debugRealUiMobileComposerSendText;

/// L3 real-UI test seam (debug builds only): send WHATEVER the composer already
/// holds, through the same production `_submitTextMessage()` path, WITHOUT
/// overwriting the text first. The mobile twin of
/// `debugRealUiDesktopComposerSend`.
///
/// WHY IT IS SEPARATE FROM [debugRealUiMobileComposerSendText]: that seam takes
/// the text as an argument and assigns it, so a driver can only send text it
/// already knows. Text the APP itself put in the field is then unsendable — the
/// @-mention picker (`_submitAtMemberList` rewrites "…@" into "…@<label> ") is
/// exactly that case, and it is unreadable through any seam, so a case that
/// asserts the insertion end-to-end must send the field as-is. Before this,
/// `l3_composer_send` with no `text` fell through to the DESKTOP-only hook and
/// answered `no_active_composer` on every phone/tablet shell.
void Function()? debugRealUiMobileComposerSend;

/// L3 real-UI test seam (debug builds only): WHICH conversation the mounted
/// mobile composer is bound to — its `inputData.userID` / `groupID`, read live.
/// The send seams above are process-global and are re-registered by every
/// composer that mounts, and on a phone the app binds `currentConversation`
/// BEFORE it pushes the new message route (whose composer registers on
/// mount) — so a driver that sends as soon as the conversation id reads right
/// hands its text to the PREVIOUS chat's composer. toxee's `l3_composer_send`
/// reports this as `boundUserID` / `boundGroupID` and drivers gate a group send
/// on it. Null in release and whenever no mobile input is mounted.
({String? userID, String? groupID}) Function()?
    debugRealUiMobileComposerBinding;

class TencentCloudChatMessageInputMobile extends StatefulWidget {
  final MessageInputBuilderData inputData;
  final MessageInputBuilderMethods inputMethods;

  /// Test seam (canonical optional-ctor pattern): resolves whether the current
  /// platform is "mobile" for the press-and-hold voice-record gate in
  /// [_onStartRecording]. Production leaves this null and falls back to the
  /// real [TencentCloudChatPlatformAdapter] check, so behaviour is unchanged on
  /// device. A widget test on a desktop host (where the adapter reports
  /// non-mobile) can inject `() => true` to drive the real record handler.
  final bool Function()? debugIsMobile;
  final bool debugDraftPersistenceOnly;

  const TencentCloudChatMessageInputMobile({
    super.key,
    required this.inputData,
    required this.inputMethods,
    this.debugIsMobile,
    this.debugDraftPersistenceOnly = false,
  });

  @override
  State<TencentCloudChatMessageInputMobile> createState() =>
      _TencentCloudChatMessageInputMobileState();
}

class _TencentCloudChatMessageInputMobileState
    extends TencentCloudChatState<TencentCloudChatMessageInputMobile>
    with TickerProviderStateMixin {
  final GlobalKey<TooltipState> micTooltipKey = GlobalKey<TooltipState>();
  final TencentCloudChatMessageAttachmentOptions _messageAttachmentOptions =
      TencentCloudChatMessageAttachmentOptions();
  final GlobalKey<TencentCloudChatMessageInputRecordingState>
      _recordingWidgetKey = GlobalKey();
  final List<({String userID, String label})> _mentionedUsers = [];

  late AnimationController? _animationController;

  final TextEditingController _textEditingController = TextEditingController();
  final FocusNode _textEditingFocusNode = FocusNode();

  bool isStarted = false;

  Widget stickerWidget = Container();

  bool _showStickerPanel = false;
  bool _showKeyboard = false;
  bool _isRecording = false;
  bool _showSendButton = false;
  Timer? _recordingStarter;
  double? _bottomPadding;
  String _inputText = "";
  int _byteCount = 0;
  String listenerUUID = "";
  late final TencentCloudChatMessageDraftCoordinator _draftCoordinator;
  bool _suppressDraftSave = false;

  /// The composer State currently mounted for each conversation.
  ///
  /// `_onTextChanged` AWAITS the full-screen @-mention picker route
  /// (`onChooseGroupMembers()` → `Navigator.push`). On the tablet
  /// master-detail shell the chat pane is remounted while that route is up, so
  /// the State that opened the picker can be DISPOSED before the picker
  /// returns — at which point `_removeTextInputEvent()` has already cleared and
  /// disposed its `TextEditingController`. Writing the resolved mention into
  /// that dead controller silently loses the user's selection. This registry
  /// lets the opener hand the result to whichever composer is live for the same
  /// conversation instead.
  ///
  /// Keyed by [_composerIdentityKey] — the SAME string
  /// `TencentCloudChatMessageInput` builds the widget `Key` from — so the map
  /// partitions conversations exactly the way the framework does and an insert
  /// can never leak into a different chat.
  static final Map<String, _TencentCloudChatMessageInputMobileState>
      _liveInputs = {};

  /// The conversation this composer belongs to (topic > group > user), or "".
  String get _composerIdentityKey =>
      TencentCloudChatUtils.checkString(widget.inputData.topicID) ??
      TencentCloudChatUtils.checkString(widget.inputData.groupID) ??
      TencentCloudChatUtils.checkString(widget.inputData.userID) ??
      "";

  @override
  void initState() {
    super.initState();
    _draftCoordinator = TencentCloudChatMessageDraftCoordinator(
      updateConversationPreview: _setConversationDraft,
    );
    WidgetsBinding.instance.addObserver(this);
    if (listenerUUID.isNotEmpty) {
      removeUIKitListener();
    }

    if (!widget.debugDraftPersistenceOnly) {
      listenerUUID = addUIKitListener();
    }
    _textEditingController.text = widget.inputData.specifiedMessageText ?? "";
    _inputText = widget.inputData.specifiedMessageText ?? "";
    // must add input event after _textEditingController.text
    _addTextInputEvent();
    _setDraftContext();
    if (_composerIdentityKey.isNotEmpty) {
      _liveInputs[_composerIdentityKey] = this;
    }
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
        } else if (data["type"] == 1) {}
      }
    }
  }

  String addUIKitListener() {
    return TencentCloudChat.instance.chatSDKInstance.messageSDK
        .addUIKitListener(listener: uikitListener);
  }

  void removeUIKitListener() {
    if (listenerUUID.isNotEmpty) {
      TencentCloudChat.instance.chatSDKInstance.messageSDK
          .removeUIKitListener(listenerID: listenerUUID);
      // Clear so a second call is an idempotent no-op (the guard above now
      // actually protects against double-removal).
      listenerUUID = "";
    }
  }

  @override
  void dispose() {
    // Dispose our own resources BEFORE super.dispose() — this State is a
    // TickerProvider (the AnimationController in _addTextInputEvent uses
    // `vsync: this`), so the controllers must be torn down first.
    // NOTE: _messageAttachmentOptions is disposed inside _removeTextInputEvent();
    // do NOT also dispose it here — that double-disposes its internal
    // AnimationController ("dispose() called more than once").
    // Only drop the registry slot if it is still OURS: a successor State for
    // the same conversation may already have claimed it.
    if (identical(_liveInputs[_composerIdentityKey], this)) {
      _liveInputs.remove(_composerIdentityKey);
    }
    WidgetsBinding.instance.removeObserver(this);
    isStarted = false;
    _cancelPendingRecordingStarter();
    _removeTextInputEvent();
    removeUIKitListener();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TencentCloudChatMessageInputMobile oldWidget) {
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
      _textEditingController.text = widget.inputData.specifiedMessageText ?? "";
      _mentionedUsers.clear();
      _mentionedUsers
          .addAll((widget.inputData.membersNeedToMention ?? []).map(((e) {
        final targetMemberLabel = _getShowName(e);
        return (label: targetMemberLabel, userID: e.userID);
      })));
      _textEditingFocusNode.requestFocus();
    } else if (!TencentCloudChatUtils.deepEqual(
            widget.inputData.membersNeedToMention,
            oldWidget.inputData.membersNeedToMention) &&
        widget.inputData.membersNeedToMention != null) {
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

  // Bodies of the L3 real-UI seams (debug only; see the top-of-file notes).
  // Mutating the controller text fires `_onTextChanged`, which flips
  // `_showSendButton` and rebuilds — so `chat_send_button` becomes tappable;
  // the actual send stays the real button tap by the driver.
  void _debugSetComposerText(String text) {
    if (!mounted) return;
    _textEditingController.text = text;
  }

  // Set the text then invoke the exact production send path the
  // chat_send_button onTap runs (see the InkWell in the build method below).
  // Bypasses the synthetic button tap, which does not reliably fire on a
  // compact phone.
  void _debugSendComposerText(String text) {
    if (!mounted) return;
    _textEditingController.text = text;
    _submitTextMessage();
  }

  // Send-only twin: submit the CURRENT field contents. Same production path.
  void _debugSendComposer() {
    if (!mounted) return;
    _submitTextMessage();
  }

  ({String? userID, String? groupID}) _debugComposerBinding() =>
      (userID: widget.inputData.userID, groupID: widget.inputData.groupID);

  late final void Function(String) _mobileSetTextTearoff =
      _debugSetComposerText;
  late final void Function(String) _mobileSendTextTearoff =
      _debugSendComposerText;
  late final void Function() _mobileSendTearoff = _debugSendComposer;
  late final ({String? userID, String? groupID}) Function()
      _mobileBindingTearoff = _debugComposerBinding;

  void _addTextInputEvent() {
    try {
      _animationController = AnimationController(
          duration: const Duration(milliseconds: 200), vsync: this);
      _messageAttachmentOptions.init(vsync: this, context: context);
      _textEditingController.addListener(_onTextChanged);
      if (kDebugMode) {
        // Register the L3 real-UI composer seams (see the top-of-file notes).
        // Stored tearoffs, so `_removeTextInputEvent` can clear a slot only
        // while it is still OURS: a successor composer for another
        // conversation mounts (and registers) BEFORE this one is disposed on a
        // keyed remount, and an unconditional null here wiped its seams.
        debugRealUiMobileComposerSetText = _mobileSetTextTearoff;
        debugRealUiMobileComposerSendText = _mobileSendTextTearoff;
        debugRealUiMobileComposerSend = _mobileSendTearoff;
        debugRealUiMobileComposerBinding = _mobileBindingTearoff;
      }
      _textEditingFocusNode.addListener(() {
        if (_textEditingFocusNode.hasFocus) {
          safeSetState(() {
            _showKeyboard = true;
            _showStickerPanel = false;
          });
        } else {
          safeSetState(() {
            _showKeyboard = false;
          });
        }
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _removeTextInputEvent() {
    try {
      _animationController?.dispose();
      _messageAttachmentOptions.dispose();
      _animationController = null;
      if (kDebugMode) {
        if (identical(
            debugRealUiMobileComposerSetText, _mobileSetTextTearoff)) {
          debugRealUiMobileComposerSetText = null;
        }
        if (identical(
            debugRealUiMobileComposerSendText, _mobileSendTextTearoff)) {
          debugRealUiMobileComposerSendText = null;
        }
        if (identical(debugRealUiMobileComposerSend, _mobileSendTearoff)) {
          debugRealUiMobileComposerSend = null;
        }
        if (identical(
            debugRealUiMobileComposerBinding, _mobileBindingTearoff)) {
          debugRealUiMobileComposerBinding = null;
        }
      }
      _textEditingController.removeListener(_onTextChanged);
      _textEditingController.clear();
      _textEditingController.dispose();
      _textEditingFocusNode.dispose();
      // NOTE: the UIKit listener is initState-paired and removed in dispose()
      // via removeUIKitListener(); do NOT also remove it here (double-remove),
      // and keeping it out of this try/catch means a text-controller throw
      // can't skip the listener removal.
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  void _focusTextInputAndShowKeyboard() {
    _textEditingFocusNode.requestFocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.show'));
  }

  void _cancelPendingRecordingStarter() {
    _recordingStarter?.cancel();
    _recordingStarter = null;
  }

  /// [iconKey] is an AUTOMATION-ONLY handle placed on the tappable `InkWell`
  /// (never on an animated ancestor — see the mic/send swap below). It is
  /// optional and defaults to null, so every existing call site is unchanged.
  Widget _buildInputAreaIcon({
    required IconData icon,
    required GestureTapDownCallback onTapDown,
    Key? iconKey,
  }) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.hardEdge,
              child: InkWell(
                key: iconKey,
                onTapDown: onTapDown,
                child: Container(
                  margin: EdgeInsets.only(bottom: getSquareSize(1.5)),
                  padding: EdgeInsets.all(getSquareSize(8)),
                  child: Icon(
                    icon,
                    size: textStyle.inputAreaIcon,
                    color: colorTheme.inputAreaIconColor,
                  ),
                ),
              ),
            ));
  }

  void _onStartRecording(PointerDownEvent event) async {
    isStarted = true;
    final bool isMobilePlatform = widget.debugIsMobile?.call() ??
        TencentCloudChatPlatformAdapter().isMobile;
    if (isMobilePlatform &&
        await TencentCloudChatPermissionHandler.checkPermission(
            "microphone", context) &&
        isStarted) {
      _cancelPendingRecordingStarter();
      _recordingStarter = Timer(const Duration(milliseconds: 100), () {
        _recordingStarter = null;
        if (!mounted || !isStarted) return;
        safeSetState(() {
          _isRecording = true;
        });
        _recordingWidgetKey.currentState?.startRecording();
      });
    }
  }

  void _onStopRecording(PointerUpEvent event) {
    isStarted = false;
    if (_recordingStarter != null && _recordingStarter!.isActive) {
      _recordingWidgetKey.currentState?.stopRecording(cancel: true);
      _cancelPendingRecordingStarter();
      micTooltipKey.currentState?.ensureTooltipVisible();
      Future.delayed(const Duration(seconds: 2), () {
        // micTooltipKey.currentState?.dispose();
        Tooltip.dismissAllToolTips();
      });
    } else {
      // toxee fix: the trash key now lives on the recording State (it was a
      // module-level GlobalKey shared across instances — duplicate-key tree
      // corruption when two inputs coexist a frame). Reach it through our
      // own recording instance, and treat an unmounted icon as "not over
      // trash" instead of crashing on a null cast.
      final trashIconObject = _recordingWidgetKey
          .currentState?.trashIconKey.currentContext
          ?.findRenderObject();
      var isOverTrashIcon = false;
      if (trashIconObject is RenderBox) {
        final boxHitTestResult = BoxHitTestResult();
        isOverTrashIcon = trashIconObject.hitTest(boxHitTestResult,
            position: trashIconObject.globalToLocal(event.position));
      }
      safeSetState(() {
        _isRecording = false;
      });
      _recordingWidgetKey.currentState?.stopRecording(cancel: isOverTrashIcon);
    }
  }

  String _getShowName(V2TimGroupMemberFullInfo? item) {
    return TencentCloudChatUtils.checkStringWithoutSpace(item?.nameCard) ??
        TencentCloudChatUtils.checkStringWithoutSpace(item?.nickName) ??
        TencentCloudChatUtils.checkStringWithoutSpace(item?.userID) ??
        "";
  }

  void _addMentionedUsers(
      {V2TimMessage? message,
      List<V2TimGroupMemberFullInfo>? groupMembersInfo}) {
    final currentText = _textEditingController.text;
    final isValid = (groupMembersInfo ?? []).isNotEmpty ||
        TencentCloudChatUtils.checkString(message?.sender) != null;
    if (isValid) {
      String addText = "";
      groupMembersInfo?.forEach((element) {
        final targetMemberLabel = _getShowName(element);
        _mentionedUsers.add((label: targetMemberLabel, userID: element.userID));
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

  void _onTextChanged() async {
    final newText = _textEditingController.text;

    if (!_suppressDraftSave) {
      _draftCoordinator.markEdited();
    }

    /// Send Button Animation
    if (newText.isNotEmpty != _showSendButton) {
      safeSetState(() {
        _showSendButton = !_showSendButton;
      });
      if (_showSendButton) {
        _animationController?.forward();
      } else {
        _animationController?.reverse();
      }
    }

    if (_inputText == newText) {
      if (_inputText.isEmpty && !_suppressDraftSave) {
        /// Update draft
        _updateDraft(_inputText);
      }
      return;
    }

    /// Dealing with mentioning member in group
    if (TencentCloudChatUtils.checkString(widget.inputData.groupID) != null) {
      final compareResult =
          TencentCloudChatUtils.compareString(_inputText, newText);
      if (compareResult.isAddText && compareResult.character == "@") {
        /// Add "@" mentioned member tag.
        ///
        /// THE AWAIT BELOW CAN OUTLIVE THIS STATE. `onChooseGroupMembers()`
        /// pushes the full-screen `TencentCloudChatAtGroupMemberList` route;
        /// on the tablet master-detail shell the chat pane is remounted while
        /// that route is up, so `dispose()` (and with it
        /// `_removeTextInputEvent()`, which CLEARS and disposes the controller)
        /// can run between the push and the pop. Proved live on iPad: the
        /// successor State restored the pre-`@` draft, the resolved mention was
        /// written into the dead controller, and the group received the bare
        /// prefix with neither the label nor the `@`.
        ///
        /// So two invariants are established here:
        ///   1. the draft is flushed to what is ON SCREEN (the text WITH the
        ///      `@`) BEFORE handing control to the route — the end-of-method
        ///      `_updateDraft` is unreachable until the picker closes, which is
        ///      exactly why a remount used to restore the stale pre-`@` value;
        ///   2. the result is applied to whichever composer is LIVE for this
        ///      conversation when the picker closes, not blindly to `this`.
        _inputText = newText;
        if (!_suppressDraftSave) {
          _updateDraft(newText);
        }
        final List<V2TimGroupMemberFullInfo> memberList =
            await widget.inputMethods.onChooseGroupMembers();

        final mentioned = <({String userID, String label})>[];
        final mentionTextList = memberList.map((targetMember) {
          final String targetMemberLabel =
              TencentCloudChatUtils.checkString(targetMember.nameCard) ??
                  TencentCloudChatUtils.checkString(targetMember.nickName) ??
                  targetMember.userID;

          mentioned
              .add((label: targetMemberLabel, userID: targetMember.userID));
          return "@$targetMemberLabel ";
        }).toList();
        final mentionText = mentionTextList.join();

        if (memberList.isNotEmpty) {
          /// Insert mentionText after the "@" character
          final updatedText = newText.replaceRange(
              compareResult.index, compareResult.index + 1, mentionText);
          final caret = compareResult.index + mentionText.length;
          final target = mounted ? this : _liveInputs[_composerIdentityKey];
          if (target != null) {
            target._applyMentionInsertion(updatedText, caret, mentioned);
          } else {
            // Nothing is mounted for this conversation right now. Persist the
            // completed mention as the draft so the NEXT composer for it
            // restores the inserted label instead of the bare "@".
            _mentionedUsers.addAll(mentioned);
            _updateDraft(updatedText);
          }
        }
        // Everything past this branch touches `this`'s controller/State, which
        // is gone when the pane was remounted under the picker.
        if (!mounted) return;
      } else if (!compareResult.isAddText) {
        final atIndex =
            _inputText.lastIndexOf('@', max(0, compareResult.index - 1));
        final removedLabelList = [];
        if (atIndex != -1 &&
            compareResult.character != '@' &&
            compareResult.index > (atIndex + 1)) {
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
    }

    /// End
    _inputText = _textEditingController.text;

    final nextByteCount = utf8.encode(_inputText).length;
    if (nextByteCount != _byteCount) {
      safeSetState(() {
        _byteCount = nextByteCount;
      });
    }

    /// Update draft
    if (!_suppressDraftSave) {
      _updateDraft(_inputText);
    }
  }

  void _updateDraft(String draftText) {
    _draftCoordinator.saveDraft(draftText);
  }

  /// Apply an @-mention resolved by the picker route to THIS (live) composer.
  ///
  /// Invoked on `this` in the normal case, and on the SUCCESSOR State for the
  /// same conversation when the opener was disposed while the picker was up
  /// (see the mention branch in [_onTextChanged]). Assigning `.text` re-enters
  /// `_onTextChanged`, which sees a multi-character addition ("@<label> ") —
  /// never the single "@" that opens the picker — so this cannot recurse into
  /// a second route.
  void _applyMentionInsertion(
    String text,
    int caret,
    List<({String userID, String label})> mentioned,
  ) {
    if (!mounted) return;
    for (final member in mentioned) {
      if (!_mentionedUsers.any((e) => e.userID == member.userID)) {
        _mentionedUsers.add(member);
      }
    }
    _textEditingController.text = text;
    _textEditingController.selection =
        TextSelection.collapsed(offset: caret.clamp(0, text.length));
    _inputText = text;
    if (!_suppressDraftSave) {
      _updateDraft(text);
    }
  }

  bool _submitTextMessage() {
    final text = _textEditingController.text;
    if (text.isEmpty || utf8.encode(text).length > _kToxMaxMessageBytes) {
      return false;
    }
    final mentionedUsers = _mentionedUsers.map((e) => e.userID).toList();
    return _draftCoordinator.sendAndClear(
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
      },
      onError: (error) {
        debugPrint('Failed to send text message: $error');
      },
    );
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
    _suppressDraftSave = true;
    try {
      _inputText = text;
      _textEditingController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } finally {
      _suppressDraftSave = false;
    }
    safeSetState(() {
      _byteCount = utf8.encode(text).length;
    });
  }

  void _setConversationDraft(String conversationID, String draft) {
    final controller = widget.inputMethods.controller;
    if (controller is TencentCloudChatMessageController) {
      unawaited(controller.setDraft(conversationID, draft));
    }
  }

  void _insertComposerNewline() {
    final value = _textEditingController.value;
    final text = value.text;
    final selection = value.selection;
    final start = selection.isValid
        ? min(max(selection.start, 0), text.length)
        : text.length;
    final end = selection.isValid
        ? min(max(selection.end, start), text.length)
        : text.length;
    _textEditingController.value = value.copyWith(
      text: text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  KeyEventResult _onComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }

    final composing = _textEditingController.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      _insertComposerNewline();
      return KeyEventResult.handled;
    }

    _submitTextMessage();
    return KeyEventResult.handled;
  }

  Widget _buildInputTextField() {
    return ExtendedTextField(
      onTap: () {
        (widget.inputMethods.controller as TencentCloudChatMessageController)
            .scrollToBottom();
        _focusTextInputAndShowKeyboard();
        safeSetState(() {
          _showStickerPanel = false;
          _showKeyboard = true;
        });
      },
      focusNode: _textEditingFocusNode,
      controller: _textEditingController,
      minLines: 1,
      maxLines: 4,
      style: TextStyle(
        fontSize: getFontSize(14),
      ),
      decoration: InputDecoration(
        hintText: tL10n.sendAMessage,
        // Disable every border state so the composer never inherits the
        // app-wide blue focused-border ring (form fields keep it). The pill
        // outline comes from the wrapper Container; the reference composer
        // shows no extra ring when focused.
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        filled: false,
        fillColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        isDense: true,
      ),
      specialTextSpanBuilder: TencentCloudChatSpecialTextSpanBuilder(
        onTapUrl: (_) {},
        stickerPluginInstance: widget.inputData.stickerPluginInstance,
      ),
    );
  }

  Widget _buildInputWidget(BoxConstraints constraints) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Container(
              color: colorTheme.inputAreaBackground,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildInputAreaIcon(
                    // toxee automation anchor: the mobile composer's ONE
                    // attachment affordance (the "+" left of the input pill).
                    // Mirrored in lib/ui/testing/ui_keys.dart as
                    // UiKeys.messageAttachmentOptionsButton. Automation-only.
                    iconKey:
                        const ValueKey('message_attachment_options_button'),
                    icon: Icons.add_circle_outline_rounded,
                    onTapDown: (details) {
                      _textEditingFocusNode.unfocus();
                      if (_showStickerPanel) {
                        safeSetState(() {
                          _showStickerPanel = false;
                        });
                      }

                      _messageAttachmentOptions.toggleAttachmentOptionsOverlay(
                        constraints: constraints,
                        context: context,
                        tapDownDetails: details,
                        attachmentOptions: widget.inputData.attachmentOptions,
                        messageAttachmentOptionsBuilder: widget
                                .inputMethods.messageAttachmentOptionsBuilder
                            as Widget? Function(
                                {required MessageAttachmentOptionsBuilderData
                                    data,
                                Key? key,
                                required MessageAttachmentOptionsBuilderMethods
                                    methods})?,
                      );
                    },
                  ),
                  SizedBox(
                    width: getSquareSize(6),
                  ),
                  Expanded(
                      child: Container(
                    padding: EdgeInsets.symmetric(
                        vertical: getWidth(9), horizontal: getHeight(14)),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(
                          color: colorTheme.inputFieldBorderColor
                              .withOpacity(0.65)),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Input field for the message.
                        Expanded(
                          child: Focus(
                            onKeyEvent: _onComposerKeyEvent,
                            child: _buildInputTextField(),
                          ),
                        ),
                        if (widget.inputData.hasStickerPlugin)
                          GestureDetector(
                            key: const ValueKey('emoji_panel_button'),
                            onTap: () {
                              if (!_showStickerPanel) {
                                _textEditingFocusNode.unfocus();
                              } else {
                                _focusTextInputAndShowKeyboard();
                              }
                              safeSetState(() {
                                _showStickerPanel = !_showStickerPanel;
                              });
                            },
                            child: Icon(
                              _showStickerPanel
                                  ? Icons.keyboard_alt_outlined
                                  : Icons.emoji_emotions_outlined,
                              size: textStyle.inputAreaIcon,
                              color: colorTheme.inputAreaIconColor,
                            ),
                          ),
                      ],
                    ),
                  )),
                  Container(
                    margin: EdgeInsets.only(
                      bottom: getSquareSize(_showSendButton ? 6 : 4),
                      left: getSquareSize(6),
                      right: getSquareSize(_showSendButton ? 4 : 0),
                    ),
                    child: _animationController != null
                        ? AnimatedBuilder(
                            animation: _animationController!,
                            builder: (BuildContext context, Widget? child) {
                              return Transform.rotate(
                                // Full turn (2π), not a half turn (π): at rest
                                // (value == 1) a half turn left the send icon
                                // (Icons.arrow_upward_rounded) rotated 180° so it
                                // pointed DOWN. A full turn animates the swap and
                                // lands the arrow upright.
                                angle: _animationController!.value * 2 * pi,
                                child: _showSendButton
                                    ? InkWell(
                                        // Stable key so real-UI automation can tap
                                        // the mobile send button (matches
                                        // toxee UiKeys.chatSendButton = 'chat_send_button').
                                        key: const ValueKey('chat_send_button'),
                                        onTap: _byteCount > _kToxMaxMessageBytes
                                            ? null
                                            : _submitTextMessage,
                                        child: Container(
                                          decoration: BoxDecoration(
                                              color: _byteCount >
                                                      _kToxMaxMessageBytes
                                                  ? colorTheme.primaryColor
                                                      .withOpacity(0.4)
                                                  : colorTheme.primaryColor,
                                              borderRadius:
                                                  BorderRadius.circular(25)),
                                          padding:
                                              EdgeInsets.all(getSquareSize(8)),
                                          child: Icon(
                                            Icons.arrow_upward_rounded,
                                            size: textStyle.inputAreaIcon,
                                            color: colorTheme.backgroundColor,
                                          ),
                                        ),
                                      )
                                    : Tooltip(
                                        key: micTooltipKey,
                                        preferBelow: false,
                                        verticalOffset: getSquareSize(36),
                                        triggerMode: TooltipTriggerMode.manual,
                                        showDuration:
                                            const Duration(seconds: 1),
                                        message:
                                            tL10n.holdToRecordReleaseToSend,
                                        child: Listener(
                                          // toxee automation anchor for the
                                          // hold-to-record mic. Deliberately on
                                          // the Listener (a plain
                                          // RenderPointerListener that wraps a
                                          // padded Icon) and NOT on the
                                          // Transform/AnimatedBuilder above it:
                                          // keying an animated widget with a
                                          // value that flips per state remounts
                                          // it and destroys the rotation
                                          // animation. The mic and
                                          // `chat_send_button` are the two arms
                                          // of the SAME ternary, so presence of
                                          // this key IS "_showSendButton ==
                                          // false". Mirrored in
                                          // lib/ui/testing/ui_keys.dart as
                                          // UiKeys.chatVoiceRecordButton.
                                          key: const ValueKey(
                                              'chat_voice_record_button'),
                                          onPointerDown: _onStartRecording,
                                          onPointerUp: _onStopRecording,
                                          child: Container(
                                            padding: EdgeInsets.all(
                                                getSquareSize(6)),
                                            child: Icon(
                                              Icons.mic,
                                              size: textStyle.inputAreaIcon,
                                              color:
                                                  colorTheme.inputAreaIconColor,
                                            ),
                                          ),
                                        ),
                                      ),
                              );
                            },
                          )
                        : Container(),
                  ),
                ],
              ),
            ));
  }

  double _getBottomContainerHeight() {
    if (_showStickerPanel) {
      // The input is a non-flex Column child (unbounded height), so cap the
      // panel at 40% of the visible window or it pushes the list off-screen
      // on short phones / landscape.
      final visibleHeight = MediaQuery.sizeOf(context).height -
          MediaQuery.viewInsetsOf(context).bottom;
      return min(getHeight(280), visibleHeight * 0.4);
    }
    // toxee 5.1: track the soft keyboard height via viewInsets so the sticker
    // panel can size to match the previously-seen keyboard height the first
    // time it opens. The previous behaviour (commented out below) tried to
    // pad the panel area with the live `viewInsets.bottom`, which conflicted
    // with `Scaffold.resizeToAvoidBottomInset` and produced double-padding.
    // Instead we only OBSERVE the keyboard height here (debounced cache) and
    // let the outer `Padding` (see `defaultBuilder`) push the bar above the
    // keyboard. Sticker-panel sizing falls back to the cached height.
    if (_showKeyboard) {
      final currentKeyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
      if (currentKeyboardHeight > 0) {
        TencentCloudChatUtils.debounce(
          'setCurrentKeyboardHeight',
          () {
            TencentCloudChat.instance.dataInstance.basic.keyboardHeight =
                currentKeyboardHeight;
          },
          duration: const Duration(seconds: 1),
        );
      }
    }
    return _bottomPadding ?? 0.0;
  }

  Future<bool> getStickerPanelWidget() async {
    if (widget.inputData.hasStickerPlugin) {
      if (widget.inputData.stickerPluginInstance != null) {
        var wid = await widget.inputData.stickerPluginInstance!
            .getWidget(methodName: "stickerPanel");
        if (wid != null) {
          stickerWidget = wid;
          return true;
        }
      }
    }
    return false;
  }

  /// Sticker mode: the sticker panel is the only part of the composer that
  /// can give up height. Under a bounded parent (the layout caps the input)
  /// it becomes Flexible and shrinks to what the reply bar + text field
  /// leave. A Flexible under an unbounded parent would assert, and keyboard
  /// mode scrolls instead (see [_scrollIfTight]), so it stays as-is there.
  Widget _boundedPanel(BoxConstraints constraints, Widget panel) =>
      constraints.hasBoundedHeight && _showStickerPanel
          ? Flexible(child: panel)
          : panel;

  /// Keyboard mode: nothing in the composer can shrink, so when reply bar +
  /// a multi-line draft exceed a keyboard-shrunk body (~118 px on a short
  /// landscape window) the column scrolls, anchored at the text field so the
  /// field stays fully visible, instead of overflowing. Shrink-wraps, so it
  /// is invisible whenever the content fits.
  Widget _scrollIfTight(BoxConstraints constraints, Widget column) =>
      constraints.hasBoundedHeight && !_showStickerPanel
          ? SingleChildScrollView(reverse: true, child: column)
          : column;

  @override
  Widget defaultBuilder(BuildContext context) {
    if (widget.debugDraftPersistenceOnly) {
      return Text(
        _textEditingController.text,
        key: const ValueKey('draft_persistence_text'),
      );
    }
    _bottomPadding ??= MediaQuery.of(context).padding.bottom;
    var panelHeight = _getBottomContainerHeight();
    // toxee 5.1: pad the input container above the OS soft keyboard. We use
    // `MediaQuery.viewInsetsOf(context).bottom` (tear-off form, lower rebuild
    // cost than `MediaQuery.of(context).viewInsets.bottom`). When the sticker
    // panel is shown we suppress the inset because the panel itself takes
    // the keyboard's place.
    final double keyboardInset =
        _showStickerPanel ? 0.0 : MediaQuery.viewInsetsOf(context).bottom;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) =>
          TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) {
          return Padding(
            padding: EdgeInsets.only(bottom: keyboardInset),
            child: Container(
              color: colorTheme.inputAreaBackground,
              padding: EdgeInsets.only(
                bottom: _showStickerPanel
                    ? 0
                    : (_bottomPadding! > 8
                        ? getSquareSize(0)
                        : getSquareSize(16)),
                left: getSquareSize(16),
                right: getSquareSize(16),
                top: widget.inputData.repliedMessage != null
                    ? getSquareSize(8)
                    : getSquareSize(16),
              ),
              child: _scrollIfTight(constraints, Column(
                // min: the layout now hands the input a BOUNDED height; a max
                // Column would grow to fill the whole cap.
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.inputData.repliedMessage != null)
                    TencentCloudChatMessageInputReplyContainer(
                      repliedMessage: widget.inputData.repliedMessage,
                    ),
                  if (_byteCount >= _kToxByteCounterThreshold)
                    Padding(
                      padding: EdgeInsets.only(
                          bottom: getSquareSize(4), right: getSquareSize(4)),
                      child: Text(
                        '$_byteCount / $_kToxMaxMessageBytes',
                        style: TextStyle(
                          fontSize: getFontSize(11),
                          // Over the hard cap -> error; nearing it -> warning tone
                          // (#FF8800, no dedicated colorTheme warning slot).
                          color: _byteCount > _kToxMaxMessageBytes
                              ? colorTheme.error
                              : const Color(0xFFFF8800),
                        ),
                      ),
                    ),
                  IndexedStack(
                    index: _isRecording ? 1 : 0,
                    children: [
                      AnimatedSwitcher(
                        switchInCurve: Curves.ease,
                        switchOutCurve: Curves.ease,
                        duration: const Duration(milliseconds: 500),
                        transitionBuilder:
                            (Widget child, Animation<double> animation) {
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
                            : _buildInputWidget(constraints),
                      ),
                      TencentCloudChatMessageInputRecording(
                        onRecordFinish: (recordInfo) => widget.inputMethods
                            .sendVoiceMessage(
                                voicePath: recordInfo.path,
                                duration: recordInfo.duration),
                        isRecording: _isRecording,
                        key: _recordingWidgetKey,
                      ),
                    ],
                  ),
                  _boundedPanel(constraints, AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.ease,
                    height: panelHeight,
                    constraints: _showStickerPanel
                        ? BoxConstraints(minHeight: panelHeight)
                        : null,
                    child: _showStickerPanel
                        // toxee: keyed so automation can prove the MOBILE sticker
                        // panel actually opened (the desktop panel has its own
                        // 'desktop_sticker_panel' overlay key; this is the inline
                        // mobile counterpart, present only while shown).
                        ? KeyedSubtree(
                            key: const ValueKey('mobile_sticker_panel'),
                            child: Center(
                              child: FutureBuilder<bool>(
                                future: getStickerPanelWidget(),
                                builder: (BuildContext context,
                                    AsyncSnapshot<bool> snapshot) {
                                  return stickerWidget;
                                },
                              ),
                            ),
                          )
                        : Container(),
                  ))
                ],
              )),
            ),
          );
        },
      ),
    );
  }
}
