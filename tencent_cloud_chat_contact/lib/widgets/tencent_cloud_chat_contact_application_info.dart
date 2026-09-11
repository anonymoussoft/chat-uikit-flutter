// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/data/theme/color/color_base.dart';
import 'package:tencent_cloud_chat_common/data/theme/text_style/text_style.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_code_info.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_safe_dialog_pop.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_common/builders/tencent_cloud_chat_common_builders.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';

class TencentCloudChatContactApplicationInfo extends StatefulWidget {
  final V2TimFriendApplication application;
  final ContactApplicationResult? applicationResult;

  const TencentCloudChatContactApplicationInfo({
    Key? key,
    required this.application,
    this.applicationResult,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactApplicationInfoState();
}

class TencentCloudChatContactApplicationInfoState
    extends TencentCloudChatState<TencentCloudChatContactApplicationInfo> {
  void getActionFromApplication(ContactApplicationResult result) {
    // safeSetState(() {
    //   widget.applicationResult = result;
    // });
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Scaffold(
            appBar: AppBar(
              leadingWidth: getWidth(100),
              leading: TencentCloudChatThemeWidget(
                  build: (context, colorTheme, textStyle) => GestureDetector(
                        key: const ValueKey(
                            'contact_detail_back'),
                        onTap: () => popDialogIfCurrent(context, widget.applicationResult),
                        child: Row(children: [
                          Padding(padding: EdgeInsets.only(left: getWidth(10))),
                          Icon(
                            Icons.arrow_back_ios_outlined,
                            color: colorTheme.contactBackButtonColor,
                            size: getSquareSize(24),
                          ),
                          Padding(padding: EdgeInsets.only(left: getWidth(8))),
                          Text(
                            tL10n.back,
                            style: TextStyle(
                              color: colorTheme.contactBackButtonColor,
                              fontSize: textStyle.fontsize_14,
                            ),
                          )
                        ]),
                      )),
              title: Text(
                tL10n.info,
                style: TextStyle(
                    fontSize: textStyle.fontsize_16,
                    fontWeight: FontWeight.w600,
                    color: colorTheme.contactItemFriendNameColor),
              ),
              centerTitle: true,
              backgroundColor: colorTheme.contactBackgroundColor,
            ),
            body: Container(
              color: colorTheme.contactApplicationBackgroundColor,
              child: Center(
                child: TencentCloudChatContactApplicationInfoBody(
                    application: widget.application,
                    resultFunction: getActionFromApplication,
                    applicationResult: widget.applicationResult),
              ),
            )));
  }
}

class TencentCloudChatContactApplicationInfoBody extends StatefulWidget {
  final V2TimFriendApplication application;
  final Function? resultFunction;
  final ContactApplicationResult? applicationResult;

  const TencentCloudChatContactApplicationInfoBody({
    Key? key,
    required this.application,
    this.resultFunction,
    this.applicationResult,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactApplicationInfoBodyState();
}

class TencentCloudChatContactApplicationInfoBodyState
    extends TencentCloudChatState<TencentCloudChatContactApplicationInfoBody> {
  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Column(
              children: [
                Container(
                  margin: EdgeInsets.only(top: getHeight(28)),
                  padding: EdgeInsets.symmetric(vertical: getHeight(10), horizontal: getWidth(16)),
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(
                      width: 1,
                      color: colorTheme.contactItemTabItemBorderColor,
                    )),
                    color: colorTheme.contactBackgroundColor,
                  ),
                  child: Row(children: [
                    TencentCloudChat.instance.dataInstance.contact.contactBuilder
                        ?.getContactApplicationInfoAvatarBuilder(widget.application),
                    TencentCloudChat.instance.dataInstance.contact.contactBuilder
                        ?.getContactApplicationInfoContentBuilder(widget.application)
                  ]),
                ),
                Container(
                  color: colorTheme.contactBackgroundColor,
                  padding: EdgeInsets.symmetric(vertical: getHeight(12), horizontal: getWidth(16)),
                  child: TencentCloudChat.instance.dataInstance.contact.contactBuilder
                      ?.getContactApplicationInfoAddWordingBuilder(widget.application),
                ),
                Row(
                  children: [
                    // Expanded: the buttons fill the row from bounded
                    // constraints instead of sizing to the screen width.
                    Expanded(
                      child: TencentCloudChat.instance.dataInstance.contact.contactBuilder
                              ?.getContactApplicationInfoButtonBuilder(
                                  widget.application, widget.resultFunction, widget.applicationResult) ??
                          const SizedBox.shrink(),
                    )
                  ],
                )
              ],
            ));
  }
}

class TencentCloudChatContactApplicationInfoAvatar extends StatefulWidget {
  final V2TimFriendApplication application;

  const TencentCloudChatContactApplicationInfoAvatar({super.key, required this.application});

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactApplicationInfoAvatarState();
}

