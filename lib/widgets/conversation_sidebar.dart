import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

/// 会话侧边栏组件 — 展示所有会话列表，支持删除模式
class ConversationSidebar extends StatelessWidget {
  const ConversationSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final deleteMode = provider.deleteMode;
    final selectedForDelete = provider.selectedForDelete;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // ---- 顶部标题栏 ----
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history_rounded, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text(
                        '对话列表',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      // 新建会话按钮（非删除模式下显示）
                      if (!deleteMode)
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded),
                          iconSize: 22,
                          color: Colors.blue[500],
                          tooltip: '新建对话',
                          onPressed: () {
                            provider.createNewConversation();
                            Navigator.pop(context);
                          },
                        ),
                      if (deleteMode)
                        TextButton(
                          onPressed: () => provider.toggleDeleteMode(),
                          child: const Text('取消'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '共 ${provider.conversationOrder.length} 个对话',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),

            // ---- 会话列表 ----
            Expanded(
              child: provider.conversationOrder.isEmpty
                  ? Center(
                      child: Text(
                        '暂无对话',
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: provider.conversationOrder.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (context, index) {
                        final convId = provider.conversationOrder[index];
                        final isCurrent = convId == provider.currentConversationId;
                        final title = provider.getConversationTitle(convId);
                        final isChecked = selectedForDelete.contains(convId);

                        return _ConversationTile(
                          convId: convId,
                          title: title,
                          isCurrent: isCurrent,
                          deleteMode: deleteMode,
                          isChecked: isChecked,
                          onTap: () {
                            if (deleteMode) {
                              provider.toggleConversationSelection(convId);
                            } else {
                              provider.switchConversation(convId);
                              Navigator.pop(context); // 关闭侧边栏
                            }
                          },
                        );
                      },
                    ),
            ),

            // ---- 底部操作按钮 ----
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: Column(
                children: [
                  if (deleteMode && selectedForDelete.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmDelete(context, provider, selectedForDelete.length),
                        icon: const Icon(Icons.delete_forever_rounded, size: 20),
                        label: Text('删除所选 (${selectedForDelete.length})'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[500],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => provider.toggleDeleteMode(),
                        icon: Icon(
                          deleteMode ? Icons.close : Icons.delete_outline_rounded,
                          size: 20,
                        ),
                        label: Text(deleteMode ? '取消删除' : '删除对话'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: deleteMode ? Colors.grey : Colors.red[400],
                          side: BorderSide(
                            color: deleteMode ? Colors.grey[300]! : Colors.red[200]!,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 确认删除弹窗
  Future<void> _confirmDelete(BuildContext context, ChatProvider provider, int count) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 $count 个对话吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await provider.deleteSelectedConversations();
      if (context.mounted) Navigator.pop(context); // 关闭侧边栏
    }
  }
}

/// 单个会话列表项
class _ConversationTile extends StatelessWidget {
  final String convId;
  final String title;
  final bool isCurrent;
  final bool deleteMode;
  final bool isChecked;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.convId,
    required this.title,
    required this.isCurrent,
    required this.deleteMode,
    required this.isChecked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 删除模式下显示复选框
            if (deleteMode)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Checkbox(
                  value: isChecked,
                  onChanged: (_) => onTap(),
                  activeColor: Colors.red,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            // 当前会话指示图标
            Icon(
              isCurrent ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
              size: 20,
              color: isCurrent ? Colors.blue[500] : Colors.grey[500],
            ),
            const SizedBox(width: 10),
            // 会话标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 当前会话标记
            if (isCurrent && !deleteMode)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '当前',
                  style: TextStyle(fontSize: 10, color: Colors.blue[600]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
