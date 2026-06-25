import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message.dart';
import '../services/timer_service.dart';
import '../providers/chat_provider.dart';
import 'thinking_indicator.dart';

/// 消息气泡组件 - 显示单条聊天消息
/// 用户消息：蓝色气泡右对齐，AI 消息：灰色气泡左对齐
class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  /// 流式输出秒数。传入 -1 表示最近一条流式消息，将自动从 ElapsedTimerService 读取
  final int streamingElapsedSeconds;

  const MessageBubble({
    super.key,
    required this.message,
    this.streamingElapsedSeconds = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 头像（仅 AI 消息显示）
          if (!isUser) _buildAvatar(Icons.smart_toy_outlined, Colors.deepPurple),
          const SizedBox(width: 8),
          // 消息气泡
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue[500] : Colors.grey[200],
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 消息内容：用户消息可选择文字，AI 消息渲染 Markdown（支持链接点击 + 代码选择）
                  if (isUser)
                    SelectableText(
                      message.content,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    )
                  else
                    Markdown(
                      data: message.content,
                      selectable: true, // 内置文字选择
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(), // 禁止内部滚动，交由父级 ListView 控制
                      // 点击链接时弹出浏览器选择器
                      onTapLink: (text, href, title) {
                        if (href != null) {
                          launchUrl(Uri.parse(href), mode: LaunchMode.platformDefault);
                        }
                      },
                      styleSheet: MarkdownStyleSheet(
                        p: const TextStyle(fontSize: 15, color: Colors.black87),
                        // 行内代码样式
                        code: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          backgroundColor: Colors.grey[300],
                          color: Colors.black87,
                        ),
                        // 代码块样式：深色背景 + 圆角 + 内边距 + 等宽字体
                        codeblockDecoration: BoxDecoration(
                          color: Colors.grey[350],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        codeblockPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        blockquoteDecoration: BoxDecoration(
                          color: Colors.grey[100],
                          border: const Border(
                            left: BorderSide(width: 4, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  // 流式输出闪烁光标
                  if (message.isStreaming) const StreamingCursor(),
                  // 底部操作栏：时间戳 + 复制按钮 + AI 思考耗时/实时计时 + 翻译按钮
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 消息发送时间
                      Text(
                        _formatTime(message.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: isUser ? Colors.white70 : Colors.grey[500],
                        ),
                      ),
                      // 流式输出中的实时思考秒数
                      if (!isUser && message.isStreaming) ...[
                        const SizedBox(width: 6),
                        _StreamingTimerBadge(),
                      ],
                      // AI 消息完成后的思考耗时显示
                      if (!isUser &&
                          !message.isStreaming &&
                          message.thinkTimeSeconds != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _formatThinkTime(message.thinkTimeSeconds!),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                      // 复制按钮（非流式、非空内容）- 用户和 AI 消息均显示
                      if (!message.isStreaming && message.content.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _CopyButton(message: message),
                      ],
                      // AI 消息的翻译按钮（非流式、非空内容）
                      if (!isUser && !message.isStreaming && message.content.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _TranslateButton(message: message),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 用户头像（仅用户消息显示）
          if (isUser) const SizedBox(width: 8),
          if (isUser) _buildAvatar(Icons.person, Colors.blue),
        ],
      ),
    );
  }

  /// 构建圆形头像
  Widget _buildAvatar(IconData icon, Color color) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: color.withValues(alpha: 0.2),
      child: Icon(icon, size: 18, color: color),
    );
  }

  /// 格式化显示时间（时:分）
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 格式化思考耗时显示
  String _formatThinkTime(double seconds) {
    if (seconds < 1) return '思考时间：<1s';
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = (seconds % 60).toInt();
      return '思考时间：${m}m${s}s';
    }
    return '思考时间：${seconds.toStringAsFixed(1)}s';
  }
}

/// 流式计时徽章 — 独立监听 ElapsedTimerService
/// 每秒 tick 仅触发此组件重建，不影响上游 MessageBubble 树
class _StreamingTimerBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final seconds =
        context.select<ElapsedTimerService, int>((t) => t.elapsedSeconds);
    if (seconds <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '思考中 ${seconds}s',
        style: TextStyle(
          fontSize: 10,
          color: Colors.deepPurple[400],
        ),
      ),
    );
  }
}

/// 翻译按钮组件 — 点击后翻译 AI 消息内容并弹出结果
class _TranslateButton extends StatelessWidget {
  final ChatMessage message;

  const _TranslateButton({required this.message});

  @override
  Widget build(BuildContext context) {
    final isTranslating =
        context.select<ChatProvider, bool>((p) => p.isTranslating(message.id));
    final translation =
        context.select<ChatProvider, String?>((p) => p.getTranslation(message.id));

    // 正在翻译 → 显示加载圈
    if (isTranslating) {
      return SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.grey[500],
        ),
      );
    }

    // 已有翻译结果 → 绿色图标（提示可查看）
    final iconColor = translation != null ? Colors.green[600] : Colors.grey[400];

    return GestureDetector(
      onTap: () => _showTranslation(context),
      child: Icon(
        Icons.translate_rounded,
        size: 16,
        color: iconColor,
      ),
    );
  }

  /// 弹出翻译结果底部面板
  Future<void> _showTranslation(BuildContext context) async {
    final provider = context.read<ChatProvider>();

    // 如果已有缓存结果，直接显示
    final cached = provider.getTranslation(message.id);
    if (cached != null) {
      _showTranslationSheet(context, cached);
      return;
    }

    // 否则请求翻译并显示
    final result = await provider.translateMessage(message.id, message.content);
    if (context.mounted) {
      _showTranslationSheet(context, result);
    }
  }

  /// 构建翻译结果弹窗
  void _showTranslationSheet(BuildContext context, String translation) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.4,
          minChildSize: 0.25,
          maxChildSize: 0.75,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部拖动指示条
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 标题 + 关闭按钮
                  Row(
                    children: [
                      Icon(Icons.translate_rounded,
                          size: 20, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      const Text(
                        '翻译结果',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  // 翻译结果内容（可滚动）
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: SelectableText(
                        translation,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// 复制按钮组件 — 点击将消息内容复制到剪贴板
class _CopyButton extends StatelessWidget {
  final ChatMessage message;

  const _CopyButton({required this.message});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // 将消息内容复制到系统剪贴板
        Clipboard.setData(ClipboardData(text: message.content));
        // 显示复制成功的提示
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已复制到剪贴板'),
            duration: Duration(seconds: 1),
          ),
        );
      },
      child: Icon(
        Icons.copy_rounded,
        size: 14,
        color: Colors.grey[400],
      ),
    );
  }
}
