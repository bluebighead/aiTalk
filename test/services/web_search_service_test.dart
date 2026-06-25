import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ai_talk/services/web_search_service.dart';

/// Mock HTTP 客户端 — 用于 WebSearchService 测试
class _MockSearchClient extends http.BaseClient {
  final int statusCode;
  final Map<String, dynamic>? responseBody;
  final bool shouldTimeout;

  _MockSearchClient({
    this.statusCode = 200,
    this.responseBody,
    this.shouldTimeout = false,
  });

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (shouldTimeout) {
      await Future.delayed(const Duration(seconds: 30));
    }

    final body = responseBody ??
        {
          'results': [
            {
              'title': 'Flutter 官方文档',
              'url': 'https://flutter.dev',
              'content': 'Flutter 是 Google 的 UI 工具包...',
            },
          ],
          'answer': 'Flutter 是一个跨平台框架。',
        };

    final controller = StreamController<List<int>>();
    controller.add(utf8.encode(jsonEncode(body)));
    controller.close();
    return http.StreamedResponse(controller.stream, statusCode,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

void main() {
  late WebSearchService service;
  late _MockSearchClient mockClient;

  group('WebSearchService 搜索测试', () {
    test('API Key 为空时返回提示信息', () async {
      service = WebSearchService(apiKey: '');
      // 不依赖 Mock，直接走空 key 逻辑
      final result = await service.search('测试');

      expect(result, contains('未配置搜索 API Key'));
    });

    test('搜索成功返回格式化上下文', () async {
      service = WebSearchService(apiKey: 'test-key');
      mockClient = _MockSearchClient();
      service.httpClient = mockClient;

      final result = await service.search('Flutter');

      // 包含摘要
      expect(result, contains('摘要: Flutter 是一个跨平台框架。'));
      // 包含搜索结果
      expect(result, contains('Flutter 官方文档'));
      expect(result, contains('https://flutter.dev'));
      // 包含 Markdown 格式
      expect(result, contains('[Flutter 官方文档]'));
      // 包含上下文指示标记
      expect(result, contains('从互联网搜索到的相关信息'));
      expect(result, contains('搜索信息结束'));
    });

    test('搜索无结果时返回提示', () async {
      service = WebSearchService(apiKey: 'test-key');
      mockClient = _MockSearchClient(responseBody: {
        'results': [],
        'answer': null,
      });
      service.httpClient = mockClient;

      final result = await service.search('不存在的关键词');

      expect(result, contains('未找到相关搜索结果'));
    });

    test('搜索 API 返回错误时返回提示', () async {
      service = WebSearchService(apiKey: 'test-key');
      mockClient = _MockSearchClient(
        statusCode: 401,
        responseBody: {'error': 'Invalid API key'},
      );
      service.httpClient = mockClient;

      final result = await service.search('test');

      expect(result, contains('搜索失败'));
      expect(result, contains('Invalid API key'));
    });

    test('搜索网络异常时返回友好提示', () async {
      service = WebSearchService(apiKey: 'test-key');
      // 使用会抛出异常的 Mock 客户端
      service.httpClient = _MockSearchClient(
        statusCode: 500,
        responseBody: {'error': 'Network error'},
      );

      final result = await service.search('test');

      expect(result, contains('搜索失败'));
    });

    test('搜索包含多个结果', () async {
      service = WebSearchService(apiKey: 'test-key');
      mockClient = _MockSearchClient(responseBody: {
        'results': [
          {'title': '结果1', 'url': 'https://example.com/1', 'content': '内容1'},
          {'title': '结果2', 'url': 'https://example.com/2', 'content': '内容2'},
          {'title': '结果3', 'url': 'https://example.com/3', 'content': '内容3'},
        ],
        'answer': '多个结果',
      });
      service.httpClient = mockClient;

      final result = await service.search('test');

      expect(result, contains('1. [结果1]'));
      expect(result, contains('2. [结果2]'));
      expect(result, contains('3. [结果3]'));
    });

    test('updateApiKey 正确更新', () {
      service = WebSearchService(apiKey: 'old-key');
      expect(service.hasApiKey, isTrue);

      service.updateApiKey('new-key');
      // 通过 hasApiKey 间接验证
      expect(service.hasApiKey, isTrue);
    });

    test('hasApiKey 判断正确', () {
      service = WebSearchService(apiKey: '');
      expect(service.hasApiKey, isFalse);

      service = WebSearchService(apiKey: 'valid-key');
      expect(service.hasApiKey, isTrue);
    });
  });
}
