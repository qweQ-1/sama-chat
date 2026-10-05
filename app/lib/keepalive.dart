/// 后台保活：
/// - Android：前台服务（常驻低优先级通知），进程不被系统回收，WebSocket 保持在线
/// - iOS：循环播放静音音频，App 退到后台后不被挂起（局限：从后台划掉 App 后无效）
library;

import 'dart:async';
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

class KeepAliveService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _audioStarted = false;
  static bool _interruptionHooked = false;
  static Timer? _watchdog;

  static Future<void> start() async {
    if (Platform.isAndroid) {
      await _startAndroid();
    } else if (Platform.isIOS) {
      await _startIos();
    }
  }

  static Future<void> stop() async {
    _watchdog?.cancel();
    _watchdog = null;
    if (Platform.isAndroid) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (_) {}
    } else if (Platform.isIOS) {
      try {
        await _player.stop();
      } catch (_) {}
      _audioStarted = false;
    }
  }

  /// 诊断信息（显示在「诊断」页）。
  static String get debugStatus {
    if (Platform.isIOS) {
      return _player.playing ? 'iOS 音频保活: 播放中 ✓' : 'iOS 音频保活: 未播放 ✗';
    } else if (Platform.isAndroid) {
      return 'Android 前台服务保活模式';
    }
    return '未知平台';
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
    try {
      final session = await AudioSession.instance;
      // 后台可播放的音频会话（首选混音，避免打断用户自己的音乐）
      try {
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
      } catch (_) {
        try {
          await session.configure(const AudioSessionConfiguration.music());
        } catch (_) {}
      }
      try {
        await session.setActive(true);
      } catch (_) {}

      if (!_audioStarted) {
        await _player.setAsset('assets/silence.wav');
        await _player.setLoopMode(LoopMode.one);
        _audioStarted = true;
      }
      // 注意：play() 返回的 Future 会等播放结束才完成（循环音频永不结束），不能 await
      unawaited(_player.play().catchError((Object _) {}));
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!_player.playing) {
        // 会话激活失败时重试一次
        try {
          await session.setActive(true);
        } catch (_) {}
        unawaited(_player.play().catchError((Object _) {}));
      }

      _hookInterruptions(session);

      // 看门狗：每 45 秒检查一次，被系统暂停就自动恢复
      _watchdog ??= Timer.periodic(const Duration(seconds: 45), (_) {
        if (Platform.isIOS && !_player.playing) {
          unawaited(_startIos());
        }
      });
    } catch (_) {}
  }

  static void _hookInterruptions(AudioSession session) {
    if (_interruptionHooked) return;
    _interruptionHooked = true;
    try {
      session.interruptionEventStream.listen((event) {
        if (!event.begin) {
          // 中断结束（如电话挂断）后恢复播放
          unawaited(_startIos());
        }
      });
    } catch (_) {}
  }
}
