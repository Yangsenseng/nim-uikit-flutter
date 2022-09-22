// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:chatkit_ui/generated/l10n.dart';
import 'package:chatkit_ui/view/chat_kit_message_list/pop_menu/chat_kit_pop_actions.dart';
import 'package:chatkit_ui/view/chat_kit_message_list/widgets/chat_forward_dialog.dart';
import 'package:collection/collection.dart';
import 'package:im_common_ui/router/imkit_router_factory.dart';
import 'package:im_common_ui/ui/dialog.dart';
import 'package:im_common_ui/utils/color_utils.dart';
import 'package:corekit_im/model/contact_info.dart';
import 'package:corekit_im/services/message/chat_message.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nim_core/nim_core.dart';
import 'package:provider/provider.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:yunxin_alog/yunxin_alog.dart';

import '../../chat_kit_client.dart';
import '../../view_model/chat_view_model.dart';
import 'item/chat_kit_message_item.dart';

class ChatKitMessageList extends StatefulWidget {
  final AutoScrollController scrollController;

  final ChatKitMessageBuilder? messageBuilder;

  final void Function(String? userID, {bool isSelf})? onTapAvatar;

  final PopMenuAction? popMenuAction;

  final NIMTeam? teamInfo;

  final NIMMessage? anchor;

  final ChatUIConfig? chatUIConfig;

  ChatKitMessageList(
      {Key? key,
      required this.scrollController,
      this.anchor,
      this.messageBuilder,
      this.popMenuAction,
      this.onTapAvatar,
      this.teamInfo,
      this.chatUIConfig})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => ChatKitMessageListState();
}

class ChatKitMessageListState extends State<ChatKitMessageList> {
  NIMMessage? findAnchor;

  void _logI(String content) {
    Alog.i(tag: 'ChatKit', moduleName: 'message list', content: content);
  }

