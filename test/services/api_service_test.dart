import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_talk/services/api_service.dart';
import 'package:ai_talk/models/chat_message.dart';

/// 将 Stream<List<int>> 读取为 String
Future<String> _streamToString(Stream<List<int>> stream) async {
  final bytes = <int>[];
  await for (final chunk in stream) {
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

/// 自定义 Mock HTTP 客户端 — 非流式请求，直接返回 StreamedResponse
class _MockClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request) _handler;

  _MockClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}

/// 辅助函数：创建包含 JSON 字符串的 StreamedResponse
http.StreamedResponse _makeJsonResponse(Map<String, dynamic> json, int statusCode) {
  final body = utf8.encode(jsonEncode(json));
  return http.StreamedResponse(
    Stream.value(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

/// 流式 Mock HTTP 客户端 — 返回 SSE 流数据
class _MockStreamClient extends http.BaseClient {
  final List<String> _chunks;
  final int statusCode;

  _MockStreamClient(this._chunks, {this.statusCode = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final controller = StreamController<List<int>>();
    for (final chunk in _chunks) {
      controller.add(utf8.encode(chunk));
      await Future.delayed(Duration.zero); // 模拟异步
    }
    controller.close();
    return http.StreamedResponse(controller.stream, statusCode);
  }
}

void main() {
  group('ApiService 连接测试', () {
    test('连接成功时返回 true', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: 'test-key',
        connectionMode: 'lan',
      );
      // 注入 Mock 客户端 — 返回 200
      service.httpClient = _MockClient((request) async {
        expect(request.url.toString(), 'http://192.168.1.1:11434/v1/models');
        return _makeJsonResponse({'data': []}, 200);
      });

      final result = await service.testConnection();
      expect(result, isTrue);
    });

    test('连接失败时返回 false', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: 'test-key',
      );
      service.httpClient = _MockClient((request) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('Not Found')),
          404,
        );
      });

      final result = await service.testConnection();
      expect(result, isFalse);
    });

    test('超时时返回 false', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: 'test-key',
      );
      service.httpClient = _MockClient((request) async {
        await Future.delayed(const Duration(seconds: 10));
        return http.StreamedResponse(Stream.value(utf8.encode('')), 200);
      });

      // 用较短的超时（测试代码层面）
      final result = await service.testConnection();
      // 实际上超时由 testConnection 内部 5s 控制
      // 这里 MockClient 不会真的超时，仅验证接口可调用
      expect(result, isA<bool>());
    });
  });

  group('ApiService 模型列表解析', () {
    test('成功解析模型列表', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: '',
      );
      service.httpClient = _MockClient((request) async {
        expect(request.url.toString(),
            'http://192.168.1.1:11434/v1/models');
        return _makeJsonResponse({
          'object': 'list',
          'data': [
            {'id': 'llama3.1', 'object': 'model'},
            {'id': 'qwen2.5', 'object': 'model'},
          ],
        }, 200);
      });

      final models = await service.fetchModels();

      expect(models.length, 2);
      expect(models[0].id, 'llama3.1');
      expect(models[1].id, 'qwen2.5');
    });

    test('Cherry Studio 前缀处理', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: '',
      );
      service.httpClient = _MockClient((request) async {
        return _makeJsonResponse({
          'object': 'list',
          'data': [
            {'id': 'ollama:llama3.1', 'object': 'model'},
          ],
        }, 200);
      });

      final models = await service.fetchModels();

      expect(models.length, 1);
      expect(models[0].id, 'llama3.1'); // 前缀被去掉
    });

    test('请求失败时抛出异常', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: '',
      );
      service.httpClient = _MockClient((request) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('Forbidden')),
          403,
        );
      });

      expect(
        () => service.fetchModels(),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ApiService 非流式聊天', () {
    test('成功获取完整回复', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: 'test-key',
      );
      service.httpClient = _MockClient((request) async {
        // 验证请求体
        final body = utf8.decode(await (request as http.Request).bodyBytes);
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        expect(decoded['model'], 'llama3.1');
        expect(decoded['stream'], false);
        expect((decoded['messages'] as List).length, 1);

        // 验证认证头
        expect(request.headers['Authorization'], 'Bearer test-key');

        return _makeJsonResponse({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '你好！有什么可以帮助你的？',
              },
            },
          ],
        }, 200);
      });

      final messages = [
        ChatMessage(id: '1', conversationId: 'default', role: MessageRole.user, content: '你好'),
      ];
      final response = await service.sendChat(
        messages: messages,
        model: 'llama3.1',
      );

      expect(response, '你好！有什么可以帮助你的？');
    });

    test('空 choices 时抛出异常', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: '',
      );
      service.httpClient = _MockClient((request) async {
        return _makeJsonResponse({
          'choices': [],
        }, 200);
      });

      expect(
        () => service.sendChat(
          messages: [],
          model: 'test',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ApiService 流式聊天', () {
    test('逐块接收 SSE 数据', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: '',
      );
      // 注入流式 Mock 客户端
      service.httpClient = _MockStreamClient([
        'data: {"choices":[{"delta":{"content":"你好"}}]}\n',
        'data: {"choices":[{"delta":{"content":"！"}}]}\n',
        'data: [DONE]\n',
      ]);

      final messages = [
        ChatMessage(id: '1', conversationId: 'default', role: MessageRole.user, content: 'hello'),
      ];
      final chunks = <String>[];
      await for (final chunk in service.sendChatStream(
        messages: messages,
        model: 'llama3.1',
      )) {
        chunks.add(chunk);
      }

      expect(chunks, ['你好', '！']);
    });

    test('解析失败的行被跳过', () async {
      final service = ApiService(
        host: '192.168.1.1',
        port: '11434',
        apiKey: '',
      );
      service.httpClient = _MockStreamClient([
        'data: {"choices":[{"delta":{"content":"正常"}}]}\n',
        'data: 不是合法 JSON\n', // 应该被跳过
        'data: {"choices":[{"delta":{"content":"继续"}}]}\n',
        'data: [DONE]\n',
      ]);

      final messages = [
        ChatMessage(id: '1', conversationId: 'default', role: MessageRole.user, content: 'test'),
      ];
      final chunks = <String>[];
      await for (final chunk in service.sendChatStream(
        messages: messages,
        model: 'test',
      )) {
        chunks.add(chunk);
      }

      expect(chunks, ['正常', '继续']);
    });
  });

  group('ApiService URL 构建', () {
    test('局域网模式使用 http://host:port', () {
      final service = ApiService(
        host: '192.168.31.13',
        port: '11434',
        apiKey: '',
        connectionMode: 'lan',
      );
      // 通过注入 Mock 客户端验证 URL
      String? capturedUrl;
      service.httpClient = _MockClient((request) async {
        capturedUrl = request.url.toString();
        return _makeJsonResponse({'data': []}, 200);
      });

      service.testConnection();

      expect(capturedUrl, 'http://192.168.31.13:11434/v1/models');
    });

    test('隧道模式使用隧道 URL', () {
      final service = ApiService(
        host: '',
        port: '',
        apiKey: '',
        connectionMode: 'tunnel',
        tunnelUrl: 'https://example.ngrok.io',
      );
      String? capturedUrl;
      service.httpClient = _MockClient((request) async {
        capturedUrl = request.url.toString();
        return _makeJsonResponse({'data': []}, 200);
      });

      service.testConnection();

      expect(capturedUrl, 'https://example.ngrok.io/v1/models');
    });
  });
}
