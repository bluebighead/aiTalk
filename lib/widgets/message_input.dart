import 'package:flutter/material.dart';

/// 消息输入框组件 - 底部输入区域
/// 包含文本输入框、联网搜索按钮和发送/停止按钮
class MessageInput extends StatefulWidget {
  final Function(String) onSend; // 发送消息回调
  final VoidCallback? onStop; // 停止 AI 回复回调
  final VoidCallback? onToggleSearch; // 切换搜索模式回调
  final bool isEnabled; // 是否可输入（发送中禁用）
  final bool isStreaming; // 是否正在流式输出
  final bool searchEnabled; // 搜索模式是否开启

  const MessageInput({
    super.key,
    required this.onSend,
    this.onStop,
    this.onToggleSearch,
    this.isEnabled = true,
    this.isStreaming = false,
    this.searchEnabled = false,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 发送消息并清空输入框
  void _onSend() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && widget.isEnabled) {
      widget.onSend(text);
      _controller.clear();
      setState(() => _hasText = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // isLoading（搜索/等待模型加载）或 isStreaming（流式输出中）时都显示停止按钮
    final showStop = widget.isStreaming || !widget.isEnabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 联网搜索按钮（左侧）
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.searchEnabled
                    ? Colors.blue.withValues(alpha: 0.1)
                    : Colors.transparent,
              ),
              child: IconButton(
                icon: Icon(
                  Icons.language_rounded,
                  size: 22,
                  color: widget.searchEnabled ? Colors.blue[600] : Colors.grey[400],
                ),
                tooltip: widget.searchEnabled ? '联网搜索已开启' : '联网搜索',
                onPressed: widget.onToggleSearch,
              ),
            ),
            const SizedBox(width: 4),
            // 文本输入框（流式输出时禁用）
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !showStop && widget.isEnabled,
                maxLines: 5,
                minLines: 1,
                maxLength: 4096, // 限制最大输入字符数，避免极端长文本
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  counterText: '', // 隐藏计数器以保持输入框简洁
                  hintText: showStop ? 'AI 回复中...' : '输入消息...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: showStop ? Colors.grey[200] : Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon: widget.searchEnabled
                      ? Tooltip(
                          message: '联网搜索已开启',
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.language, size: 12, color: Colors.blue[600]),
                                const SizedBox(width: 2),
                                Text(
                                  '在线',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : null,
                ),
                onChanged: (text) {
                  setState(() => _hasText = text.trim().isNotEmpty);
                },
                onSubmitted: widget.isEnabled && !showStop
                    ? (_) => _onSend()
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            // 发送/停止按钮
            if (showStop)
              Container(
                decoration: BoxDecoration(
                  color: Colors.red[400],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.stop_rounded, size: 22),
                  color: Colors.white,
                  tooltip: '停止回复',
                  onPressed: widget.onStop,
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: _hasText && widget.isEnabled
                      ? Colors.blue[500]
                      : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, size: 20),
                  color: _hasText && widget.isEnabled
                      ? Colors.white
                      : Colors.grey[500],
                  onPressed: _hasText && widget.isEnabled ? _onSend : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
