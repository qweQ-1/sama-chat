import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:samachat/main.dart';
import 'package:samachat/store.dart';
import 'package:samachat/widgets.dart';

void main() {
  testWidgets('shows login screen when there is no session', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SamaChatApp());

    // let boot() finish
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('登 录'), findsOneWidget);
    expect(find.text('没有账号？立即注册'), findsOneWidget);
    expect(find.text('萨摩聊天'), findsOneWidget);
  });

  testWidgets('login screen can switch to register mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SamaChatApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('没有账号？立即注册'));
    await tester.pumpAndSettle();

    expect(find.text('注 册'), findsOneWidget);
    expect(find.text('昵称（可留空）'), findsOneWidget);
  });

  testWidgets('avatar falls back to initial letter', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState()..boot(),
        child: const MaterialApp(
          home: Scaffold(body: Center(child: Avatar(name: '萨摩', size: 60))),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('萨'), findsOneWidget);
  });
}
