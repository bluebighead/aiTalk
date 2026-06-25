import 'dart:math';
import 'package:flutter/material.dart';
import '../providers/chat_provider.dart';

/// AI 思考中动画组件 - 用三个跳动的小圆点表示 AI 正在生成回复
/// 显示当前发送阶段的状态文字（搜索中 / 加载中 / 生成中 / 超时）
class ThinkingIndicator extends StatefulWidget {
  /// AI 已思考的秒数（由 Provider 实时更新）
  final int elapsedSeconds;

  /// 当前发送阶段
  final SendingStage stage;

  const ThinkingIndicator({
    super.key,
    this.elapsedSeconds = 0,
    this.stage = SendingStage.loadingModel,
  });

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 创建一个无限循环动画，控制三个小圆点的跳动
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 头像
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.deepPurple.withValues(alpha: 0.2),
            child: const Icon(Icons.smart_toy_outlined, size: 18, color: Colors.deepPurple),
          ),
          const SizedBox(width: 8),
          // 加载气泡
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 三个带延迟的跳动圆点
                _buildDot(0),
                const SizedBox(width: 5),
                _buildDot(1),
                const SizedBox(width: 5),
                _buildDot(2),
                const SizedBox(width: 8),
                // 根据阶段显示不同状态文字
                Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 13,
                    color: _getStatusColor(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 根据当前阶段返回对应的状态文字
  String _getStatusText() {
    switch (widget.stage) {
      case SendingStage.searching:
        return '正在联网搜索...';
      case SendingStage.loadingModel:
        return '等待模型加载...';
      case SendingStage.generating:
        return '思考中 ${widget.elapsedSeconds}s';
      case SendingStage.timeout:
        return '模型加载超时（25s），请检查模型状态';
      case SendingStage.none:
        return '';
    }
  }

  /// 根据当前阶段返回对应的文字颜色
  Color _getStatusColor() {
    switch (widget.stage) {
      case SendingStage.searching:
        return Colors.blue[500]!;
      case SendingStage.loadingModel:
        return Colors.orange[600]!;
      case SendingStage.generating:
        return Colors.grey[500]!;
      case SendingStage.timeout:
        return Colors.red[500]!;
      case SendingStage.none:
        return Colors.grey[500]!;
    }
  }

  /// 构建单个跳动圆点
  /// [index] 圆点序号（0,1,2），用于错开动画时间
  Widget _buildDot(int index) {
    final delay = index * 0.15;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = (_controller.value - delay / 1.2).clamp(0.0, 1.0);
        final scale = 0.5 + 0.5 * sin(t * 3.14159 * 2);
        final opacity = 0.4 + 0.6 * sin(t * 3.14159 * 2).abs();

        return Transform.scale(
          scale: 0.6 + 0.4 * scale,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _getDotColor(),
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 圆点颜色跟随阶段变化
  Color _getDotColor() {
    switch (widget.stage) {
      case SendingStage.searching:
        return Colors.blue;
      case SendingStage.loadingModel:
        return Colors.orange;
      case SendingStage.timeout:
        return Colors.red;
      default:
        return Colors.deepPurple;
    }
  }
}

/// 流式输出闪烁光标组件
class StreamingCursor extends StatefulWidget {
  const StreamingCursor({super.key});

  @override
  State<StreamingCursor> createState() => _StreamingCursorState();
}

class _StreamingCursorState extends State<StreamingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 16,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
