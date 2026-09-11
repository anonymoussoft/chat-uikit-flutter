import 'package:desktop_drop_for_t/desktop_drop_for_t.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_message/common/for_desktop/file_tools.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_member_mention_panel.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_sticker_panel.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_layout/special_case/tencent_cloud_chat_message_drop_target.dart';

class TencentCloudChatMessageLayout extends StatefulWidget {
  final MessageLayoutBuilderWidgets widgets;
  final MessageLayoutBuilderData data;
  final MessageLayoutBuilderMethods methods;

  const TencentCloudChatMessageLayout({
    super.key,
    required this.widgets,
    required this.data,
    required this.methods,
  });

  @override
  State<TencentCloudChatMessageLayout> createState() => _TencentCloudChatMessageLayoutState();
}

class _TencentCloudChatMessageLayoutState extends TencentCloudChatState<TencentCloudChatMessageLayout> {
  bool _dragging = false;

  @override
  Widget defaultBuilder(BuildContext context) {
    return Scaffold(
      appBar: widget.widgets.header,
      // resizeToAvoidBottomInset: false,
      // The input used to be an unbounded non-flex child: reply bar + a
      // multi-line composer + the sticker panel on a landscape phone pushed
      // the list to zero and the Column overflowed. Bound the input so its
      // sticker panel (the only part that can shrink) yields. The list keeps
      // up to a 96-px strip, but only out of height the composer does not
      // need: the reservation fades to 0 below a 296-px body, so a
      // keyboard-shrunk body (e.g. 114 px on a landscape phone) goes entirely
      // to the fixed composer instead of leaving it 18 px.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double body = constraints.maxHeight;
          final double listReserve = (body - 200).clamp(0.0, 96.0).toDouble();
          return Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                  },
                  child: widget.widgets.messageListView,
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: body - listReserve),
                child: widget.widgets.messageInput,
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget desktopBuilder(BuildContext context) {
    return Scaffold(
      // resizeToAvoidBottomInset: false,
      appBar: widget.widgets.header,
      body: DropTarget(
          onDragDone: (detail) {
            setState(() {
              _dragging = false;
            });
            final filesPath = detail.files.map((e) => e.path).toList();
            TencentCloudChatDesktopFileTools.sendFileWithConfirmation(
              filesPath: filesPath,
              currentConversationShowName: widget.data.currentConversationShowName,
              sendFileMessage: widget.methods.sendFileMessage,
              context: context,
            );
          },
          onDragEntered: (detail) {
            setState(() {
              _dragging = true;
            });
          },
          onDragExited: (detail) {
            setState(() {
              _dragging = false;
            });
          },
          // LayoutBuilder: the sticker panel is a Positioned child of this
          // Stack and needs the pane width to clamp itself inside it.
          child: LayoutBuilder(builder: (context, paneConstraints) => Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        FocusScope.of(context).unfocus();
                        widget.methods.closeSticker();
                        // widget.methods;
                      },
                      child: widget.widgets.messageListView,
                  )),
                  widget.widgets.messageInput,
                ],
              ),
              TencentCloudChatDesktopMemberMentionPanel(
                atMemberPanelScroll: widget.methods.desktopInputMemberSelectionPanelScroll,
                onSelectMember: widget.methods.onSelectMember,
                desktopMentionBoxPositionX: widget.data.desktopMentionBoxPositionX,
                desktopMentionBoxPositionY: widget.data.desktopMentionBoxPositionY,
                activeMentionIndex: widget.data.activeMentionIndex,
                currentFilteredMembersListForMention: widget.data.currentFilteredMembersListForMention,
              ),
              if (widget.data.hasStickerPlugin && widget.data.stickerPluginInstance != null && widget.data.desktopStickerBoxPositionX != 0.0 && widget.data.desktopStickerBoxPositionY != 0.0)
                TencentCloudChatDesktopStickerPanel(
                  desktopStickerBoxPositionX: widget.data.desktopStickerBoxPositionX,
                  desktopStickerBoxPositionY: widget.data.desktopStickerBoxPositionY,
                  stickerPluginInstance: widget.data.stickerPluginInstance!,
                  paneWidth: paneConstraints.maxWidth,
                ),
              if (_dragging)
                TencentCloudChatMessageDropTarget(
                  currentConversationShowName: widget.data.currentConversationShowName,
                ),
            ],
          ))),
    );
  }
}
