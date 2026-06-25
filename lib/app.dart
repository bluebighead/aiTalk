import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/chat_provider.dart';
import 'pages/chat_page.dart';

/// App 根组件 - 应用入口 Widget
class AiTalkApp extends StatelessWidget {
  const AiTalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        return MaterialApp(
          title: 'AI Talk',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.blue,
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 0,
            ),
          ),
          home: const ChatPage(),
        );
      },
    );
  }
}
