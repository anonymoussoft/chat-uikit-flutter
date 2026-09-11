// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:azlistview_all_platforms/azlistview_all_platforms.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';
import 'package:tencent_cloud_chat_common/utils/sdk_const.dart';

class ISuspensionBeanImpl<T> extends ISuspensionBean {
  String tagIndex;
  T memberInfo;

  ISuspensionBeanImpl({required this.tagIndex, required this.memberInfo});

  @override
  String getSuspensionTag() => tagIndex;
}

class TencentCloudChatAtGroupMemberList extends StatefulWidget {
  final V2TimGroupInfo groupInfo;
  final List<V2TimGroupMemberFullInfo> memberInfoList;
  // Whether the @All entry is offered — admin/owner only, parity with the
  // desktop inline mention. Defaults true to preserve upstream behavior for any
  // caller that doesn't pass it; toxee's _onChooseGroupMembers passes the
  // resolved admin state so a non-admin member doesn't get @All on mobile.
  final bool isGroupAdmin;

  const TencentCloudChatAtGroupMemberList({
    Key? key,
    required this.groupInfo,
    required this.memberInfoList,
    this.isGroupAdmin = true,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatAtGroupMemberListState();
}

class TencentCloudChatAtGroupMemberListState
    extends TencentCloudChatState<TencentCloudChatAtGroupMemberList> {
  final List<V2TimGroupMemberFullInfo> selectMembers = [];

  void _onSelectGroupMember(
      bool isSelect, V2TimGroupMemberFullInfo memberFullInfo) {
    if (isSelect) {
      selectMembers.add(memberFullInfo);
      if (memberFullInfo.userID == SDKConst.sdkAtAllUserID) {
        _submitAtMemberList();
      }
    } else {
      selectMembers
          .removeWhere((element) => element.userID == memberFullInfo.userID);
    }
  }

  void _submitAtMemberList() {
    Navigator.pop(context, selectMembers);
  }

  @override
  Widget? desktopBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Container(
            color: colorTheme.backgroundColor,
            child: Center(
              child: TencentCloudChatGroupProfileMemberListAzList(
                groupInfo: widget.groupInfo,
                memberInfoList: widget.memberInfoList,
                isGroupAdmin: widget.isGroupAdmin,
                onSelectGroupMember: _onSelectGroupMember,
              ),
            )));
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Scaffold(
            appBar: AppBar(
              leadingWidth: getWidth(100),
              leading: GestureDetector(
                // toxee automation anchor. This screen is MULTI-select and only
                // commits when it is popped, so both app-bar affordances call
                // the SAME `_submitAtMemberList()`; "back" is not a cancel, it
                // commits whatever is currently ticked (possibly nothing).
                // Mirrored as UiKeys.mentionMemberListBackButton.
                key: const ValueKey('mention_member_list_back_button'),
                onTap: () async {
                  _submitAtMemberList();
                },
                child: Row(children: [
                  Padding(padding: EdgeInsets.only(left: getWidth(10))),
                  Icon(
                    Icons.arrow_back_ios_outlined,
                    color: colorTheme.primaryColor,
                    size: getSquareSize(24),
                  ),
                  Padding(padding: EdgeInsets.only(left: getWidth(8))),
                  Text(
                    tL10n.back,
                    style: TextStyle(
                      color: colorTheme.primaryColor,
                      fontSize: textStyle.fontsize_14,
                    ),
                  )
                ]),
              ),
              actions: [
                TextButton(
                  // toxee automation anchor; mirrored as
                  // UiKeys.mentionMemberListConfirmButton.
                  key: const ValueKey('mention_member_list_confirm_button'),
                  onPressed: () {
                    _submitAtMemberList();
                  },
                  child: Text(
                    tL10n.confirm,
                    style: TextStyle(
                      color: colorTheme.primaryColor,
                      fontSize: 14,
                    ),
                  ),
                )
              ],
              scrolledUnderElevation: 0.0,
            ),
            body: Container(
                color: colorTheme.backgroundColor,
                child: Center(
                  child: TencentCloudChatGroupProfileMemberListAzList(
                    groupInfo: widget.groupInfo,
                    memberInfoList: widget.memberInfoList,
                    // toxee: forward the admin verdict the container resolved.
                    // Dropping it here left the AzList on its `true` default,
                    // so the desktopBuilder and defaultBuilder disagreed about
                    // who may @All.
                    isGroupAdmin: widget.isGroupAdmin,
                    onSelectGroupMember: _onSelectGroupMember,
                  ),
                ))));
  }
}

