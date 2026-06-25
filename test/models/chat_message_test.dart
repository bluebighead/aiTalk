import 'package:flutter_test/flutter_test.dart';
import 'package:ai_talk/models/chat_message.dart';

void main() {
  group('ChatMessage 序列化测试', () {
    test('toJson 正确转换所有字段', () {
      final time = DateTime(2026, 6, 24, 14, 30, 0);
      final msg = ChatMessage(
        id: 'test_123',
        conversationId: 'default',
        role: MessageRole.user,
        content: '你好',
        timestamp: time,
        thinkTimeSeconds: null,
      );

      final json = msg.toJson();

      expect(json['id'], 'test_123');
      expect(json['conversationId'], 'default');
      expect(json['role'], 'user');
      expect(json['content'], '你好');
      expect(json['timestamp'], '2026-06-24T14:30:00.000');
      expect(json['thinkTimeSeconds'], isNull);
    });

    test('fromJson 正确恢复所有字段', () {
      final json = {
        'id': 'ai_456',
        'conversationId': 'conv_1',
        'role': 'assistant',
        'content': '你好！有什么可以帮助你的？',
        'timestamp': '2026-06-24T14:30:05.000',
        'thinkTimeSeconds': 2.3,
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.id, 'ai_456');
      expect(msg.conversationId, 'conv_1');
      expect(msg.role, MessageRole.assistant);
      expect(msg.content, '你好！有什么可以帮助你的？');
      expect(msg.timestamp, DateTime(2026, 6, 24, 14, 30, 5));
      expect(msg.thinkTimeSeconds, 2.3);
      expect(msg.isUser, isFalse);
      expect(msg.isStreaming, isFalse);
    });

    test('fromJson 兼容旧数据（无 conversationId）', () {
      final json = {
        'id': 'ai_789',
        'role': 'assistant',
        'content': '旧数据',
        'timestamp': '2026-06-24T14:30:05.000',
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.conversationId, 'default'); // 回退为 'default'
      expect(msg.content, '旧数据');
    });

    test('toJson → fromJson 往返一致', () {
      final original = ChatMessage(
        id: 'msg_789',
        conversationId: 'default',
        role: MessageRole.system,
        content: '这是一条系统消息',
        thinkTimeSeconds: 0,
      );

      final json = original.toJson();
      final restored = ChatMessage.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.conversationId, original.conversationId);
      expect(restored.role, original.role);
      expect(restored.content, original.content);
      expect(restored.thinkTimeSeconds, original.thinkTimeSeconds);
    });

    test('isUser 判断正确', () {
      final userMsg = ChatMessage(id: '1', conversationId: 'default', role: MessageRole.user, content: 'hi');
      final aiMsg = ChatMessage(id: '2', conversationId: 'default', role: MessageRole.assistant, content: 'hello');
      final sysMsg = ChatMessage(id: '3', conversationId: 'default', role: MessageRole.system, content: 'system');

      expect(userMsg.isUser, isTrue);
      expect(aiMsg.isUser, isFalse);
      expect(sysMsg.isUser, isFalse);
    });

    test('copyWith 只覆盖指定字段', () {
      final original = ChatMessage(
        id: 'id_1',
        conversationId: 'default',
        role: MessageRole.assistant,
        content: '原内容',
        isStreaming: true,
        thinkTimeSeconds: null,
      );

      final copied = original.copyWith(content: '新内容', isStreaming: false);

      expect(copied.id, 'id_1'); // 不变
      expect(copied.conversationId, 'default'); // 不变
      expect(copied.role, MessageRole.assistant); // 不变
      expect(copied.content, '新内容'); // 更新
      expect(copied.isStreaming, isFalse); // 更新
      expect(copied.thinkTimeSeconds, isNull); // 不变
    });

    test('isStreaming 状态不持久化', () {
      final streamingMsg = ChatMessage(
        id: 's1',
        conversationId: 'default',
        role: MessageRole.assistant,
        content: '部分内容',
        isStreaming: true,
      );

      final json = streamingMsg.toJson();
      expect(json.containsKey('isStreaming'), isFalse);
    });

    test('默认时间戳为当前时间', () {
      final before = DateTime.now();
      final msg = ChatMessage(
        id: 't1',
        conversationId: 'default',
        role: MessageRole.user,
        content: 'test',
      );
      final after = DateTime.now();

      expect(msg.timestamp.isAfter(before) || msg.timestamp == before, isTrue);
      expect(msg.timestamp.isBefore(after) || msg.timestamp == after, isTrue);
    });
  });
}
