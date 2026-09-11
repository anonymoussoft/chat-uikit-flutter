import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/builders/tencent_cloud_chat_common_builders.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_navigator.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_safe_dialog_pop.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';
import 'package:tencent_cloud_chat_contact/widgets/create_group.dart';
import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_azlist.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_index_bar_fit.dart';

class StartC2CChat extends StatefulWidget {
  const StartC2CChat({super.key});

  @override
  State<StartC2CChat> createState() {
    return _StartC2CChatState();
  }
}

class _StartC2CChatState extends TencentCloudChatState<StartC2CChat> {
  List<V2TimFriendInfo> friendInfoList = [];

  List<ISuspensionBeanImpl> _getSortedFriendList() {
    final List<ISuspensionBeanImpl> showList = List.empty(growable: true);
    for (var item in friendInfoList) {
      final showName = _getMemberName(item);
      String tag = showName.substring(0, 1).toUpperCase();
      if (RegExp("[A-Z]").hasMatch(tag)) {
        showList.add(ISuspensionBeanImpl(friendInfo: item, tagIndex: tag));
      } else {
        showList.add(ISuspensionBeanImpl(friendInfo: item, tagIndex: "#"));
      }
    }
    SuspensionUtil.sortListBySuspensionTag(showList);
    SuspensionUtil.setShowSuspensionStatus(showList);
    return showList;
  }

  String _getMemberName(V2TimFriendInfo friendInfo) {
    if (friendInfo.friendRemark != null && friendInfo.friendRemark!.isNotEmpty) {
      return friendInfo.friendRemark!;
    } else if (friendInfo.userProfile != null) {
      if (friendInfo.userProfile!.nickName != null &&
          friendInfo.userProfile!.nickName != null &&
          friendInfo.userProfile!.nickName!.isNotEmpty) {
        return friendInfo.userProfile!.nickName!;
      }
    }

    return friendInfo.userID;
  }

  String _getMemberUserID(V2TimFriendInfo friendInfo) {
    return friendInfo.userID!;
  }

  Widget _buildMemberList(colorTheme, textStyle) {
    final sortedFriendList = _getSortedFriendList();

    // Empty-state: with no contacts the AzListView renders nothing, leaving a
    // blank page under the app bar (reported as "New Chat page is blank" on
    // accounts with no friends). Show a centered hint instead.
    if (sortedFriendList.isEmpty) {
      return Center(
        child: Text(
          tL10n.noContact,
          style: TextStyle(
            fontSize: textStyle.fontsize_14,
            color: colorTheme.contactNoListColor,
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      final indexBar = TencentCloudChatIndexBarFit.fit(
          SuspensionUtil.getTagIndexList(sortedFriendList).where((element) => element != "@").toList(),
          constraints.maxHeight,
          textScale: MediaQuery.textScalerOf(context).scale(1.0));
      return AzListView(
      data: sortedFriendList,
      itemCount: sortedFriendList.length,
      indexBarData: indexBar.tags,
      indexBarItemHeight: indexBar.itemHeight,
      indexBarOptions: indexBar.options,
      itemBuilder: (context, index) {
        V2TimFriendInfo friendInfo = sortedFriendList[index].friendInfo;
        return GestureDetector(
            onTap: () {
              // Prevents the double-pop blank; a double-tap may still push the
              // chat twice (minor) — full idempotency needs a State-level flag.
              popDialogIfCurrent(context);
              navigateToMessage(
                context: context,
                options: TencentCloudChatMessageOptions(userID: _getMemberUserID(friendInfo), groupID: null),
              );
            },
            child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: getHeight(8),
                  horizontal: getWidth(16),
                ),
                child: Row(
                  children: [
                    TencentCloudChatCommonBuilders.getCommonAvatarBuilder(
                      scene: TencentCloudChatAvatarScene.contacts,
                      imageList: [friendInfo.userProfile?.faceUrl ?? ''],
                      width: getSquareSize(40),
                      height: getSquareSize(40),
                      borderRadius: getSquareSize(58),
                    ),
                    SizedBox(width: getWidth(8)),
                    Text(
                      _getMemberName(friendInfo),
                      style: TextStyle(
                        fontSize: textStyle.fontsize_14,
                        fontWeight: FontWeight.w400,
                        color: colorTheme.contactItemFriendNameColor,
                      ),
                    )
                  ],
                )));
      },
      susItemBuilder: (context, index) {
        ISuspensionBeanImpl tag = sortedFriendList[index];
        if (tag.getSuspensionTag() == "@") {
          return Container();
        }
        return Container(
          width: MediaQuery.of(context).size.width,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          color: colorTheme.backgroundColor,
          child: Text(
            tag.getSuspensionTag(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        );
      },
      physics: const ClampingScrollPhysics(),
    );
    });
  }

  void _fetchMembers() async {
    List<V2TimFriendInfo> friendList = TencentCloudChat.instance.dataInstance.contact.contactList;
    setState(() {
      friendInfoList = friendList;
    });
  }

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Scaffold(
              backgroundColor: colorTheme.backgroundColor,
              appBar: AppBar(
                // Widen the leading slot so the "Cancel" text button fits on
                // one line (the 56px default wraps it to "Can/cel", and is also
                // tight for longer locales like JA "キャンセル").
                leadingWidth: getWidth(100),
                backgroundColor: colorTheme.contactBackgroundColor,
                leading: TextButton(
                  onPressed: () => popDialogIfCurrent(context),
                  child: Text(
                    tL10n.cancel,
                    style: TextStyle(color: colorTheme.primaryColor),
                  ),
                ),
                title: Text(
                  tL10n.startConversation,
                  style: TextStyle(fontSize: textStyle.fontsize_16, color: colorTheme.primaryTextColor),
                ),
                centerTitle: true,
                scrolledUnderElevation: 0.0,
              ),
              body: Column(
                children: [
                  Divider(height: 1, color: colorTheme.dividerColor),
                  Expanded(child: _buildMemberList(colorTheme, textStyle)),
                ],
              ),
            ));
  }
}