  void _onMessageCopy(ChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.nimMessage.content));
    Fluttertoast.showToast(msg: S().chat_message_copy_success);
  }

  _scrollToIndex(String uuid) {
    var index = context
        .read<ChatViewModel>()
        .messageList
        .indexWhere((element) => element.nimMessage.uuid == uuid);
    if (index >= 0) {
      widget.scrollController.scrollToIndex(index);
    }
  }

  _scrollToAnchor(NIMMessage anchor) {
    var list = context.read<ChatViewModel>().messageList;
    if (list.isEmpty) {
      _logI('scrollToAnchor: messageList is empty');
      return;
    }
    final lastTimestamp = context
        .read<ChatViewModel>()
        .getAnchor(QueryDirection.QUERY_OLD)
        .timestamp;
    if (anchor.timestamp >= lastTimestamp) {
      // in range
      findAnchor = null;
      int index = context
          .read<ChatViewModel>()
          .messageList
          .indexWhere((element) => element.nimMessage.uuid == anchor.uuid!);
      _logI(
          'scrollToAnchor: found time:${anchor.timestamp} >= $lastTimestamp, index found:$index');
      if (index >= 0) {
        widget.scrollController
            .scrollToIndex(index, duration: Duration(milliseconds: 1))
            .then((value) {
          widget.scrollController
              .scrollToIndex(index, preferPosition: AutoScrollPosition.middle);
        });
      }
    } else {
      _logI(
          'scrollToAnchor: not found in ${list.length} items, load more -->> ');
      widget.scrollController
          .scrollToIndex(list.length, duration: Duration(milliseconds: 1));
      if (context.read<ChatViewModel>().hasMoreForwardMessages) {
        _loadMore();
      }
    }
  }

  void _onMessageCollect(ChatMessage message) {
    context.read<ChatViewModel>().collectMessage(message.nimMessage);
    Fluttertoast.showToast(msg: S().chat_message_collect_success);
  }

  void _onMessageReply(ChatMessage message) {
    context.read<ChatViewModel>().replyMessage = message;
  }

  void _goContactSelector(ChatMessage message) {
    var filterUser =
        context.read<ChatViewModel>().sessionType == NIMSessionType.p2p
            ? [context.read<ChatViewModel>().sessionId]
            : null;
    var sessionName = context.read<ChatViewModel>().chatTitle;
    String forwardStr = S.of(context).message_forward_message_tips(sessionName);
    goToContactSelector(context, filter: filterUser, returnContact: true)
        .then((selectedUsers) {
      if (selectedUsers is List<ContactInfo>) {
        showChatForwardDialog(
                context: context,
                contentStr: forwardStr,
                contacts: selectedUsers)
            .then((result) {
          if (result == true) {
            for (var user in selectedUsers) {
              context.read<ChatViewModel>().forwardMessage(
                  message.nimMessage, user.user.userId!, NIMSessionType.p2p);
            }
          }
        });
      }
    });
  }

  void _goTeamSelector(ChatMessage message) {
    var sessionName = context.read<ChatViewModel>().chatTitle;
    String forwardStr = S.of(context).message_forward_message_tips(sessionName);
    goTeamListPage(context, selectorModel: true).then((result) {
      if (result is NIMTeam) {
        showChatForwardDialog(
                context: context, contentStr: forwardStr, team: result)
            .then((forward) {
          if (forward == true) {
            context.read<ChatViewModel>().forwardMessage(
                message.nimMessage, result.id!, NIMSessionType.team);
          }
        });
      }
    });
  }

  void _onMessageForward(ChatMessage message) {
    // 转发
    var style = const TextStyle(fontSize: 16, color: CommonColors.color_333333);
    showBottomChoose<int>(context: context, actions: [
      CupertinoActionSheetAction(
        onPressed: () {
          Navigator.pop(context, 2);
        },
        child: Text(
          S.of(context).message_forward_to_team,
          style: style,
        ),
      ),
      CupertinoActionSheetAction(
        onPressed: () {
          Navigator.pop(context, 1);
        },
        child: Text(
          S.of(context).message_forward_to_p2p,
          style: style,
        ),
      )
    ]).then((value) {
      if (value == 1) {
        _goContactSelector(message);
      } else if (value == 2) {
        _goTeamSelector(message);
      }
    });
  }

  void _onMessagePin(ChatMessage message, bool isCancel) {
    if (isCancel) {
      context.read<ChatViewModel>().removeMessagePin(message.nimMessage);
    } else {
      context.read<ChatViewModel>().addMessagePin(message.nimMessage);
    }
  }

  void _onMessageMultiSelect(ChatMessage message) {
    ///todo implement
  }

  void _onMessageDelete(ChatMessage message) {
    showCommonDialog(
            context: context,
            title: S().chat_message_action_delete,
            content: S().chat_message_delete_confirm)
        .then((value) => {
              if (value ?? false)
                context.read<ChatViewModel>().deleteMessage(message)
            });
  }

  void _resendMessage(ChatMessage message) {
    context.read<ChatViewModel>().sendMessage(message.nimMessage,
        replyMsg: message.replyMsg, resend: true);
  }

  void _onMessageRevoke(ChatMessage message) {
    showCommonDialog(
            context: context,
            title: S().chat_message_action_revoke,
            content: S().chat_message_revoke_confirm)
        .then((value) => {
              if (value ?? false)
                context
                    .read<ChatViewModel>()
                    .revokeMessage(message)
                    .then((value) {
                  if (!value.isSuccess) {
                    if (value.code == 508) {
                      Fluttertoast.showToast(
                          msg: S().chat_message_revoke_over_time);
                    } else {
                      Fluttertoast.showToast(
                          msg: S().chat_message_revoke_failed);
                    }
                  }
                })
            });
  }

  _loadMore() async {
    // load old
    if (context.read<ChatViewModel>().messageList.isNotEmpty) {
      Alog.d(
          tag: 'ChatKit',
          moduleName: 'ChatKitMessageList',
          content: '_loadMore -->>');
      context.read<ChatViewModel>().fetchMoreMessage(QueryDirection.QUERY_OLD);
    }
  }

  PopMenuAction getDefaultPopMenuActions(PopMenuAction? customActions) {
    PopMenuAction actions = PopMenuAction();
    if (customActions != null) {
      actions = customActions;
    }
    actions.onMessageCopy ??= _onMessageCopy;
    actions.onMessageReply ??= _onMessageReply;
    actions.onMessageCollect ??= _onMessageCollect;
    actions.onMessageForward ??= _onMessageForward;
    actions.onMessagePin ??= _onMessagePin;
    actions.onMessageMultiSelect ??= _onMessageMultiSelect;
    actions.onMessageDelete ??= _onMessageDelete;
    actions.onMessageRevoke ??= _onMessageRevoke;
    return actions;
  }

  @override
  void initState() {
    super.initState();
    findAnchor = widget.anchor;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (findAnchor != null) {
      _logI('build, try scroll to anchor:${findAnchor?.content}');
      _scrollToAnchor(findAnchor!);
    }

    return Consumer<ChatViewModel>(builder: (cnt, chatViewModel, child) {
      if (chatViewModel.sessionType == NIMSessionType.p2p &&
          chatViewModel.messageList.isNotEmpty) {
        NIMMessage? firstMessage = chatViewModel.messageList
            .firstWhereOrNull((element) =>
                element.nimMessage.messageDirection ==
                NIMMessageDirection.received)
            ?.nimMessage;
        if (firstMessage?.messageAck == true &&
            firstMessage?.hasSendAck == false) {
          chatViewModel.sendMessageP2PReceipt(firstMessage!);
        }
      }

      ///message list
      return Container(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ListView.builder(
                controller: widget.scrollController,
                padding: const EdgeInsets.symmetric(vertical: 10),
                addAutomaticKeepAlives: false,
                shrinkWrap: true,
                reverse: true,
                itemCount: chatViewModel.messageList.length,
                itemBuilder: (context, index) {
                  ChatMessage message = chatViewModel.messageList[index];
                  ChatMessage? lastMessage =
                      index < chatViewModel.messageList.length - 1
                          ? chatViewModel.messageList[index + 1]
                          : null;
                  if (index == chatViewModel.messageList.length - 1 &&
                      chatViewModel.hasMoreForwardMessages) {
                    _loadMore();
                  }
                  return AutoScrollTag(
                    controller: widget.scrollController,
                    index: index,
                    key: ValueKey(message.nimMessage.uuid),
                    highlightColor: Colors.black.withOpacity(0.1),
                    child: ChatKitMessageItem(
                      key: ValueKey(message.nimMessage.uuid),
                      chatMessage: message,
                      messageBuilder: widget.messageBuilder,
                      lastMessage: lastMessage,
                      popMenuAction:
                          getDefaultPopMenuActions(widget.popMenuAction),
                      scrollToIndex: _scrollToIndex,
                      onTapFailedMessage: _resendMessage,
                      onTapAvatar: widget.onTapAvatar,
                      chatUIConfig: widget.chatUIConfig,
                      teamInfo: widget.teamInfo,
                    ),
                  );
                },
              ),
            )
          ],
        ),
      );
    });
    // List messageList = widget.messageList;
  }
}