import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_safe_dialog_pop.dart';

class TencentCloudChatModalAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  TencentCloudChatModalAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

void showTencentCloudChatBottomModal({
  required BuildContext context,
  required List<TencentCloudChatModalAction> actions,
}) {
  showModalBottomSheet(
    context: context,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // Rounded-top sheet surface (reference design); transparent host so the
    // themed, clipped container below owns the rounded corners.
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (BuildContext context) {
      return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            child: Container(
                padding: EdgeInsets.only(
                  top: 8,
                  right: 0,
                  left: 0,
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                color: colorTheme.inputAreaBackground,
                // Scrollable: the sheet's max height is 9/16 of the window, so
                // a long action list on a short phone overflowed instead of
                // scrolling.
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ...actions.map(
                      (e) => Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            popDialogIfCurrent(context);
                            e.onTap();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: ListTile(
                              leading: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colorTheme.primaryColor,
                                  border: Border.all(
                                      color: colorTheme.primaryColor, width: 8),
                                ),
                                child: Icon(
                                  e.icon,
                                  color: colorTheme.backgroundColor,
                                  size: textStyle.standardLargeText,
                                ),
                              ),
                              title: Text(e.label),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  ),
                ),
              )));
    },
  );
}
