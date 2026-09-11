import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_safe_dialog_pop.dart';

class TencentCloudChatContactLeading extends StatefulWidget {
  const TencentCloudChatContactLeading({super.key});

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactLeadingState();
}

class TencentCloudChatContactLeadingState
    extends TencentCloudChatState<TencentCloudChatContactLeading> {
  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => GestureDetector(
              key: const ValueKey('contact_detail_back'),
              onTap: () => popDialogIfCurrent(context),
              child: Row(children: [
                Padding(padding: EdgeInsets.only(left: getWidth(10))),
                Icon(
                  Icons.arrow_back_ios_outlined,
                  color: colorTheme.contactBackButtonColor,
                  size: getSquareSize(24),
                ),
                Padding(padding: EdgeInsets.only(left: getWidth(8))),
                // Flexible: hosts give this a fixed leadingWidth (100 px);
                // long locales / large text would overflow it.
                Flexible(
                  child: Text(
                    tL10n.back,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorTheme.contactBackButtonColor,
                      fontSize: textStyle.fontsize_14,
                    ),
                  ),
                )
              ]),
            ));
  }
}
