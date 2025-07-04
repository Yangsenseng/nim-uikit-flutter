// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:netease_common_ui/utils/color_utils.dart';
import 'package:netease_common_ui/utils/connectivity_checker.dart';
import 'package:nim_chatkit/im_kit_config_center.dart';
import 'package:nim_chatkit/router/imkit_router_constants.dart';
import 'package:nim_chatkit/router/imkit_router_factory.dart';
import 'package:nim_conversationkit_ui/page/add_friend_page.dart';
import 'package:nim_chatkit/model/contact_info.dart';
import 'package:nim_chatkit/service_locator.dart';
import 'package:nim_chatkit/services/team/team_provider.dart';
import 'package:nim_chatkit/repo/chat_message_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:yunxin_alog/yunxin_alog.dart';

import '../conversation_kit_client.dart';
import '../l10n/S.dart';
import '../page/join_team_page.dart';

const String keyAddFriend = 'add_friend';

const String keyCreateGroupTeam = 'create_group_team';

const String keyCreateAdvancedTeam = 'create_advanced_team';

const String keyJoinTeam = 'join_team';

class ConversationPopMenuButton extends StatelessWidget {
  const ConversationPopMenuButton({Key? key}) : super(key: key);

  _onMenuSelected(BuildContext context, String value) async {
    Alog.i(tag: 'ConversationKit', content: "onMenuSelected: $value");
    switch (value) {
      case keyAddFriend:
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const AddFriendPage()));
        break;
      case keyJoinTeam:
        Navigator.push(context,
            MaterialPageRoute(builder: (context) => const JoinTeamPage()));
        break;
      case keyCreateGroupTeam:
      case keyCreateAdvancedTeam:
        if (!(await haveConnectivity())) {
          return;
        }
        goToContactSelector(context,
                mostCount: TeamProvider.createTeamInviteLimit,
                returnContact: true,
                includeAIUser: true)
            .then((contacts) {
          if (contacts is List<ContactInfo> && contacts.isNotEmpty) {
            Alog.d(
                tag: 'ConversationKit',
                content: '$value, select:${contacts.length}');
            var selectName =
                contacts.map((e) => e.user.name ?? e.user.accountId!).toList();
            getIt<TeamProvider>()
                .createTeam(
              contacts.map((e) => e.user.accountId!).toList(),
              selectNames: selectName,
              isGroup: value == 'create_group_team',
            )
                .then((teamResult) {
              if (teamResult != null && teamResult.team != null) {
                if (value == 'create_advanced_team') {
                  Map<String, String> map = Map();
                  map[RouterConstants.keyTeamCreatedTip] =
                      S.of(context).createAdvancedTeamSuccess;
                  ConversationIdUtil()
                      .teamConversationId(teamResult.team!.teamId)
                      .then((conversationId) {
                    ChatMessageRepo.insertLocalTipsMessageWithExt(
                        conversationId.data!, '', map,
                        time: teamResult.team!.createTime - 100);
                  });
                }
                Future.delayed(Duration(milliseconds: 200), () {
                  goToTeamChat(context, teamResult.team!.teamId);
                });
              }
            });
          }
        });
        break;
    }
  }

  List _conversationMenu(BuildContext context) {
    return [
      {
        'image': 'images/icon_add_friend.svg',
        'name': S.of(context).addFriend,
        'value': keyAddFriend
      },
      if (IMKitConfigCenter.enableTeam) ...[
        {
          'image': 'images/icon_join_team.svg',
          'name': S.of(context).joinTeam,
          'value': keyJoinTeam
        },
        {
          'image': 'images/icon_create_group_team.svg',
          'name': S.of(context).createGroupTeam,
          'value': keyCreateGroupTeam
        },
        {
          'image': 'images/icon_create_advanced_team.svg',
          'name': S.of(context).createAdvancedTeam,
          'value': keyCreateAdvancedTeam
        }
      ]
    ];
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      itemBuilder: (context) {
        return _conversationMenu(context)
            .map<PopupMenuItem<String>>(
              (item) => PopupMenuItem<String>(
                child: Row(
                  children: [
                    SvgPicture.asset(
                      item['image'],
                      package: kPackage,
                      width: 14,
                      height: 14,
                    ),
                    const SizedBox(
                      width: 6,
                    ),
                    Text(
                      item['name'],
                      style: const TextStyle(
                          fontSize: 14, color: CommonColors.color_333333),
                    ),
                  ],
                ),
                value: item['value'],
              ),
            )
            .toList();
      },
      icon: SvgPicture.asset(
        'images/ic_more.svg',
        width: 26,
        height: 26,
        package: kPackage,
      ),
      offset: const Offset(0, 50),
      onSelected: (value) {
        _onMenuSelected(context, value);
      },
    );
  }
}
