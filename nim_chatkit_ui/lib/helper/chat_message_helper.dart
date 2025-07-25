// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:netease_common/netease_common.dart';
import 'package:netease_common_ui/ui/dialog.dart';
import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:nim_chatkit/im_kit_client.dart';
import 'package:nim_chatkit/model/ait/ait_contacts_model.dart';
import 'package:nim_chatkit/model/ait/ait_msg.dart';
import 'package:nim_chatkit/model/contact_info.dart';
import 'package:nim_chatkit/model/custom_type_constant.dart';
import 'package:nim_chatkit/model/team_models.dart';
import 'package:nim_chatkit/repo/config_repo.dart';
import 'package:nim_chatkit/router/imkit_router_factory.dart';
import 'package:nim_chatkit/service_locator.dart';
import 'package:nim_chatkit/services/contact/contact_provider.dart';
import 'package:nim_chatkit/services/message/chat_message.dart';
import 'package:nim_chatkit/services/team/team_provider.dart';
import 'package:nim_chatkit/message/message_helper.dart';
import 'package:nim_chatkit_ui/chat_kit_client.dart';
import 'package:nim_chatkit_ui/l10n/S.dart';
import 'package:nim_chatkit_ui/view/input/emoji/emoji_text.dart';

import '../view/chat_kit_message_list/item/chat_kit_message_multi_line_text_item.dart';
import '../view/chat_kit_message_list/widgets/chat_forward_dialog.dart';
import 'chat_message_user_helper.dart';
import 'merge_message_helper.dart';
import 'package:nim_core_v2/nim_core.dart';

///定义转发方法
///[isLastUser] 是否是最后一个用户,用于转发给多个用户的case，主要用于合并转发和逐条转发
///[postScript] 转发附言
///[conversationId] 会话id
typedef ForwardMessageFunction = Function(String conversationId,
    {String? postScript, bool isLastUser});

class NotifyHelper {
  static Future<String> getNotificationText(NIMMessage message) async {
    if (message.attachment is NIMMessageNotificationAttachment) {
      NIMMessageNotificationAttachment attachment =
          message.attachment as NIMMessageNotificationAttachment;
      var teamId = (await NimCore.instance.conversationIdUtil
              .conversationTargetId(message.conversationId!))
          .data!;
      switch (attachment.type) {
        case NIMMessageNotificationType.teamInvite:
          return buildInviteMemberNotification(
              teamId, message.senderId!, attachment);
        case NIMMessageNotificationType.teamKick:
          return buildKickMemberNotification(teamId, attachment);
        case NIMMessageNotificationType.teamLeave:
          return buildMemberLeaveNotification(teamId, message.senderId!);
        case NIMMessageNotificationType.teamDismiss:
          return buildTeamDismissNotification(teamId, message.senderId!);
        case NIMMessageNotificationType.teamUpdateTInfo:
          return buildUpdateTeamNotification(
              teamId, message.senderId!, attachment);
        case NIMMessageNotificationType.teamApplyPass:
          return buildManagerPassTeamApplyNotification(teamId, attachment);
        case NIMMessageNotificationType.teamOwnerTransfer:
          return buildTeamTransOwnerNotification(
              teamId, message.senderId!, attachment);
        case NIMMessageNotificationType.teamAddManager:
          return buildTeamAddManagerNotification(teamId, attachment);
        case NIMMessageNotificationType.teamRemoveManager:
          return buildTeamRemoveManagerNotification(teamId, attachment);
        case NIMMessageNotificationType.teamInviteAccept:
          return buildAcceptInviteNotification(
              teamId, message.senderId!, attachment);
        case NIMMessageNotificationType.teamBannedTeamMember:
          return buildMuteTeamNotification(teamId, attachment);
        default:
          return S.of().chatMessageUnknownNotification;
      }
    } else {
      return S.of().chatMessageUnknownNotification;
    }
  }

