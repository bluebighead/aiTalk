import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/chat_provider.dart';
import 'services/timer_service.dart';

/// 应用入口
/// 初始化 ChatProvider 并从本地存储加载配置后启动 App
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 ChatProvider（从本地存储加载 API 配置）
  final chatProvider = ChatProvider();
  await chatProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatProvider>.value(value: chatProvider),
        ChangeNotifierProvider<ElapsedTimerService>.value(
          value: chatProvider.elapsedTimerService,
        ),
      ],
      child: const AiTalkApp(),
    ),
  );
}
