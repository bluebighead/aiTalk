import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 联网搜索服务 - 使用 Tavily Search API
/// 将搜索结果作为上下文提供给 AI 模型
///
/// 用户需注册 https://app.tavily.com 获取 API Key
class WebSearchService {
  String _apiKey;

  /// 可注入的 HTTP 客户端（用于测试时 Mock）
  http.Client httpClient = http.Client();

  WebSearchService({String apiKey = ''}) : _apiKey = apiKey;

  /// 更新 API Key
  void updateApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  /// 是否已配置 API Key
  bool get hasApiKey => _apiKey.isNotEmpty;

  /// 执行搜索并返回格式化的上下文文本
  /// [query] 搜索关键词
  /// 返回包含搜索结果的 Markdown 格式文本，可直接注入到 AI 对话上下文中
  Future<String> search(String query) async {
    if (_apiKey.isEmpty) {
      return '⚠️ 未配置搜索 API Key，请在设置中添加 Tavily API Key。';
    }

    debugPrint('[WebSearch] 开始搜索: $query');
    try {
      final response = await httpClient
          .post(
            Uri.parse('https://api.tavily.com/search'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'api_key': _apiKey,
              'query': query,
              'search_depth': 'basic',
              'include_answer': true,
              'max_results': 5,
            }),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[WebSearch] 响应状态: ${response.statusCode}');

      if (response.statusCode != 200) {
        // 尝试解析 JSON 格式的错误响应；若代理返回 HTML 等非 JSON 内容则使用状态码
        String errorMsg;
        try {
          final errorBody = jsonDecode(response.body);
          errorMsg = errorBody['error'] ?? 'HTTP ${response.statusCode}';
        } catch (_) {
          errorMsg = 'HTTP ${response.statusCode}';
        }
        debugPrint('[WebSearch] 搜索失败: $errorMsg');
        return '⚠️ 搜索失败: $errorMsg';
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      // 检查 API 是否返回了错误信息
      if (json.containsKey('error')) {
        final errorMsg = json['error'].toString();
        debugPrint('[WebSearch] API 返回错误: $errorMsg');
        return '⚠️ 搜索失败: $errorMsg';
      }

      final resultsRaw = json['results'];
      if (resultsRaw is! List || resultsRaw.isEmpty) {
        debugPrint('[WebSearch] 搜索结果为空或格式异常');
        return '⚠️ 未找到相关搜索结果。';
      }
      final results = resultsRaw;

      final answer = json['answer'] as String?;

      // 格式化为 Markdown 上下文
      final buffer = StringBuffer();
      buffer.writeln('--- 以下是从互联网搜索到的相关信息 ---');
      buffer.writeln('用户搜索: $query');
      buffer.writeln('');

      if (answer != null && answer.isNotEmpty) {
        buffer.writeln('摘要: $answer');
        buffer.writeln('');
      }

      buffer.writeln('搜索结果:');
      for (int i = 0; i < results.length; i++) {
        final item = results[i] as Map<String, dynamic>;
        buffer.writeln('${i + 1}. [${item['title']}](${item['url']})');
        buffer.writeln('   ${item['content']}');
        buffer.writeln('');
      }
      buffer.writeln('--- 搜索信息结束，请基于以上信息回答用户问题 ---');

      final result = buffer.toString();
      debugPrint('[WebSearch] 搜索结果长度: ${result.length} 字符');
      return result;
    } catch (e) {
      debugPrint('[WebSearch] 搜索异常: $e');
      return '⚠️ 搜索请求失败: $e';
    }
  }
}