  static Future<String> buildUpdateTeamNotification(String tid,
      String fromAccId, NIMMessageNotificationAttachment attachment) async {
    if (attachment.updatedTeamInfo?.name != null) {
      var fromName = await getTeamMemberDisplayName(tid, fromAccId);
      return S.of().chatTeamNotifyUpdateName(
          fromName, attachment.updatedTeamInfo!.name!);
    } else if (attachment.updatedTeamInfo?.intro != null) {
      var fromName = await getTeamMemberDisplayName(tid, fromAccId);
      return S.of().chatTeamNotifyUpdateIntroduction(fromName);
    } else if (attachment.updatedTeamInfo?.announcement != null) {
      return S
          .of()
          .chatTeamNoticeUpdate(attachment.updatedTeamInfo!.announcement!);
    } else if (attachment.updatedTeamInfo?.joinMode != null &&
        attachment.updatedTeamInfo?.joinMode != NIMTeamJoinMode.unknown) {
      if (attachment.updatedTeamInfo?.joinMode ==
          NIMTeamJoinMode.joinModeApply) {
        var fromName = await getTeamMemberDisplayName(tid, fromAccId);
        return S.of().chatTeamVerifyUpdateAsNeedVerify(fromName);
      } else if (attachment.updatedTeamInfo?.joinMode ==
          NIMTeamJoinMode.joinModeInvite) {
        return S.of().chatTeamVerifyUpdateAsDisallowAnyoneJoin;
      } else {
        var fromName = await getTeamMemberDisplayName(tid, fromAccId);
        return S.of().chatTeamVerifyUpdateAsNeedNoVerify(fromName);
      }
    } else if (attachment.updatedTeamInfo?.serverExtension.isNotEmpty == true) {
      try {
        Map<String, dynamic> extension =
            json.decode(attachment.updatedTeamInfo!.serverExtension!);
        if (extension[lastOption] == aitPrivilegeKey) {
          if (extension[aitPrivilegeKey] == aitPrivilegeAll) {
            return S.of().teamMsgAitAllPrivilegeIsAll;
          } else {
            return S.of().teamMsgAitAllPrivilegeIsOwner;
          }
        }
      } catch (e) {
        Alog.e(tag: 'MessageHelper', content: 'e : ${e.toString()}');
      }
      return S.of().chatTeamNotifyUpdateExtension(
          attachment.updatedTeamInfo!.serverExtension!);
    } else if (attachment.updatedTeamInfo?.avatar.isNotEmpty == true) {
      var fromName = await getTeamMemberDisplayName(tid, fromAccId);
      return S.of().chatTeamNotifyUpdateTeamAvatar(fromName);
    } else if (attachment.updatedTeamInfo?.inviteMode != null &&
        attachment.updatedTeamInfo?.inviteMode != NIMTeamInviteMode.unknown) {
      var fromName = await getTeamMemberDisplayName(tid, fromAccId);
      return S.of().chatTeamInvitationPermissionUpdate(fromName,
          getTeamInvitePermissionName(attachment.updatedTeamInfo!.inviteMode!));
    } else if (attachment.updatedTeamInfo?.updateInfoMode != null &&
        attachment.updatedTeamInfo?.updateInfoMode !=
            NIMTeamUpdateInfoMode.unknown) {
      var fromName = await getTeamMemberDisplayName(tid, fromAccId);
      return S.of().chatTeamModifyResourcePermissionUpdate(
          fromName,
          getTeamUpdatePermissionName(
              attachment.updatedTeamInfo!.updateInfoMode!));
    } else if (attachment.updatedTeamInfo?.agreeMode != null) {
      if (attachment.updatedTeamInfo?.agreeMode ==
          NIMTeamAgreeMode.agreeModeAuth) {
        var fromName = await getTeamMemberDisplayName(tid, fromAccId);
        return S.of().chatTeamInviteUpdateAsNeedVerify(fromName);
      } else if (attachment.updatedTeamInfo?.agreeMode ==
          NIMTeamAgreeMode.agreeModeNoAuth) {
        var fromName = await getTeamMemberDisplayName(tid, fromAccId);
        return S.of().chatTeamInviteUpdateAsNeedNoVerify(fromName);
      }
    } else if (attachment.updatedTeamInfo?.updateExtensionMode != null &&
        attachment.updatedTeamInfo?.updateExtensionMode !=
            NIMTeamUpdateExtensionMode.unknown) {
      return S.of().chatTeamModifyExtensionPermissionUpdate(
          attachment.updatedTeamInfo!.updateExtensionMode!.name);
    } else if (attachment.updatedTeamInfo?.chatBannedMode != null &&
        attachment.updatedTeamInfo?.chatBannedMode != -1) {
      if (attachment.updatedTeamInfo?.chatBannedMode == 0) {
        return S.of().chatTeamCancelAllMute;
      } else {
        return S.of().chatTeamFullMute;
      }
    }
    return S.of().chatMessageUnknownNotification;
  }