class TencentCloudChatGroupProfileMemberListAzList extends StatefulWidget {
  final V2TimGroupInfo groupInfo;
  final List<V2TimGroupMemberFullInfo> memberInfoList;
  final bool isGroupAdmin;
  final Function(bool isSelect, V2TimGroupMemberFullInfo memberFullInfo)
      onSelectGroupMember;

  const TencentCloudChatGroupProfileMemberListAzList({
    Key? key,
    required this.groupInfo,
    required this.memberInfoList,
    this.isGroupAdmin = true,
    required this.onSelectGroupMember,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatGroupProfileMemberListAzListState();
}

class TencentCloudChatGroupProfileMemberListAzListState
    extends TencentCloudChatState<
        TencentCloudChatGroupProfileMemberListAzList> {
  List<ISuspensionBeanImpl> list = [];

  @override
  initState() {
    super.initState();
    list = _getListTag();
  }

  List<ISuspensionBeanImpl> _getListTag() {
    final List<ISuspensionBeanImpl> showList = List.empty(growable: true);
    for (var i = 0; i < widget.memberInfoList.length; i++) {
      final item = widget.memberInfoList[i];
      String showName = widget.memberInfoList[i].userID;
      if (TencentCloudChatUtils.checkString(
              widget.memberInfoList[i].nickName) !=
          null) {
        showName = widget.memberInfoList[i].nickName!;
      }

      String showNamePinyin = PinyinHelper.getPinyinE(showName);
      String tag = showNamePinyin.substring(0, 1).toUpperCase();
      if (RegExp("[A-Z]").hasMatch(tag)) {
        showList.add(ISuspensionBeanImpl(memberInfo: item, tagIndex: tag));
      } else {
        tag = "#";
        showList.add(ISuspensionBeanImpl(memberInfo: item, tagIndex: "#"));
      }
    }
    SuspensionUtil.sortListBySuspensionTag(showList);
    // add @everyone item — admin/owner only (parity with the desktop inline
    // mention, which gates @All on isGroupAdmin and on NOTHING else; mobile
    // previously also required groupType ∈ {Work, Public, Meeting}, a
    // Tencent-IM taxonomy that toxee's lowercase types ('group', 'public',
    // 'conference', …) can never satisfy — @All was unreachable on mobile for
    // EVERY toxee group while the desktop panel offered it freely.
    if (widget.isGroupAdmin) {
      showList.insert(
          0,
          ISuspensionBeanImpl(
              memberInfo: V2TimGroupMemberFullInfo(
                  userID: SDKConst.sdkAtAllUserID, nickName: tL10n.atAll),
              tagIndex: ""));
    }
    SuspensionUtil.setShowSuspensionStatus(showList);
    return showList;
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    if (widget.memberInfoList.isEmpty) {
      return Container();
    }
    return Scrollbar(
        child: AzListView(
      data: list,
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index].memberInfo;
        return TencentCloudChatGroupProfileMemberListItem(
          onSelectGroupMember: (bool isSelect) async {
            widget.onSelectGroupMember(isSelect, item);
          },
          memberFullInfo: item,
          groupInfo: widget.groupInfo,
        );
      },
      indexBarData: SuspensionUtil.getTagIndexList(list),
      physics:
          const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      susItemBuilder: (context, index) {
        ISuspensionBeanImpl tag = list[index];
        if (tag.getSuspensionTag() == "") {
          return Container();
        } else {
          return TencentCloudChatGroupProfileMemberListTag(
            tag: tag.getSuspensionTag(),
          );
        }
      },
      susItemHeight: getSquareSize(0),
    ));
  }
}

class TencentCloudChatGroupProfileMemberListItem extends StatefulWidget {
  final V2TimGroupInfo groupInfo;
  final V2TimGroupMemberFullInfo memberFullInfo;
  final Function(bool isSelect) onSelectGroupMember;

