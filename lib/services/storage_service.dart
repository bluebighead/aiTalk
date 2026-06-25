import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chat_message.dart';

/// 本地存储服务 - 负责聊天消息的持久化读写
/// 使用 JSON 文件存储多会话数据，保存在应用文档目录下
class StorageService {
  static const String _fileName = 'chat_messages.json';
  static const int _maxMessages = 200; // 每个会话最多保留 200 条消息

  /// 获取存储文件的路径
  Future<String> get _filePath async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$_fileName';
  }

  /// 保存多会话数据到本地文件
  /// [conversations] 会话ID -> 消息列表 的映射
  /// [conversationOrder] 会话ID的有序列表
  Future<void> saveConversations(
    Map<String, List<ChatMessage>> conversations,
    List<String> conversationOrder,
  ) async {
    try {
      final path = await _filePath;
      final data = <String, dynamic>{
        'conversationOrder': conversationOrder,
        'conversations': <String, dynamic>{},
      };

      final convMap = data['conversations'] as Map<String, dynamic>;
      for (final entry in conversations.entries) {
        // 每个会话只保留最近的 N 条消息
        final trimmed = entry.value.length > _maxMessages
            ? entry.value.sublist(entry.value.length - _maxMessages)
            : entry.value;
        convMap[entry.key] = trimmed.map((m) => m.toJson()).toList();
      }

      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      await File(path).writeAsString(jsonStr);
      debugPrint('[Storage] 已保存 ${conversations.length} 个会话');
    } catch (e) {
      debugPrint('[Storage] 保存会话失败: $e');
    }
  }

  /// 从本地文件加载多会话数据
  /// 返回 (conversations, conversationOrder)
  Future<Map<String, List<ChatMessage>>> loadConversations() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) return {};

      final jsonStr = await file.readAsString();
      final decoded = jsonDecode(jsonStr);

      // 新格式：Map 包含 "conversations"
      if (decoded is Map<String, dynamic> && decoded.containsKey('conversations')) {
        final convMap = decoded['conversations'] as Map<String, dynamic>;
        final result = <String, List<ChatMessage>>{};
        for (final entry in convMap.entries) {
          final list = (entry.value as List<dynamic>)
              .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
              .toList();
          result[entry.key] = list;
        }
        debugPrint('[Storage] 已加载 ${result.length} 个会话');
        return result;
      }

      // 旧格式兼容：扁平消息列表 -> 转为 "default" 会话
      if (decoded is List) {
        if (decoded.isEmpty) return {};
        final messages = decoded
            .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
            .toList();
        debugPrint('[Storage] 兼容旧格式，已加载 ${messages.length} 条消息');
        return {'default': messages};
      }

      debugPrint('[Storage] 无法识别的数据格式');
      return {};
    } catch (e) {
      debugPrint('[Storage] 加载会话失败: $e');
      return {};
    }
  }

  /// 获取会话顺序列表
  Future<List<String>> loadConversationOrder() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) return [];

      final jsonStr = await file.readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (json.containsKey('conversationOrder')) {
        final order = (json['conversationOrder'] as List<dynamic>)
            .map((e) => e as String)
            .toList();
        return order;
      }

      // 旧格式兼容
      return ['default'];
    } catch (e) {
      debugPrint('[Storage] 加载会话顺序失败: $e');
      return [];
    }
  }

  /// 清空所有已保存的数据
  Future<void> clearAll() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[Storage] 已清空所有数据');
      }
    } catch (e) {
      debugPrint('[Storage] 清空数据失败: $e');
    }
  }
}