class TencentCloudChatContactApplicationInfoAvatarState
    extends TencentCloudChatState<TencentCloudChatContactApplicationInfoAvatar> {
  @override
  Widget defaultBuilder(BuildContext context) {
    // Tox friend applications carry no avatar URL, so faceUrl is null here.
    // The upstream `faceUrl!` null-asserts and throws ("Null check operator used
    // on a null value") during build, which replaces this avatar with an
    // ErrorWidget whose unbounded intrinsic size then overflows the parent
    // Row/Column by ~99k px. Treat null as empty so the default-avatar branch
    // renders. (Shared UIKit code → fixes desktop + mobile alike.)
    if ((widget.application.faceUrl ?? '').isEmpty) {
      return Padding(
          padding: EdgeInsets.symmetric(horizontal: getWidth(13)),
          child: TencentCloudChatCommonBuilders.getCommonAvatarBuilder(
            scene: TencentCloudChatAvatarScene.contacts,
            imageList: [widget.application.faceUrl],
            width: getSquareSize(43),
            height: getSquareSize(43),
            // Friend application (person) → circle (radius = size / 2).
            borderRadius: getSquareSize(21.5),
          ));
    }
    return Padding(
        padding: EdgeInsets.symmetric(horizontal: getWidth(13)),
        child: TencentCloudChatCommonBuilders.getCommonAvatarBuilder(
          scene: TencentCloudChatAvatarScene.contacts,
          imageList: [widget.application.faceUrl],
          width: getSquareSize(43),
          height: getSquareSize(43),
          borderRadius: getSquareSize(38),
        ));
  }
}

class TencentCloudChatContactApplicationInfoContent extends StatefulWidget {
  final V2TimFriendApplication application;

  const TencentCloudChatContactApplicationInfoContent({super.key, required this.application});

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactApplicationInfoContentState();
}

class TencentCloudChatContactApplicationInfoContentState
    extends TencentCloudChatState<TencentCloudChatContactApplicationInfoContent> {
  @override
  Widget defaultBuilder(BuildContext context) {
    return Expanded(
        child: TencentCloudChatThemeWidget(
            build: (context, colorTheme, textStyle) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      widget.application.nickname ?? widget.application.userID,
                      style: TextStyle(
                          fontSize: textStyle.fontsize_16,
                          fontWeight: FontWeight.w600,
                          color: colorTheme.contactItemFriendNameColor),
                    ),
                    Text(
                      "ID: ${widget.application.userID}",
                      style: TextStyle(
                          color: colorTheme.contactItemFriendNameColor,
                          fontSize: textStyle.fontsize_12,
                          fontWeight: FontWeight.w400),
                    )
                  ],
                )));
  }
}

class TencentCloudChatContentApplicationInfoAddwording extends StatefulWidget {
  final V2TimFriendApplication application;

  const TencentCloudChatContentApplicationInfoAddwording({super.key, required this.application});

  @override
  State<StatefulWidget> createState() => TencentCloudChatContentApplicationInfoAddwordingState();
}

class TencentCloudChatContentApplicationInfoAddwordingState
    extends TencentCloudChatState<TencentCloudChatContentApplicationInfoAddwording> {
  Widget getAddWording(TencentCloudChatThemeColors colorTheme, TencentCloudChatTextStyle textStyle) {
    String addwording = "hello";
    if (widget.application.addWording != null) {
      addwording = widget.application.addWording!;
    }
    Widget w = addwording.isEmpty
        ? Container()
        : Text(
            addwording,
            style: TextStyle(
                color: colorTheme.contactItemFriendNameColor,
                fontSize: textStyle.fontsize_16,
                fontWeight: FontWeight.w400),
          );
    return w;
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Container(
            padding: EdgeInsets.symmetric(horizontal: getWidth(16)),
            child: Row(
              children: [
                Expanded(
                    child: Text(
                  tL10n.validationMessages,
                  style: TextStyle(
                    color: colorTheme.contactItemTabItemNameColor,
                    fontSize: textStyle.fontsize_16,
                    fontWeight: FontWeight.w400,
                  ),
                )),
                getAddWording(colorTheme, textStyle)
              ],
            )));
  }
}

class TencentCloudChatContactApplicationInfoButton extends StatefulWidget {
  final V2TimFriendApplication application;
  final Function? resultFunction;
  final ContactApplicationResult? applicationResult;

  const TencentCloudChatContactApplicationInfoButton(
      {super.key, required this.application, this.resultFunction, this.applicationResult});

  @override
  State<StatefulWidget> createState() => TencentCloudChatContactApplicationInfoButtonState();
}