  static Future<String> buildInviteMemberNotification(String tid,
      String fromAccId, NIMMessageNotificationAttachment attachment) async {
    var fromName = await getTeamMemberDisplayName(tid, fromAccId);
    var memberNames = await buildMemberListString(tid, attachment.targetIds!,
        fromAccount: fromAccId, needTeamNick: false);
    var team = (await NimCore.instance.teamService
            .getTeamInfo(tid, NIMTeamType.typeNormal))
        .data;
    if (team != null && !getIt<TeamProvider>().isGroupTeam(team)) {
      return S.of().chatAdviceTeamNotifyInvite(fromName, memberNames);
    } else {
      return S.of().chatDiscussTeamNotifyInvite(fromName, memberNames);
    }
  }

  static Future<String> buildKickMemberNotification(
      String tid, NIMMessageNotificationAttachment attachment) async {
    var team = (await NimCore.instance.teamService
            .getTeamInfo(tid, NIMTeamType.typeNormal))
        .data;
    var members = await buildMemberListString(tid, attachment.targetIds!);
    if (team != null && !getIt<TeamProvider>().isGroupTeam(team)) {
      return S.of().chatAdvancedTeamNotifyRemove(members);
    } else {
      return S.of().chatDiscussTeamNotifyRemove(members);
    }
  }

  static Future<String> buildMemberLeaveNotification(
      String tid, String fromAccId) async {
    var team = (await NimCore.instance.teamService
            .getTeamInfo(tid, NIMTeamType.typeNormal))
        .data;
    var members = await getTeamMemberDisplayName(tid, fromAccId);
    if (team != null && !getIt<TeamProvider>().isGroupTeam(team)) {
      return S.of().chatAdvancedTeamNotifyLeave(members);
    } else {
      return S.of().chatDiscussTeamNotifyLeave(members);
    }
  }

  static Future<String> buildTeamDismissNotification(
      String tid, String fromAccId) async {
    return S
        .of()
        .chatTeamNotifyDismiss(await getTeamMemberDisplayName(tid, fromAccId));
  }

  static Future<String> buildManagerPassTeamApplyNotification(
      String tid, NIMMessageNotificationAttachment attachment) async {
    return S.of().chatTeamNotifyManagerPass(
        await buildMemberListString(tid, attachment.targetIds!));
  }

  static Future<String> buildTeamTransOwnerNotification(String tid, String from,
      NIMMessageNotificationAttachment attachment) async {
    return S.of().chatTeamNotifyTransOwner(
        await buildMemberListString(tid, attachment.targetIds!),
        (await getTeamMemberDisplayName(tid, from)));
  }

  static Future<String> buildTeamAddManagerNotification(
      String tid, NIMMessageNotificationAttachment attachment) async {
    return S.of().chatTeamNotifyAddManager(
        await buildMemberListString(tid, attachment.targetIds!));
  }

  static Future<String> buildTeamRemoveManagerNotification(
      String tid, NIMMessageNotificationAttachment attachment) async {
    return S.of().chatTeamNotifyRemoveManager(
        await buildMemberListString(tid, attachment.targetIds!));
  }

  static Future<String> buildAcceptInviteNotification(String tid, String from,
      NIMMessageNotificationAttachment attachment) async {
    return S.of().chatTeamNotifyAcceptInvite(
        await buildMemberListString(tid, attachment.targetIds!,
            needTeamNick: false),
        (await getTeamMemberDisplayName(tid, from)));
  }

