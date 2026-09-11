// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_state_widget.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';

class TencentCloudChatContactTabItem extends StatefulWidget {
  final TTabItem item;

  const TencentCloudChatContactTabItem({super.key, required this.item});

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactTabItemState();
}

class TencentCloudChatContactTabItemState
    extends TencentCloudChatState<TencentCloudChatContactTabItem> {
  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatContactTab(item: widget.item);
  }
}

class TencentCloudChatContactTab extends StatefulWidget {
  final TTabItem item;

  const TencentCloudChatContactTab({super.key, required this.item});

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactTabState();
}

class TencentCloudChatContactTabState
    extends TencentCloudChatState<TencentCloudChatContactTab> {
  Widget getUnreadCount() {
    if (widget.item.unreadCount != null) {
      return TencentCloudChatContactTabItemApplicationCount(
          count: widget.item.unreadCount ?? 0);
    }
    return Container();
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    final tabKey = switch (widget.item.id) {
      'new_contacts' => const ValueKey('contact_new_contacts_tab'),
      'group_notification' => const ValueKey('contact_group_notifications_tab'),
      'blocked_users' => const ValueKey('contact_blocked_users_tab'),
      _ => null,
    };
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => GestureDetector(
        key: tabKey,
        onTap: widget.item.onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              vertical: getHeight(12), horizontal: getWidth(16)),
          decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: colorTheme.contactItemTabItemBorderColor)),
            color: colorTheme.contactTabItemBackgroundColor,
          ),
          child: Row(
            children: [
              SizedBox(
                width: getSquareSize(24),
                height: getSquareSize(24),
                child: Icon(
                  widget.item.icon,
                  color: colorTheme.primaryColor,
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                  child: Container(
                      padding: EdgeInsets.only(left: getWidth(4)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Expanded: the name gets all remaining width (a
                          // blank Expanded sibling used to take half of it).
                          Expanded(
                            child: Text(
                              widget.item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: textStyle.fontsize_16,
                                  fontWeight: FontWeight.w400,
                                  color:
                                      colorTheme.contactItemTabItemNameColor),
                            ),
                          ),
                          getUnreadCount(),
                          Icon(
                            Icons.keyboard_arrow_right,
                            color: colorTheme.contactItemTabItemNameColor,
                          )
                        ],
                      )))
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget desktopBuilder(BuildContext context) {
    final tabKey = switch (widget.item.id) {
      'new_contacts' => const ValueKey('contact_new_contacts_tab'),
      'group_notification' => const ValueKey('contact_group_notifications_tab'),
      'blocked_users' => const ValueKey('contact_blocked_users_tab'),
      _ => null,
    };
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Material(
        color: colorTheme.contactTabItemBackgroundColor,
        child: InkWell(
          key: tabKey,
          onTap: widget.item.onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
                vertical: getHeight(12), horizontal: getWidth(16)),
            decoration: BoxDecoration(
              border: Border(
                bottom:
                    BorderSide(color: colorTheme.contactItemTabItemBorderColor),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.item.icon,
                  color: colorTheme.primaryColor,
                  size: 20,
                ),
                Expanded(
                  child: Container(
                    padding: EdgeInsets.only(left: getWidth(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Expanded: the name gets all remaining width (a
                        // blank Expanded sibling used to take half of it).
                        Expanded(
                          child: Text(
                            widget.item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: textStyle.fontsize_14,
                                color: colorTheme.secondaryTextColor),
                          ),
                        ),
                        getUnreadCount(),
                        Icon(
                          Icons.keyboard_arrow_right,
                          color: colorTheme.contactItemTabItemNameColor,
                        )
                      ],
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
}

class TencentCloudChatContactTabItemApplicationCount extends StatefulWidget {
  final int count;

  const TencentCloudChatContactTabItemApplicationCount({
    Key? key,
    required this.count,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() =>
      TencentCloudChatContactTabItemApplicationCountState();
}

class TencentCloudChatContactTabItemApplicationCountState
    extends TencentCloudChatState<
        TencentCloudChatContactTabItemApplicationCount> {
  @override
  Widget defaultBuilder(BuildContext context) {
    if (widget.count > 0) {
      String text = widget.count.toString();
      return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => Container(
                // Min-size pill instead of a fixed 16/26 px box so "99+" still
                // fits when the text scale grows; shape/radius unchanged.
                constraints: BoxConstraints(
                    minWidth: getWidth(16), minHeight: getHeight(16)),
                padding: EdgeInsets.symmetric(
                    horizontal: text.length == 1 ? 0 : getWidth(4)),
                decoration: BoxDecoration(
                  color: colorTheme.tipsColor,
                  borderRadius: BorderRadius.all(
                    Radius.circular(
                      getSquareSize(8),
                    ),
                  ),
                ),
                // Shrink-wrap: without the factors Center would fill the
                // loose parent constraints now that the box has no fixed width.
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: textStyle.fontsize_10,
                      fontWeight: FontWeight.w600,
                      color: colorTheme.contactApplicationUnreadCountTextColor,
                    ),
                  ),
                ),
              ));
    }
    return Container();
  }
}
