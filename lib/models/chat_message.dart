/// 聊天消息模型 - 表示一条对话消息
/// role 区分用户/AI/系统消息，isStreaming 标记流式输出状态
enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id; // 消息唯一 ID
  final String conversationId; // 所属会话 ID
  final MessageRole role; // 消息角色：用户/AI/系统
  final String content; // 消息内容
  final DateTime timestamp; // 发送时间
  final bool isStreaming; // 是否正在流式输出中
  final double? thinkTimeSeconds; // AI 思考耗时（秒），完成后设置

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.isStreaming = false,
    this.thinkTimeSeconds,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 复制并修改部分字段（用于流式更新内容）
  ChatMessage copyWith({
    String? id,
    String? conversationId,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isStreaming,
    double? thinkTimeSeconds,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      thinkTimeSeconds: thinkTimeSeconds ?? this.thinkTimeSeconds,
    );
  }

  /// 判断是否为用户消息
  bool get isUser => role == MessageRole.user;

  /// 转为 JSON（用于持久化存储）
  /// isStreaming 状态不持久化，加载时统一设为 false
  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        'thinkTimeSeconds': thinkTimeSeconds,
      };

  /// 从 JSON 恢复（从持久化存储加载）
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String? ?? 'default',
      role: MessageRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => MessageRole.user,
      ),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      thinkTimeSeconds: (json['thinkTimeSeconds'] as num?)?.toDouble(),
    );
  }
}