  static Future<String> buildMuteTeamNotification(
      String tid, NIMMessageNotificationAttachment attachment) async {
    if (attachment.chatBanned == true) {
      return S.of().chatTeamNotifyMute(
          await buildMemberListString(tid, attachment.targetIds!));
    } else {
      return S.of().chatTeamNotifyUnMute(
          await buildMemberListString(tid, attachment.targetIds!));
    }
  }

  static Future<String> buildMemberListString(String tid, List<String> members,
      {String? fromAccount, bool needTeamNick = true}) async {
    String memberList = '';
    if (needTeamNick == false) {
      var contactList = await getIt<ContactProvider>().fetchUserList(members);
      for (var contact in contactList) {
        if (fromAccount != contact.user.accountId) {
          if (contact.user.accountId == IMKitClient.account()) {
            memberList = memberList + S.of().chatMessageYou + '、';
          } else {
            memberList = memberList + contact.getName() + '、';
          }
        }
      }
    } else {
      for (var member in members) {
        if (fromAccount != member) {
          var name = await getTeamMemberDisplayName(tid, member);
          memberList = memberList + name + '、';
        }
      }
    }
    return memberList.endsWith('、')
        ? memberList.substring(0, memberList.length - 1)
        : memberList;
  }

  static Future<String> getTeamMemberDisplayName(
      String tid, String accId) async {
    if (accId == IMKitClient.account()) {
      return S.of().chatMessageYou;
    }
    return getUserNickInTeam(tid, accId);
  }

  static Future<String?> getTeamMemberNick(String tid, String accId) async {
    var memberResult = await NimCore.instance.teamService
        .getTeamMemberListByIds(tid, NIMTeamType.typeNormal, [accId]);
    if (memberResult.isSuccess && memberResult.data?.isNotEmpty == true) {
      return memberResult.data?[0].teamNick;
    }
    return null;
  }

  static String getTeamInvitePermissionName(NIMTeamInviteMode mode) {
    return mode == NIMTeamInviteMode.inviteModeAll
        ? S.of().chatTeamPermissionInviteAll
        : S.of().chatTeamPermissionInviteOnlyOwnerAndManagers;
  }

  static String getTeamUpdatePermissionName(NIMTeamUpdateInfoMode mode) {
    return mode == NIMTeamUpdateInfoMode.updateInfoModeAll
        ? S.of().chatTeamPermissionUpdateAll
        : S.of().chatTeamPermissionUpdateOnlyOwnerAndManagers;
  }
}

class ChatMessageHelper {
  static Future<String> getReplayMessageTextById(
      BuildContext context, String messageId, String conversationId) async {
    var messageResult = await NimCore.instance.messageService
        .getMessageListByIds(messageClientIds: [messageId]);
    return _getMessageContent(context, conversationId, messageResult);
  }

  static Future<String> getReplayMessageText(BuildContext context,
      NIMMessageRefer messageRefer, String conversationId) async {
    var messageResult = await NimCore.instance.messageService
        .getMessageListByRefers(messageRefers: [messageRefer]);

    return _getMessageContent(context, conversationId, messageResult);
  }

  static Future<String> _getMessageContent(BuildContext context,
      String conversationId, NIMResult<List<NIMMessage>> messageResult) async {
    if (messageResult.isSuccess) {
      if (messageResult.data?.isNotEmpty == true) {
        NIMMessage nimMessage = messageResult.data!.first;
        var teamId = null;
        if (nimMessage.conversationType == NIMConversationType.team) {
          teamId = (await NimCore.instance.conversationIdUtil
                  .conversationTargetId(nimMessage.conversationId!))
              .data;
        }
        String nick = nimMessage.conversationType == NIMConversationType.p2p
            ? await nimMessage.senderId!.getUserName()
            : await getUserNickInTeam(teamId ?? '', nimMessage.senderId!,
                showAlias: false);
        String content = getMessageBrief(nimMessage);
        return '$nick : $content';
      } else {
        return S.of(context).chatMessageHaveBeenRevokedOrDelete;
      }
    } else {
      return '';
    }
  }

