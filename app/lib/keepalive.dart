/// 后台保活：
/// - Android：前台服务（常驻低优先级通知），进程不被系统回收，WebSocket 保持在线
/// - iOS：循环播放静音音频，App 退到后台后不被挂起（局限：从后台划掉 App 后无效）
library;

import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:just_audio/just_audio.dart';

/// Android 前台服务入口（仅用于保活，无额外逻辑）。
@pragma('vm:entry-point')
void samaKeepAliveEntry() {
  FlutterForegroundTask.setTaskHandler(_NoopTaskHandler());
}

class _NoopTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}
}

class KeepAlive {
  static final AudioPlayer _player = AudioPlayer();
  static bool _audioPlaying = false;

  static Future<void> start() async {
    if (Platform.isAndroid) {
      await _startAndroid();
    } else if (Platform.isIOS) {
      await _startIos();
    }
  }

  static Future<void> stop() async {
    if (Platform.isAndroid) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
    } else if (Platform.isIOS) {
      try {
        await _player.stop();
        _audioPlaying = false;
      } catch (_) {}
    }
  }

  static Future<void> _startAndroid() async {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'sama_keepalive',
          channelName: '消息服务',
          channelDescription: '保持消息实时接收',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions:
            const IOSNotificationOptions(showNotification: false),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
        ),
      );
      await FlutterForegroundTask.startService(
        notificationTitle: '萨摩聊天运行中',
        notificationText: '保持消息实时接收',
        callback: samaKeepAliveEntry,
      );
    } catch (_) {}
  }

  static Future<void> _startIos() async {
    if (_audioPlaying) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      await _player.setAsset('assets/silence.wav');
      await _player.setLoopMode(LoopMode.one);
      await _player.play();
      _audioPlaying = true;
    } catch (_) {}
  }
}