  const TencentCloudChatGroupProfileMemberListItem(
      {super.key,
      required this.memberFullInfo,
      required this.groupInfo,
      required this.onSelectGroupMember});

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatGroupProfileMemberListItemState();
}

class TencentCloudChatGroupProfileMemberListItemState
    extends TencentCloudChatState<TencentCloudChatGroupProfileMemberListItem> {
  bool isSelected = false;

  @override
  Widget defaultBuilder(BuildContext context) {
    String showName = widget.memberFullInfo.userID;
    if (TencentCloudChatUtils.checkString(widget.memberFullInfo.nickName) !=
        null) {
      showName = widget.memberFullInfo.nickName!;
    }

    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Container(
              color: colorTheme.backgroundColor,
              child: InkWell(
                  // toxee automation anchor. Shares the `mention_member:<uid>`
                  // contract with the DESKTOP inline mention panel
                  // (..._input_member_mention_panel.dart) so one real-UI case
                  // can drive either surface; the two are never mounted at the
                  // same time (platform-exclusive composers), and this
                  // list/item pair is instantiated only from
                  // TencentCloudChatAtGroupMemberList, so no other screen can
                  // produce a duplicate. The @everyone pseudo-member uses the
                  // SDK sentinel userID, which maps to the stable
                  // `mention_member:atAll` string
                  // (UiKeys.mentionMemberAtAll) rather than leaking the
                  // sentinel into the key.
                  key: ValueKey(
                    widget.memberFullInfo.userID == SDKConst.sdkAtAllUserID
                        ? 'mention_member:atAll'
                        : 'mention_member:${widget.memberFullInfo.userID}',
                  ),
                  onTap: () {
                    isSelected = !isSelected;
                    widget.onSelectGroupMember(isSelected);
                    setState(() {});
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: getHeight(8),
                      horizontal: getWidth(8),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          // toxee automation anchor: the ROW key proves the row
                          // exists; this one makes the ticked-but-not-committed
                          // state observable (multi-select before confirm).
                          key: ValueKey(widget.memberFullInfo.userID ==
                                  SDKConst.sdkAtAllUserID
                              ? 'mention_member_checkbox:atAll'
                              : 'mention_member_checkbox:${widget.memberFullInfo.userID}'),
                          value: isSelected,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          side: BorderSide(
                              width: 1, color: colorTheme.primaryTextColor),
                          onChanged: (bool? value) {
                            isSelected = value ?? false;
                            widget.onSelectGroupMember(isSelected);
                            setState(() {});
                          },
                        ),
                        Padding(
                            padding: EdgeInsets.only(right: getWidth(16)),
                            child: TencentCloudChatAvatar(
                              imageList: [
                                TencentCloudChatUtils.checkString(
                                    widget.memberFullInfo.faceUrl)
                              ],
                              width: getSquareSize(40),
                              height: getSquareSize(40),
                              borderRadius: getSquareSize(20),
                              scene: TencentCloudChatAvatarScene.groupProfile,
                            )),
                        Expanded(
                            child: Text(
                          showName,
                          style: TextStyle(
                              color: colorTheme.groupProfileTextColor,
                              fontSize: textStyle.fontsize_14),
                        )),
                      ],
                    ),
                  )),
            ));
  }
}

class TencentCloudChatGroupProfileMemberListTag extends StatefulWidget {
  final String tag;

  const TencentCloudChatGroupProfileMemberListTag({
    Key? key,
    required this.tag,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatGroupProfileMemberListTagState();
}

class TencentCloudChatGroupProfileMemberListTagState
    extends TencentCloudChatState<TencentCloudChatGroupProfileMemberListTag> {
  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Container(
            decoration: BoxDecoration(
              color: colorTheme.backgroundColor,
            ),
            // minHeight, not height: susItemHeight is 0 here so the tag is a
            // plain list row and may grow with large fonts.
            constraints: BoxConstraints(minHeight: getSquareSize(40)),
            width: MediaQuery.of(context).size.width,
            padding: const EdgeInsets.only(left: 16.0, bottom: 3),
            alignment: Alignment.bottomLeft,
            child: Text(
              "${widget.tag}",
              style: TextStyle(
                fontSize: textStyle.fontsize_14,
                fontWeight: FontWeight.w400,
                color: colorTheme.contactItemFriendNameColor,
              ),
            )));
  }
}