  static String getMessageBrief(NIMMessage message) {
    String brief = 'unknown';
    var customBrief =
        ChatKitClient.instance.chatUIConfig.getMessageBrief?.call(message);
    if (customBrief?.isNotEmpty == true) {
      brief = customBrief!;
      return brief;
    }
    switch (message.messageType) {
      case NIMMessageType.text:
        brief = message.text!;
        break;
      case NIMMessageType.image:
        brief = S.of().chatMessageBriefImage;
        break;
      case NIMMessageType.audio:
        brief = S.of().chatMessageBriefAudio;
        break;
      case NIMMessageType.video:
        brief = S.of().chatMessageBriefVideo;
        break;
      case NIMMessageType.location:
        brief = S.of().chatMessageBriefLocation;
        break;
      case NIMMessageType.file:
        brief = S.of().chatMessageBriefFile;
        break;
      case NIMMessageType.avChat:
        //todo avChat
        brief = S.of().chatMessageNonsupport;
        break;
      case NIMMessageType.custom:
        var mergedMessage = MergeMessageHelper.parseMergeMessage(message);
        if (mergedMessage != null) {
          brief = S.of().chatMessageBriefChatHistory;
        } else {
          var multiLineMap = MessageHelper.parseMultiLineMessage(message);
          if (multiLineMap != null &&
              multiLineMap[ChatMessage.keyMultiLineTitle] != null) {
            brief = multiLineMap[ChatMessage.keyMultiLineTitle]!;
          } else {
            brief = S.of().chatMessageBriefCustom;
          }
        }
        break;
      default:
        brief = S.of().chatMessageNonsupport;
        break;
    }
    return brief;
  }

  ///显示转发选择框
  static void showForwardMessageDialog(
      BuildContext context, ForwardMessageFunction forwardMessage,
      {List<String>? filterUser,
      required String sessionName,
      ForwardType type = ForwardType.normal}) {
    // 转发
    var style = const TextStyle(fontSize: 16, color: CommonColors.color_333333);
    showBottomChoose<int>(context: context, actions: [
      CupertinoActionSheetAction(
        onPressed: () {
          Navigator.pop(context, 2);
        },
        child: Text(
          S.of(context).messageForwardToTeam,
          style: style,
        ),
      ),
      CupertinoActionSheetAction(
        onPressed: () {
          Navigator.pop(context, 1);
        },
        child: Text(
          S.of(context).messageForwardToP2p,
          style: style,
        ),
      )
    ]).then((value) {
      if (value == 1) {
        _goContactSelector(context, forwardMessage,
            filterUser: filterUser, sessionName: sessionName, type: type);
      } else if (value == 2) {
        _goTeamSelector(context, forwardMessage,
            sessionName: sessionName, type: type);
      }
    });
  }

  //转发到群
  static void _goTeamSelector(
      BuildContext context, ForwardMessageFunction forwardMessage,
      {required String sessionName, ForwardType type = ForwardType.normal}) {
    String forwardStr;
    if (type == ForwardType.normal) {
      forwardStr = S.of(context).messageForwardMessageTips(sessionName);
    } else if (type == ForwardType.merge) {
      forwardStr = S.of(context).messageForwardMessageMergedTips(sessionName);
    } else {
      forwardStr = S.of(context).messageForwardMessageOneByOneTips(sessionName);
    }
    goTeamListPage(context, selectorModel: true).then((result) async {
      if (result is NIMTeam) {
        showChatForwardDialog(
                context: context, contentStr: forwardStr, team: result)
            .then((forward) async {
          if (forward != null && forward.result == true) {
            var conversationId = (await NimCore.instance.conversationIdUtil
                    .teamConversationId(result.teamId))
                .data;
            forwardMessage(conversationId ?? '',
                postScript: forward.postScript, isLastUser: true);
          }
          hideKeyboard();
        });
      }
    });
  }

