import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_talk/providers/chat_provider.dart';
import 'package:ai_talk/models/chat_message.dart';

/// Mock HTTP 客户端 — 用于 ChatProvider 测试
class _MockProviderClient extends http.BaseClient {
  bool failConnection = false;
  bool failStream = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // 模型列表请求
    if (request.url.toString().contains('/v1/models')) {
      if (failConnection) {
        return http.StreamedResponse(
          Stream.value(utf8.encode('')),
          500,
        );
      }
      final body = utf8.encode(jsonEncode({
        'object': 'list',
        'data': [
          {'id': 'test-model', 'object': 'model'},
        ],
      }));
      return http.StreamedResponse(Stream.value(body), 200,
          headers: {'content-type': 'application/json'});
    }

    // 聊天请求
    if (request.url.toString().contains('/v1/chat/completions')) {
      if (failStream) {
        final controller = StreamController<List<int>>();
        controller.addError('模拟流式错误');
        return http.StreamedResponse(controller.stream, 200);
      }

      final controller = StreamController<List<int>>();
      final chunks = [
        'data: {"choices":[{"delta":{"content":"这是"}}]}\n',
        'data: {"choices":[{"delta":{"content":"测试"}}]}\n',
        'data: {"choices":[{"delta":{"content":"回复"}}]}\n',
        'data: [DONE]\n',
      ];
      for (final chunk in chunks) {
        controller.add(utf8.encode(chunk));
      }
      controller.close();
      return http.StreamedResponse(controller.stream, 200);
    }

    return http.StreamedResponse(Stream.value(utf8.encode('')), 404);
  }
}

void main() {
  late ChatProvider provider;
  late _MockProviderClient mockClient;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();

    // 模拟平台通道
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;

    // wakelock_plus pigeon 通道 — 返回空 ByteData
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (message) async => ByteData(0),
    );

    // path_provider 通道
    messenger.setMockMethodCallHandler(
      MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => <String, String>{'path': '/tmp'},
    );

    SharedPreferences.setMockInitialValues({});
    provider = ChatProvider();
    mockClient = _MockProviderClient();
  });

  group('ChatProvider 初始化', () {
    test('初始化后消息列表为空', () async {
      await provider.init();
      expect(provider.messages, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.isStreaming, isFalse);
    });

    test('初始化后使用默认配置', () async {
      await provider.init();
      expect(provider.apiHost, isNotEmpty);
      expect(provider.apiPort, isNotEmpty);
      expect(provider.streamEnabled, isTrue);
      expect(provider.searchEnabled, isFalse);
    });
  });

  group('ChatProvider 消息发送', () {
    setUp(() async {
      await provider.init();
      provider.setHttpClient(mockClient);
    });

    test('发送用户消息后消息列表+1', () async {
      await provider.sendMessage('你好');
      expect(provider.messages.length, 2);
      expect(provider.messages[0].role, MessageRole.user);
      expect(provider.messages[0].content, '你好');
      expect(provider.messages[1].role, MessageRole.assistant);
    });

    test('发送空消息不会添加', () async {
      await provider.sendMessage('');
      expect(provider.messages, isEmpty);
      await provider.sendMessage('   ');
      expect(provider.messages, isEmpty);
    });

    test('流式输出后内容完整', () async {
      await provider.sendMessage('测试');
      final lastMsg = provider.messages.last;
      expect(lastMsg.content, '这是测试回复');
      expect(lastMsg.isStreaming, isFalse);
      expect(lastMsg.role, MessageRole.assistant);
      expect(lastMsg.thinkTimeSeconds, greaterThanOrEqualTo(0)); // 测试环境中计时器可能为 0（未tick）
    });

    test('流式错误时返回友好提示', () async {
      mockClient.failStream = true;
      await provider.sendMessage('测试');
      final lastMsg = provider.messages.last;
      expect(lastMsg.content, contains('AI 回复中断'));
      expect(lastMsg.isStreaming, isFalse);
    });
  });

  group('ChatProvider 联网搜索', () {
    setUp(() async {
      await provider.init();
    });

    test('toggleSearch 开关切换正常', () {
      expect(provider.searchEnabled, isFalse);
      provider.toggleSearch();
      expect(provider.searchEnabled, isTrue);
      provider.toggleSearch();
      expect(provider.searchEnabled, isFalse);
    });
  });

  group('ChatProvider 模型管理', () {
    setUp(() async {
      await provider.init();
      provider.setHttpClient(mockClient);
    });

    test('获取模型列表', () async {
      await provider.fetchModels();
      expect(provider.availableModels, isNotEmpty);
      expect(provider.availableModels.first.id, 'test-model');
    });

    test('切换模型', () async {
      final oldModel = provider.selectedModel;
      await provider.selectModel('new-model');
      expect(provider.selectedModel, 'new-model');
      expect(provider.selectedModel, isNot(oldModel));
    });
  });

  group('ChatProvider 清空消息', () {
    setUp(() async {
      await provider.init();
    });

    test('清空后消息列表为空', () async {
      await provider.clearMessages();
      expect(provider.messages, isEmpty);
      expect(provider.isStreaming, isFalse);
    });
  });

  group('ChatProvider 连接检测', () {
    setUp(() async {
      await provider.init();
      provider.setHttpClient(mockClient);
    });

    test('连接成功时更新状态', () async {
      mockClient.failConnection = false;
      provider.setConnected(false);
      await provider.checkConnection();
      expect(provider.isConnected, isTrue);
    });

    test('连接失败时更新状态', () async {
      mockClient.failConnection = true;
      provider.setConnected(true);
      await provider.checkConnection();
      expect(provider.isConnected, isFalse); // 连接失败后为 false
    });
  });

  group('ChatProvider 停止流式', () {
    setUp(() async {
      await provider.init();
      provider.setHttpClient(mockClient);
    });

    test('非流式状态下停止无副作用', () {
      expect(() => provider.stopStreaming(), returnsNormally);
    });
  });

  group('ChatProvider dispose', () {
    test('dispose 不抛异常', () async {
      await provider.init();
      expect(() => provider.dispose(), returnsNormally);
    });
  });
}
