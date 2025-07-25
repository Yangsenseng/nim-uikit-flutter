// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'package:netease_corekit/report/xkit_report.dart';
import 'package:nim_chatkit/router/imkit_router.dart';
import 'package:nim_chatkit/router/imkit_router_constants.dart';
import 'package:nim_teamkit_ui/view/pages/team_kit_detail_page.dart';

import 'l10n/S.dart';
import 'view/pages/team_kit_setting_page.dart';

const String kPackage = 'nim_teamkit_ui';

class TeamKitClient {
  /// 群管理员数量限制
  int? teamManagerLimit;

  static get delegate {
    return S.delegate;
  }

  static init() {
    // TeamKitClientRepo.init();
    IMKitRouter.instance.registerRouter(
        RouterConstants.PATH_TEAM_SETTING_PAGE,
        (context) => TeamSettingPage(
            IMKitRouter.getArgumentFormMap<String>(context, 'teamId')!));

    IMKitRouter.instance.registerRouter(
      RouterConstants.PATH_TEAM_DETAIL_PAGE,
      (context) => TeamKitDetailPage(
        teamId: IMKitRouter.getArgumentFormMap<String>(context, 'teamId')!,
      ),
    );

    XKitReporter().register(moduleName: 'TeamUIKit', moduleVersion: '10.3.0');
  }

  TeamKitClient._();

  static TeamKitClient? _instance;

  static TeamKitClient get instance {
    _instance ??= TeamKitClient._();
    return _instance!;
  }
}