  //转发到个人
  static void _goContactSelector(
      BuildContext context, ForwardMessageFunction forwardMessage,
      {required String sessionName,
      List<String>? filterUser,
      ForwardType type = ForwardType.normal}) {
    String forwardStr;
    if (type == ForwardType.normal) {
      forwardStr = S.of(context).messageForwardMessageTips(sessionName);
    } else if (type == ForwardType.merge) {
      forwardStr = S.of(context).messageForwardMessageMergedTips(sessionName);
    } else {
      forwardStr = S.of(context).messageForwardMessageOneByOneTips(sessionName);
    }
    goToContactSelector(context,
            filter: filterUser, returnContact: true, mostCount: 6)
        .then((selectedUsers) {
      if (selectedUsers is List<ContactInfo>) {
        showChatForwardDialog(
                context: context,
                contentStr: forwardStr,
                contacts: selectedUsers)
            .then((result) async {
          if (result != null && result.result == true) {
            for (int i = 0; i < selectedUsers.length; i++) {
              var user = selectedUsers[i];
              var conversationId = (await NimCore.instance.conversationIdUtil
                      .p2pConversationId(user.user.accountId!))
                  .data;
              forwardMessage(conversationId ?? '',
                  postScript: result.postScript,
                  isLastUser: i == selectedUsers.length - 1);
            }
          }
        });
      }
    });
  }

  static Map<String, dynamic>? getMultiLineMessageMap(
      {String? title, String? content}) {
    if (title?.isNotEmpty == true) {
      return {
        CustomMessageKey.type: CustomMessageType.customMultiLineMessageType,
        CustomMessageKey.data: {
          ChatMessage.keyMultiLineTitle: title,
          ChatMessage.keyMultiLineBody: content
        }
      };
    }
    return null;
  }

