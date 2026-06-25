import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/chat_message.dart';
import '../models/model_info.dart';

/// API 通信服务 - 负责与 OpenAI 兼容 API（Cherry Studio / Ollama）通信
/// 支持流式 SSE 和非流式两种聊天方式
class ApiService {
  String _host;
  String _port;
  String _apiKey;
  String _connectionMode; // 'lan' 或 'tunnel'
  String _tunnelUrl;

  /// 可注入的 HTTP 客户端（用于测试时 Mock）
  http.Client httpClient = http.Client();

  ApiService({
    required String host,
    required String port,
    required String apiKey,
    String connectionMode = 'lan',
    String tunnelUrl = '',
  })  : _host = host,
        _port = port,
        _apiKey = apiKey,
        _connectionMode = connectionMode,
        _tunnelUrl = tunnelUrl;

  // ----- 配置更新方法 -----
  void updateConfig({
    required String host,
    required String port,
    required String apiKey,
    required String connectionMode,
    required String tunnelUrl,
  }) {
    _host = host;
    _port = port;
    _apiKey = apiKey;
    _connectionMode = connectionMode;
    _tunnelUrl = tunnelUrl;
  }

  /// 获取 API 基础 URL
  /// 内网穿透模式使用隧道地址，否则使用局域网 IP:端口
  String get _baseUrl {
    final url = _connectionMode == 'tunnel' && _tunnelUrl.isNotEmpty
        ? _tunnelUrl
        : 'http://$_host:$_port';
    debugPrint('[API] 基础URL: $url (模式: $_connectionMode)');
    return url;
  }

  /// 构建完整的 API URL
  String _buildUrl(String path) => '$_baseUrl$path';

  // ----- 连接测试 -----
  /// 测试 API 连接是否正常，超时 5 秒
  Future<bool> testConnection() async {
    final url = _buildUrl('/v1/models');
    debugPrint('[API] 测试连接: $url');
    try {
      final response = await httpClient
        .get(
          Uri.parse(url),
          headers: _buildHeaders(),
        )
        .timeout(const Duration(seconds: 5));
      debugPrint('[API] 连接测试结果: status=${response.statusCode} body=${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[API] 连接测试失败: $e');
      return false;
    }
  }

