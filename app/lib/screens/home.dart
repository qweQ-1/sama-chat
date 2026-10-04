import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../store.dart';
import 'chats.dart';
import 'contacts.dart';
import 'moments.dart';
import 'profile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = [
    ChatsTab(),
    ContactsTab(),
    MomentsTab(),
    ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final totalUnread = s.conversations.fold<int>(0, (a, c) => a + c.unread);
    final requestCount = s.incomingRequests.length;

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: totalUnread > 0,
              label: Text(totalUnread > 99 ? '99+' : '$totalUnread'),
              child: const Icon(Icons.chat_bubble),
            ),
            label: '消息',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: requestCount > 0,
              label: Text('$requestCount'),
              child: const Icon(Icons.people_outline),
            ),
            selectedIcon: Badge(
              isLabelVisible: requestCount > 0,
              label: Text('$requestCount'),
              child: const Icon(Icons.people),
            ),
            label: '通讯录',
          ),
          const NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public),
            label: '炫圈',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我',
          ),
        ],
      ),
    );
  }
}