  ///解析Text消息，将@消息和普通文本分开
  static List<TextSpan> textSpan(BuildContext context, String text, int start,
      {int? end,
      ChatUIConfig? chatUIConfig,
      Map<String, dynamic>? remoteExtension}) {
    //定义文本字体大小和颜色
    final textSize = chatUIConfig?.messageTextSize ?? 16;
    final textColor =
        chatUIConfig?.messageTextColor ?? CommonColors.color_333333;
    final textAitColor =
        chatUIConfig?.messageLinkColor ?? CommonColors.color_007aff;

    //需要返回的spans
    final List<TextSpan> spans = [];
    //如果有@消息，则需要将@消息的文本和普通文本分开
    if (remoteExtension?[ChatMessage.keyAitMsg] != null) {
      //获取@消息的文本list
      List<AitItemModel> aitSegments = [];
      //将所有@的文本和位置提取出来
      try {
        var aitMap = remoteExtension![ChatMessage.keyAitMsg] as Map;
        final AitContactsModel aitContactsModel =
            AitContactsModel.fromMap(Map<String, dynamic>.from(aitMap));
        aitContactsModel.aitBlocks.forEach((key, value) {
          var aitMsg = value as AitMsg;
          aitMsg.segments.forEach((segment) {
            aitSegments.add(AitItemModel(key, aitMsg.text, segment));
          });
        });
      } catch (e) {
        Alog.e(
            tag: 'ChatKitMessageTextItem',
            content: 'aitContactsModel.fromMap error: $e');
      }
      //如果没有解析到@消息，则直接返回
      if (aitSegments.isEmpty) {
        spans.add(TextSpan(
            text: text,
            style: TextStyle(fontSize: textSize, color: textColor)));
        return spans;
      }

      //根据@消息的位置，将文本分成多个部分
      aitSegments.sort((a, b) => a.segment.start.compareTo(b.segment.start));
      int preIndex = start;
      for (var aitItem in aitSegments) {
        if (preIndex > aitItem.segment.endIndex) {
          continue;
        }
        //@之前的部分
        if (preIndex < text.length && aitItem.segment.start > preIndex) {
          spans.add(TextSpan(
              text: text.substring(
                  preIndex, min(aitItem.segment.start, text.length)),
              style: TextStyle(fontSize: textSize, color: textColor)));
        }
        //@部分
        if (end == null) {
          spans.add(TextSpan(
              text: aitItem.text,
              style: TextStyle(fontSize: textSize, color: textAitColor),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  //点击@消息，如果有自定义回调，则回调，否则跳转到用户详情页
                  if (chatUIConfig?.onTapAitLink != null) {
                    chatUIConfig?.onTapAitLink
                        ?.call(aitItem.account, aitItem.text);
                  } else if (aitItem.account != AitContactsModel.accountAll) {
                    if (IMKitClient.account() != aitItem.account) {
                      goToContactDetail(context, aitItem.account);
                    } else {
                      gotoMineInfoPage(context);
                    }
                  }
                }));
          preIndex = aitItem.segment.endIndex;
        } else if (aitItem.segment.start < end) {
          spans.add(TextSpan(
              text: aitItem.text,
              style: TextStyle(fontSize: textSize, color: textAitColor),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  //点击@消息，如果有自定义回调，则回调，否则跳转到用户详情页
                  if (chatUIConfig?.onTapAitLink != null) {
                    chatUIConfig?.onTapAitLink
                        ?.call(aitItem.account, aitItem.text);
                  } else if (aitItem.account != AitContactsModel.accountAll) {
                    if (IMKitClient.account() != aitItem.account) {
                      goToContactDetail(context, aitItem.account);
                    } else {
                      gotoMineInfoPage(context);
                    }
                  }
                }));
          preIndex = aitItem.segment.endIndex;
        }
      }
      //最后一个@之后的部分
      final lastStartIndex = preIndex - start;
      if (lastStartIndex < text.length - 1) {
        spans.add(TextSpan(
            text: text.substring(lastStartIndex, text.length),
            style: TextStyle(fontSize: textSize, color: textColor)));
      }
    } else {
      //没有@消息，直接返回
      spans.add(TextSpan(
          text: text, style: TextStyle(fontSize: textSize, color: textColor)));
    }
    return spans;
  }

  ///处理文本消息中的表情
  static WidgetSpan? imageSpan(String? tag) {
    var item = EmojiUtil.instance.emojiMap[tag ?? ''];
    if (item == null) return null;
    String source = item.source;
    return WidgetSpan(
      child: Image.asset(
        source,
        package: kPackage,
        height: 24,
        width: 24,
      ),
    );
  }

  //获取消息发送前的参数
  static Future<NIMSendMessageParams> getSenderParams(
      NIMMessage message, String conversationId,
      {NIMMessagePushConfig? pushConfig}) async {
    //push Config
    pushConfig ??= NIMMessagePushConfig();
    if (ChatKitClient.instance.chatUIConfig.getPushPayload != null) {
      final pushPayload = await ChatKitClient
          .instance.chatUIConfig.getPushPayload!(message, conversationId);
      pushConfig.pushPayload = jsonEncode(pushPayload);
    }
    //message config
    final readEnable = await ConfigRepo.getShowReadStatus();

    final messageConfig =
        NIMMessageConfig(readReceiptEnabled: readEnable, unreadEnabled: true);
    NIMSendMessageParams params = NIMSendMessageParams(
      messageConfig: messageConfig,
      pushConfig: pushConfig,
    );
    return params;
  }

  ///根据消息获取内容，作为数字人参数
  static String? getAIContentMsg(NIMMessage? message) {
    if (message == null) {
      return null;
    }

    if (message.messageType == NIMMessageType.text) {
      return message.text;
    }

    if (message.messageType == NIMMessageType.custom) {
      final multiLineMap = MessageHelper.parseMultiLineMessage(message);
      if (multiLineMap != null &&
          multiLineMap[ChatMessage.keyMultiLineTitle] != null) {
        return multiLineMap[ChatMessage.keyMultiLineTitle]! +
            (multiLineMap[ChatMessage.keyMultiLineBody] ?? '');
      }
    }

    return null;
  }

  /// 是否是数字人发送的消息
  static bool isReceivedMessageFromAi(NIMMessage message) {
    final aiConfig = message.aiConfig;
    if (aiConfig != null) {
      return aiConfig.aiStatus == NIMMessageAIStatus.response &&
          aiConfig.accountId?.isNotEmpty == true;
    }
    return false;
  }
}

enum ForwardType {
  normal,
  oneByOne,
  merge,
}
