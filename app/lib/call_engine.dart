import 'package:flutter_webrtc/flutter_webrtc.dart';

/// WebRTC 通话引擎：只管媒体与连接，不管 UI 与业务状态。
/// 信令（offer/answer/ice 的收发）由 store 驱动；本类提供同步媒体操作。
class CallEngine {
  RTCPeerConnection? _pc;
  MediaStream? _local;
  bool _disposed = false;

  /// answer/offer 尚未应用时先缓存对端候选（竞态兜底），应用后统一补交。
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescSet = false;

  /// 本地产生 ICE candidate（store 转发给对方）。
  final void Function(Map<String, dynamic> candidate) onCandidate;

  /// 连接状态变化：connected / failed / disconnected / closed。
  final void Function(String state) onConnectionState;

  CallEngine({
    required this.onCandidate,
    required this.onConnectionState,
  });

  bool get disposed => _disposed;

  Future<void> createPeer(List<Map<String, dynamic>> iceServers) async {
    _pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    });
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null && !_disposed) onCandidate(c.toMap());
    };
    _pc!.onConnectionState = (s) {
      if (!_disposed) onConnectionState(s.toString().split('.').last);
    };
  }

  /// 打开麦克风并挂到 PeerConnection 上。
  /// Android 需先由调用方申请运行时权限；iOS 由系统在 getUserMedia 时弹窗。
  Future<void> openMicrophone() async {
    if (_disposed) return;
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
    for (final t in _local!.getTracks()) {
      _pc?.addTrack(t, _local!);
    }
  }

  /// 呼出：生成 offer（先 openMicrophone 再调这个）。
  Future<Map<String, dynamic>> makeOffer() async {
    final desc = await _pc!.createOffer({
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    });
    await _pc!.setLocalDescription(desc);
    return desc.toMap();
  }

  /// 接听：应用对方的 offer → 打开麦克风 → 生成 answer。
  Future<Map<String, dynamic>> answerRemote(Map<String, dynamic> offer) async {
    await _pc!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String?, offer['type'] as String?),
    );
    _remoteDescSet = true;
    await _flushPendingCandidates();
    await openMicrophone();
    final desc = await _pc!.createAnswer({
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    });
    await _pc!.setLocalDescription(desc);
    return desc.toMap();
  }

  /// 呼出方应用对方的 answer。
  Future<void> applyRemoteAnswer(Map<String, dynamic> answer) async {
    if (_disposed) return;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(answer['sdp'] as String?, answer['type'] as String?),
    );
    _remoteDescSet = true;
    await _flushPendingCandidates();
  }

  Future<void> _flushPendingCandidates() async {
    final pending = List<RTCIceCandidate>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final c in pending) {
      try {
        await _pc?.addIceCandidate(c);
      } catch (_) {}
    }
  }

  /// 应用对方的 ICE candidate；answer/offer 未到时先缓存（防丢候选连不上）。
  Future<void> addRemoteCandidate(Map<String, dynamic> candidate) async {
    if (_disposed) return;
    final c = RTCIceCandidate(
      candidate['candidate'] as String?,
      candidate['sdpMid'] as String?,
      candidate['sdpMLineIndex'] as int?,
    );
    if (!_remoteDescSet) {
      _pendingCandidates.add(c);
      return;
    }
    try {
      await _pc!.addIceCandidate(c);
    } catch (_) {}
  }

  /// 静音/取消静音麦克风。
  void setMuted(bool muted) {
    for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  /// 释放全部资源（挂断/出错时调用）。
  void dispose() {
    _disposed = true;
    try {
      _local?.dispose();
    } catch (_) {}
    try {
      _pc?.dispose();
    } catch (_) {}
    _local = null;
    _pc = null;
  }
}