  // ----- 获取模型列表 -----
  /// 从 API 获取可用的模型列表（兼容 Cherry Studio 和 Ollama）
  Future<List<ModelInfo>> fetchModels() async {
    final url = _buildUrl('/v1/models');
    debugPrint('[API] 获取模型列表: $url');
    final response = await httpClient
        .get(
          Uri.parse(url),
          headers: _buildHeaders(),
        )
        .timeout(const Duration(seconds: 10)); // 10秒超时

    debugPrint('[API] 模型列表响应: status=${response.statusCode}');
    if (response.statusCode != 200) {
      throw Exception('获取模型列表失败: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>;
    debugPrint('[API] 模型原始数据: $data');
    final models = data.map((item) {
      final modelId = (item['id'] as String);
      // Cherry Studio 返回的模型 ID 带 "ollama:" 前缀，需要去掉
      final cleanId = modelId.startsWith('ollama:') ? modelId.substring(7) : modelId;
      debugPrint('[API] 模型ID处理: $modelId -> $cleanId');
      return ModelInfo(id: cleanId, name: cleanId);
    }).toList();
    debugPrint('[API] 解析后模型列表: ${models.map((m) => m.id).toList()}');
    return models;
  }

  // ----- 发送聊天消息（流式）-----
  /// 发送消息并返回流式响应（SSE - Server-Sent Events）
  /// 逐字返回 AI 回复内容，实现打字机效果
  /// [onFirstToken] 可选回调，在收到第一个有效 token 时触发
  Stream<String> sendChatStream({
    required List<ChatMessage> messages,
    required String model,
    void Function()? onFirstToken,
  }) async* {
    final apiMessages = messages.map((m) => {
      'role': m.role.name,
      'content': m.content,
    }).toList();

    // 构建请求体，stream: true 表示启用流式输出
    final body = jsonEncode({
      'model': model,
      'messages': apiMessages,
      'stream': true,
    });

    try {
      final request = http.Request('POST', Uri.parse(_buildUrl('/v1/chat/completions')));
      request.headers.addAll(_buildHeaders());
      request.headers['Content-Type'] = 'application/json';
      request.body = body;

      // 使用异步超时处理，避免流式请求被直接切断
      final response = await httpClient
          .send(request)
          .timeout(const Duration(seconds: 60)); // 流式请求60秒总超时

      // 逐行解析 SSE 数据流
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        final lines = chunk.split('\n');
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') return;

            try {
              final jsonData = jsonDecode(data) as Map<String, dynamic>;
              final choices = jsonData['choices'] as List<dynamic>;
              if (choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>;
                final content = delta['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  // 收到第一个有效 token 时触发回调，且仅触发一次
                  onFirstToken?.call();
                  onFirstToken = null;
                  yield content;
                }
              }
            } catch (e) {
              // 跳过解析失败的片段
              continue;
            }
          }
        }
      }
    } catch (e) {
      throw Exception('请求失败: $e');
    }
  }

  // ----- 发送聊天消息（非流式）-----
  /// 发送消息并获取完整响应
  Future<String> sendChat({
    required List<ChatMessage> messages,
    required String model,
  }) async {
    final apiMessages = messages.map((m) => {
      'role': m.role.name,
      'content': m.content,
    }).toList();

    final body = jsonEncode({
      'model': model,
      'messages': apiMessages,
      'stream': false,
    });

    try {
      final response = await httpClient
          .post(
            Uri.parse(_buildUrl('/v1/chat/completions')),
            headers: {
              ..._buildHeaders(),
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30)); // 非流式请求30秒超时

      if (response.statusCode != 200) {
        throw Exception('请求失败: ${response.statusCode} ${response.body}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>;
      if (choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>;
        return message['content'] as String;
      }
      throw Exception('响应中没有消息内容');
    } catch (e) {
      throw Exception('请求失败: $e');
    }
  }

  /// 构建通用请求头（Bearer Token 认证）
  Map<String, String> _buildHeaders() {
    return {
      'Authorization': 'Bearer $_apiKey',
    };
  }

  // ----- 翻译 -----
  /// 使用 AI 模型进行翻译（非流式，复用聊天接口）
  /// 通过系统指令让模型只返回翻译结果，不附带额外说明
  Future<String> translate(String text, String model) async {
    debugPrint('[Translate] 请求翻译: model=$model, text长度=${text.length}');

    // 使用 few-shot 示例强制模型只输出纯译文，对 abliterated 等不守指令的模型尤其重要
    final messages = [
      {
        'role': 'system',
        'content': '你是一个严格的翻译引擎，只能输出翻译结果，禁止输出其他任何内容。\n'
            '规则：\n'
            '1. 无论用户输入什么语言，一律翻译为简体中文\n'
            '2. 禁止加任何前缀/后缀/解释/引号/标点修饰\n'
            '3. 禁止以"I have translated"、"Here is"、"译文："等开头\n'
            '4. 如果输入中包含代码或专有名词，保留原文不翻译\n'
            '5. 只输出一行纯译文\n\n'
            '示例：\n'
            '用户：今天天气真好\n'
            '助手：今天天气真好\n'
            '用户：I love programming\n'
            '助手：我喜欢编程',
      },
      {'role': 'user', 'content': text},
    ];

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'stream': false,
    });

    debugPrint('[Translate] 请求体: model=$model, messages_count=${messages.length}');

    try {
      final response = await httpClient
          .post(
            Uri.parse(_buildUrl('/v1/chat/completions')),
            headers: {
              ..._buildHeaders(),
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 30)); // 延长超时到30秒

      debugPrint('[Translate] 响应状态: ${response.statusCode}');

      if (response.statusCode != 200) {
        final errorBody = response.body.length > 200
            ? '${response.body.substring(0, 200)}...'
            : response.body;
        debugPrint('[Translate] 请求失败: status=${response.statusCode}, body=$errorBody');
        throw Exception('翻译请求失败: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>;
      if (choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>;
        final result = message['content'] as String;
        debugPrint('[Translate] 翻译结果: "${result.substring(0, result.length > 100 ? 100 : result.length)}${result.length > 100 ? '...' : ''}"');
        return result.trim();
      }
      debugPrint('[Translate] 响应中没有消息内容');
      throw Exception('翻译响应中没有消息内容');
    } catch (e) {
      debugPrint('[Translate] 翻译异常: $e');
      throw Exception('翻译失败: $e');
    }
  }
}
