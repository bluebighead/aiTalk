import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../services/timer_service.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_input.dart';
import '../widgets/thinking_indicator.dart';
import '../widgets/conversation_sidebar.dart';
import 'settings_page.dart';

/// 聊天主页 - 应用主界面
/// 包含侧边栏、消息列表、底部模型切换栏和输入框
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().refreshModelsAndConnection();
    });
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (mounted) {
      context.read<ChatProvider>().refreshModelsAndConnection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 侧边栏 — 会话列表
      drawer: const ConversationSidebar(),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        leadingWidth: 96, // 增大 leading 宽度，容纳两个按钮避免溢出
        // 左侧：菜单按钮（打开侧边栏）+ 清空当前会话按钮
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu_rounded),
                tooltip: '对话列表',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            // 清空当前会话按钮
            context.select<ChatProvider, bool>((p) =>
                    p.messages.isEmpty || p.isStreaming)
                ? IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    tooltip: '清空当前对话',
                    onPressed: null,
                  )
                : IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    tooltip: '清空当前对话',
                    onPressed: () async {
                      final confirm = await _confirmClear(context);
                      if (confirm && mounted) {
                        context.read<ChatProvider>().clearCurrentConversation();
                      }
                    },
                  ),
          ],
        ),
        title: _AppBarTitle(),
        actions: [
          // 刷新连接按钮
          context.select<ChatProvider, Widget>((p) {
            return IconButton(
              icon: p.checkingConnection
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find, size: 22),
              tooltip: '检测连接',
              onPressed:
                  p.checkingConnection ? null : () => p.checkConnection(),
            );
          }),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表区域（包裹 SelectionArea，统一管理文字选择）
          Expanded(
            child: SelectionArea(
              child: _MessageListView(),
            ),
          ),
          // 模型快速切换栏（位于输入框上方）
          const _ModelSwitcherBar(),
          // 错误提示条
          context.select<ChatProvider, Widget>((p) {
            if (p.errorMessage != null) {
              return _buildErrorBar(p.errorMessage!);
            }
            return const SizedBox.shrink();
          }),
          // 底部消息输入框
          Consumer<ChatProvider>(
            builder: (context, provider, _) {
              return MessageInput(
                onSend: (text) => provider.sendMessage(text),
                // isLoading 或 isStreaming 时都可以停止
                onStop: provider.isBusy ? () => provider.stopStreaming() : null,
                onToggleSearch: () => provider.toggleSearch(),
                isEnabled: !provider.isBusy,
                isStreaming: provider.isStreaming,
                searchEnabled: provider.searchEnabled,
              );
            },
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmClear(BuildContext context) async {
    final provider = context.read<ChatProvider>();
    if (provider.messages.isEmpty) return true;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空当前对话的所有消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _buildErrorBar(String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.red[50],
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== 子组件 ====================

/// AppBar 标题 — 监听连接状态和模型名称
class _AppBarTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isConnected = context.select<ChatProvider, bool>((p) => p.isConnected);
    final checking = context.select<ChatProvider, bool>((p) => p.checkingConnection);

    Color dotColor;
    if (checking) {
      dotColor = Colors.grey;
    } else if (isConnected) {
      dotColor = Colors.green;
    } else {
      dotColor = Colors.red;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: isConnected
                    ? [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            const Text('AI Talk', style: TextStyle(fontSize: 17)),
          ],
        ),
      ],
    );
  }
}

/// 模型快速切换栏 — 位于消息列表下方、输入框上方
class _ModelSwitcherBar extends StatefulWidget {
  const _ModelSwitcherBar();

  @override
  State<_ModelSwitcherBar> createState() => _ModelSwitcherBarState();
}

class _ModelSwitcherBarState extends State<_ModelSwitcherBar> {
  final _buttonKey = GlobalKey();

  /// 弹出模型选择菜单
  /// 使用 showMenu 替代 PopupMenuButton，确保点击空白处时菜单正确折叠且不会把焦点传到输入框
  void _showModelMenu(BuildContext context) async {
    final provider = context.read<ChatProvider>();
    final models = provider.availableModels;
    if (models.isEmpty) return;

    // 获取模型切换按钮的位置，用于定位菜单
    final renderBox = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    // showMenu 会创建带 ModalBarrier 的 PopupRoute，点击遮罩层会关闭菜单并消耗点击事件
    // 锚点设置为按钮的完整边界，showMenu 自动选择上方弹出（因按钮在屏幕底部）
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        offset.dx + size.width,
        offset.dy + size.height,
      ),
      items: models.map((model) {
        final isSelected = model.id == provider.selectedModel;
        return PopupMenuItem<String>(
          value: model.id,
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: isSelected ? Colors.blue : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  model.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    if (result != null && context.mounted) {
      provider.selectModel(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final models = provider.availableModels;
    final selectedModel = provider.selectedModel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // 模型切换下拉（紧凑宽度，不占满整行）
          models.isEmpty
              ? Text(
                  '未获取到模型',
                  style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                )
              : GestureDetector(
                  key: _buttonKey,
                  onTap: () => _showModelMenu(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz_rounded, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          selectedModel,
                          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                        Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[500]),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

/// 消息列表
class _MessageListView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final messages = context.select<ChatProvider, List>((p) => p.messages);
    final isLoading = context.select<ChatProvider, bool>((p) => p.isLoading);

    // 空状态
    if (messages.isEmpty && !isLoading) {
      final isConnected =
          context.select<ChatProvider, bool>((p) => p.isConnected);
      return _buildEmptyState(context, isConnected);
    }

    // 用 GestureDetector 捕获空白处点击，清除文字选择
    // behavior: translucent 确保子组件（如链接）的点击事件仍然正常处理
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        // 点击空白区域时清除文字选择状态
        // SelectableRegionState 通过 package:flutter/widgets.dart 导出
        context.findAncestorStateOfType<SelectableRegionState>()?.clearSelection();
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: messages.length + (isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == messages.length) {
            return const _ThinkingIndicatorWrapper();
          }
          final message = messages[index];
          final isLastStreaming =
              message.isStreaming && index == messages.length - 1;
          return RepaintBoundary(
            child: MessageBubble(
              message: message,
              streamingElapsedSeconds: isLastStreaming ? -1 : 0,
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isConnected) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConnected ? Icons.chat_bubble_outline : Icons.wifi_off_rounded,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            isConnected ? '开始和 AI 对话吧' : '未连接到服务器',
            style: TextStyle(fontSize: 18, color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          Text(
            isConnected ? '点击左下角 + 新建对话' : '请先在设置中配置 API 连接',
            style: TextStyle(fontSize: 14, color: Colors.grey[350]),
          ),
          if (!isConnected) ...[
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
              icon: const Icon(Icons.settings),
              label: const Text('前往设置'),
            ),
          ],
        ],
      ),
    );
  }
}

/// ThinkingIndicator 的包装 — 独立监听 ElapsedTimerService 和 SendingStage
class _ThinkingIndicatorWrapper extends StatelessWidget {
  const _ThinkingIndicatorWrapper();

  @override
  Widget build(BuildContext context) {
    final seconds =
        context.select<ElapsedTimerService, int>((t) => t.elapsedSeconds);
    final stage =
        context.select<ChatProvider, SendingStage>((p) => p.sendingStage);
    return ThinkingIndicator(elapsedSeconds: seconds, stage: stage);
  }
}