class TencentCloudChatContactApplicationInfoButtonState
    extends TencentCloudChatState<TencentCloudChatContactApplicationInfoButton> {
  onAcceptApplication() async {
    V2TimFriendOperationResult res = await TencentCloudChat.instance.chatSDKInstance.contactSDK.acceptFriendApplication(
        widget.application.userID,
        FriendResponseTypeEnum.V2TIM_FRIEND_ACCEPT_AGREE_AND_ADD,
        FriendApplicationTypeEnum.values[widget.application.type]);
    String id = res.userID ?? "";
    int code = res.resultCode ?? -1;
    if (id == widget.application.userID && code == 0) {
      safeSetState(() {
        widget.applicationResult!.result = tL10n.accepted;
        widget.applicationResult!.userID = widget.application.userID;
      });
      if (widget.resultFunction != null) {
        ContactApplicationResult res =
            ContactApplicationResult(result: tL10n.accepted, userID: widget.application.userID);
        widget.resultFunction!(res);
      }
    } else {
      TencentCloudChat.instance.callbacks.onUserNotificationEvent(
          TencentCloudChatComponentsEnum.contact,
          TencentCloudChatUserNotificationEvent(
            eventCode: code,
            text: tL10n.invalidApplication,
          ));

      // After success, delete the application proactively (IMSDK does not give notification of application deletion in such case)
      TencentCloudChat.instance.dataInstance.contact
          .deleteApplicationList([widget.application.userID], 'onFriendApplicationListDeleted');
    }
  }

  onRefuseApplication() async {
    V2TimFriendOperationResult res = await TencentCloudChat.instance.chatSDKInstance.contactSDK
        .refuseFriendApplication(widget.application.userID, FriendApplicationTypeEnum.values[widget.application.type]);
    String id = res.userID ?? "";
    int code = res.resultCode ?? -1;
    if (id == widget.application.userID && code == 0) {
      safeSetState(() {
        widget.applicationResult!.result = tL10n.declined;
        widget.applicationResult!.userID = widget.application.userID;
      });
      if (widget.resultFunction != null) {
        ContactApplicationResult res =
            ContactApplicationResult(result: tL10n.declined, userID: widget.application.userID);
        widget.resultFunction!(res);
      }
    } else {
      TencentCloudChat.instance.callbacks.onUserNotificationEvent(
          TencentCloudChatComponentsEnum.contact,
          TencentCloudChatUserNotificationEvent(
            eventCode: code,
            text: tL10n.invalidApplication,
          ));

      TencentCloudChat.instance.dataInstance.contact
          .deleteApplicationList([widget.application.userID], 'onFriendApplicationListDeleted');
    }
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    if (widget.applicationResult!.userID == widget.application.userID && widget.applicationResult!.result.isNotEmpty) {
      return TencentCloudChatThemeWidget(
          build: (context, colorTheme, textStyle) => Container(
                width: double.infinity,
                color: colorTheme.contactBackgroundColor,
                margin: EdgeInsets.only(top: getHeight(20)),
                padding: EdgeInsets.symmetric(horizontal: getWidth(20), vertical: getHeight(10)),
                child: Text(
                  widget.applicationResult!.result,
                  style: TextStyle(
                      color: colorTheme.contactItemTabItemNameColor,
                      fontSize: textStyle.fontsize_12,
                      fontWeight: FontWeight.w400),
                ),
              ));
    }
    return Container(
        margin: EdgeInsets.only(top: getHeight(20)),
        child: TencentCloudChatThemeWidget(
            build: (context, colorTheme, textStyle) => Column(children: [
                  Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                            width: 1,
                            color: colorTheme.contactItemTabItemBorderColor,
                          )),
                          color: colorTheme.backgroundColor),
                      padding: EdgeInsets.symmetric(vertical: getHeight(10), horizontal: getWidth(20)),
                      child: GestureDetector(
                          key: ValueKey(
                            'contact_application_detail_accept_button:${widget.application.userID}',
                          ),
                          onTap: onAcceptApplication,
                          child: Text(
                            tL10n.agree,
                            style: TextStyle(
                                color: colorTheme.contactAgreeButtonColor,
                                fontSize: textStyle.fontsize_16,
                                fontWeight: FontWeight.w400),
                          ))),
                  Container(
                      color: colorTheme.backgroundColor,
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: getHeight(10), horizontal: getWidth(20)),
                      child: GestureDetector(
                          key: ValueKey(
                            'contact_application_detail_decline_button:${widget.application.userID}',
                          ),
                          onTap: onRefuseApplication,
                          child: Text(
                            tL10n.refuse,
                            style: TextStyle(
                                color: colorTheme.contactRefuseButtonColor,
                                fontSize: textStyle.fontsize_16,
                                fontWeight: FontWeight.w400),
                          )))
                ])));
  }
}

class TencentCloudChatContactApplicationInfoData {
  final V2TimFriendApplication application;
  final ContactApplicationResult? applicationResult;

  TencentCloudChatContactApplicationInfoData({required this.application, this.applicationResult});

  Map<String, dynamic> toMap() {
    return {'application': application.toString()};
  }

  static TencentCloudChatContactApplicationInfoData fromMap(Map<String, dynamic> map) {
    return TencentCloudChatContactApplicationInfoData(
        application: map['application'] as V2TimFriendApplication,
        applicationResult: map['applicationResult'] as ContactApplicationResult);
  }
}
