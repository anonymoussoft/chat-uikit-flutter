import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:scrollable_positioned_list_for_us/scrollable_positioned_list_for_us.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/data/contact/tencent_cloud_chat_contact_data.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_index_bar_fit.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_item.dart';

class TencentCloudChatContactAzlist extends StatefulWidget {
  final List<V2TimFriendInfo> contactList;
  final List<TTabItem>? tabList;

  const TencentCloudChatContactAzlist(
      {super.key, required this.contactList, this.tabList});

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactAzlistState();
}

class TencentCloudChatContactAzlistState
    extends TencentCloudChatState<TencentCloudChatContactAzlist> {
  /// Owned by THIS list (ItemScrollController is single-attach), and published
  /// to the component controller only while mounted so the host app can scroll
  /// the visible contacts list back to the top.
  final ItemScrollController _itemScrollController = ItemScrollController();

  @override
  void initState() {
    super.initState();
    TencentCloudChatContactManager.controller
        .registerScrollController(_itemScrollController);
  }

  @override
  void dispose() {
    TencentCloudChatContactManager.controller
        .unregisterScrollController(_itemScrollController);
    super.dispose();
  }

  _getShowName(V2TimFriendInfo item) {
    final friendRemark = item.friendRemark ?? "";
    final nickName = item.userProfile?.nickName ?? "";
    final userID = item.userID;
    final showName = nickName != "" ? nickName : userID;
    return friendRemark != "" ? friendRemark : showName;
  }

  List<ISuspensionBeanImpl> _getFriendList(String query) {
    final List<ISuspensionBeanImpl> showList = List.empty(growable: true);
    for (var i = 0; i < widget.contactList.length; i++) {
      final item = widget.contactList[i];
      // S49: filter by the in-page contact search query (case-insensitive
      // contains on friendRemark / nickName / userID).
      if (!TencentCloudChatContactData.contactMatchesQuery(item, query)) {
        continue;
      }
      final showName = _getShowName(item);
      String tag = showName.substring(0, 1).toUpperCase();
      if (RegExp("[A-Z]").hasMatch(tag)) {
        showList.add(
          ISuspensionBeanImpl(
            friendInfo: item,
            tagIndex: tag,
          ),
        );
      } else {
        showList.add(
          ISuspensionBeanImpl(
            friendInfo: item,
            tagIndex: "#",
          ),
        );
      }
    }
    SuspensionUtil.sortListBySuspensionTag(showList);
    SuspensionUtil.setShowSuspensionStatus(showList);
    return showList;
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    // Rebuild whenever the in-page contact search query changes (S49).
    return ValueListenableBuilder<String>(
      valueListenable:
          TencentCloudChat.instance.dataInstance.contact.contactSearchQuery,
      builder: (context, query, _) => _buildList(context, query),
    );
  }

  Widget _buildList(BuildContext context, String query) {
    final showFriendList = _getFriendList(query);
    if (widget.tabList != null && widget.tabList!.isNotEmpty) {
      final topList = widget.tabList!
          .map((e) => ISuspensionBeanImpl(friendInfo: e, tagIndex: '@'))
          .toList();
      showFriendList.insertAll(0, topList);
    }
    // Show the empty-state when there are no matching friend entries (either no
    // contacts at all, or none match the active search query). TTabItems (tag
    // '@') don't count as contacts for this check.
    final hasFriendEntries =
        showFriendList.any((e) => e.getSuspensionTag() != '@');
    if (!hasFriendEntries) {
      // Scrollable (not a bare Column): the tabs + empty label exceed a short
      // contact pane (landscape phone, split desktop), which would overflow.
      return TencentCloudChatThemeWidget(
        build: (context, colors, fontSize) => LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    constraints.maxHeight.isFinite ? constraints.maxHeight : 0,
              ),
              child: Column(
                children: [
                  ...showFriendList
                      .map((e) => TencentCloudChat
                          .instance.dataInstance.contact.contactBuilder
                          ?.getContactListTabItemBuilder(e.friendInfo))
                      .toList(),
                  Padding(
                    padding: EdgeInsets.only(top: getHeight(28)),
                    child: Center(
                      child: Text(
                        tL10n.noContact,
                        style: TextStyle(
                          fontSize: fontSize.fontsize_14,
                          color: colors.contactNoListColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final indexTags = SuspensionUtil.getTagIndexList(showFriendList)
        .where((element) => element != "@")
        .toList();
    return LayoutBuilder(builder: (context, constraints) {
      // The A-Z jump bar only earns its place once there is something to jump
      // across; with a handful of letters it floats as stray glyphs beside an
      // otherwise empty column. Section headers still render regardless.
      final indexBar = TencentCloudChatIndexBarFit.fit(
          indexTags.length >= 6 ? indexTags : const <String>[],
          constraints.maxHeight,
          textScale: MediaQuery.textScalerOf(context).scale(1.0));
      return Scrollbar(
          child: AzListView(
        // Shared with the component controller so the host app can scroll this
        // list back to the top (bottom-nav re-tap convention).
        itemScrollController: _itemScrollController,
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        data: showFriendList,
        itemCount: showFriendList.length,
        indexBarData: indexBar.tags,
        indexBarItemHeight: indexBar.itemHeight,
        indexBarOptions: indexBar.options,
          itemBuilder: (context, index) {
          if (showFriendList[index].friendInfo is TTabItem) {
            return TencentCloudChat.instance.dataInstance.contact.contactBuilder
                ?.getContactListTabItemBuilder(
                    showFriendList[index].friendInfo);
          } else {
            final friend = showFriendList[index].friendInfo;
            return TencentCloudChatContactItem(friend: friend);
          }
        },
        susItemBuilder: (context, index) {
          ISuspensionBeanImpl tag = showFriendList[index];
          if (tag.getSuspensionTag() == "@") {
            return Container();
          }
          return TencentCloudChat.instance.dataInstance.contact.contactBuilder
              ?.getContactListTagBuilder(tag.getSuspensionTag());
        },
        susItemHeight: getSquareSize(30),
      ));
    });
  }
}

class ISuspensionBeanImpl<T> extends ISuspensionBean {
  String tagIndex;
  T friendInfo;

  ISuspensionBeanImpl({required this.tagIndex, required this.friendInfo});

  @override
  String getSuspensionTag() => tagIndex;
}
