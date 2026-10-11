import 'package:flutter_test/flutter_test.dart';

import 'package:samachat/models.dart';

void main() {
  group('通话状态模型（CallInfo）', () {
    test('默认呼出状态', () {
      final c = CallInfo(callId: 'call1', peerId: 'u1', peerName: '小狗');
      expect(c.status, 'outgoing');
      expect(c.video, false);
      expect(c.muted, false);
      expect(c.startedAt, null);
    });

    test('来电携带 offer 暂存', () {
      final offer = {'type': 'offer', 'sdp': 'v=0\r\nxxx'};
      final c = CallInfo(
        callId: 'call2',
        peerId: 'u2',
        peerName: '小猫',
        status: 'incoming',
        pendingOffer: offer,
      );
      expect(c.status, 'incoming');
      expect(c.pendingOffer?['sdp'], 'v=0\r\nxxx');
    });

    test('静音与接通时间可变', () {
      final c = CallInfo(callId: 'c', peerId: 'u', peerName: 'n');
      c.muted = true;
      c.status = 'connected';
      c.startedAt = 1700000000000;
      expect(c.muted, true);
      expect(c.startedAt, 1700000000000);
    });
  });

  group('通话计时文案（formatCallDuration）', () {
    test('59 秒以内', () {
      expect(formatCallDuration(0), '00:00');
      expect(formatCallDuration(59000), '00:59');
    });

    test('分钟级', () {
      expect(formatCallDuration(61000), '01:01');
      expect(formatCallDuration(600000), '10:00');
      expect(formatCallDuration(3599000), '59:59');
    });

    test('小时级', () {
      expect(formatCallDuration(3600000), '1:00:00');
      expect(formatCallDuration(3723000), '1:02:03');
    });
  });
}
