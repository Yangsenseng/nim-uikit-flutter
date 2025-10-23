// Copyright (c) 2022 NetEase, Inc. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:netease_callkit/netease_callkit.dart';
import 'package:netease_common_ui/extension.dart';
import 'package:nim_chatkit_ui/media/media_bottom_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:nim_core_v2/nim_core.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';

import '../chat_kit_client.dart';

class VideoViewer extends StatefulWidget {
  const VideoViewer({Key? key, required this.message}) : super(key: key);

  final NIMMessage message;

  @override
  State<StatefulWidget> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _progressShow = true;
  Timer? _timer;
  bool _isPlaying = true;
  StreamSubscription? _phoneStateSub;

  late NIMMessageVideoAttachment attachment;

  void _playProgressAutoHide() {
    _timer?.cancel();
    if (_progressShow) {
      _timer = Timer(const Duration(seconds: 3), () {
        if (_progressShow) {
          setState(() {
            _progressShow = false;
          });
        }
      });
    }
  }

  late NECallEngineDelegate _callDelegate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    attachment = widget.message.attachment as NIMMessageVideoAttachment;
    if (Platform.isAndroid) {
      _controller = VideoPlayerController.file(File(attachment.path!),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
          viewType: VideoViewType.platformView);
    } else {
      _controller = VideoPlayerController.file(File(attachment.path!),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false));
    }

    _controller.addListener(() {
      if (!_controller.value.isPlaying &&
          _controller.value.position == _controller.value.duration) {
        _controller.seekTo(Duration());
        _isPlaying = false;
      }
      setState(() {});
    });
    _controller.setLooping(false);
    _controller.initialize().then((_) {
      setState(() {});
    });
    _isPlaying = true;
    _controller.play();
    _playProgressAutoHide();
    _callDelegate = NECallEngineDelegate(onReceiveInvited: (info) {
      if (_isPlaying) {
        _isPlaying = false;
        _controller.pause();
        setState(() {});
      }
    });
    NECallEngine.instance.addCallDelegate(_callDelegate);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 添加 inactive 状态判断避免来电等状态
    if ((AppLifecycleState.paused == state ||
            AppLifecycleState.inactive == state) &&
        _isPlaying) {
      _isPlaying = false;
      _controller.pause();
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _timer?.cancel();
    _phoneStateSub?.cancel();
    _phoneStateSub = null;
    NECallEngine.instance.removeCallDelegate(_callDelegate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(alignment: Alignment.bottomCenter, children: [
        Center(
          child: Hero(
            tag:
                '${widget.message.messageServerId}${widget.message.messageClientId}',
            child: _controller.value.isInitialized
                ? GestureDetector(
                    onTap: () {
                      setState(() {
                        _progressShow = !_progressShow;
                        _playProgressAutoHide();
                      });
                    },
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  )
                : Container(),
          ),
        ),
        Visibility(
          visible: !_isPlaying,
          child: GestureDetector(
            onTap: () {
              _isPlaying = true;
              _controller.play();
            },
            child: Center(
              child: SvgPicture.asset(
                'images/ic_video_player.svg',
                package: kPackage,
                height: 80,
                width: 80,
              ),
            ),
          ),
        ),
        Positioned(
            left: 20,
            right: 20,
            bottom: 75,
            child: Visibility(
              visible: _progressShow,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_isPlaying) {
                        _isPlaying = false;
                        _controller.pause();
                      } else {
                        _isPlaying = true;
                        _controller.play();
                      }
                    },
                    child: SvgPicture.asset(
                      _isPlaying
                          ? 'images/ic_video_pause.svg'
                          : 'images/ic_video_resume.svg',
                      package: kPackage,
                      height: 26,
                      width: 26,
                    ),
                  ),
                  const SizedBox(
                    width: 20,
                  ),
                  Text(
                    _controller.value.position.inSeconds.formatTimeMMSS(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 2,
                      child: VideoProgressIndicator(_controller,
                          colors: const VideoProgressColors(
                              playedColor: Colors.white,
                              backgroundColor: Color(0x4d000000)),
                          padding: EdgeInsets.zero,
                          allowScrubbing: false),
                    ),
                  ),
                  const SizedBox(
                    width: 10,
                  ),
                  Text(
                    _controller.value.duration.inSeconds.formatTimeMMSS(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            )),
        MediaBottomActionOverlay(widget.message)
      ]),
    );
  }
}
