import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/chat_provider.dart';
import '../config/app_config.dart';

/// 设置页面 - 配置 API 连接、模型选择、连接方式等
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tunnelUrlController;
  late TextEditingController _searchApiKeyController;
  bool _streamEnabled = true;
  String _connectionMode = AppConfig.modeLan;
  bool _isTesting = false;
  String? _connectionStatus;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ChatProvider>();
    _hostController = TextEditingController(text: provider.apiHost);
    _portController = TextEditingController(text: provider.apiPort);
    _tunnelUrlController = TextEditingController(text: provider.tunnelUrl);
    _searchApiKeyController = TextEditingController(text: provider.searchApiKey);
    _streamEnabled = provider.streamEnabled;
    _connectionMode = provider.connectionMode;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tunnelUrlController.dispose();
    _searchApiKeyController.dispose();
    super.dispose();
  }

  /// 保存设置到 Provider 和本地存储
  Future<void> _saveSettings() async {
    // 端口号合法性校验（1-65535）
    final portStr = _portController.text.trim();
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('端口号必须在 1-65535 之间'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final provider = context.read<ChatProvider>();
    await provider.updateConfig(
      host: _hostController.text.trim(),
      port: portStr,
      key: '',
      connectionMode: _connectionMode,
      tunnelUrl: _tunnelUrlController.text.trim(),
      streamEnabled: _streamEnabled,
      searchApiKey: _searchApiKeyController.text.trim(),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('设置已保存'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  /// 测试 API 连接
  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = null;
    });

    // 先保存当前配置
    final provider = context.read<ChatProvider>();
    await provider.updateConfig(
      host: _hostController.text.trim(),
      port: _portController.text.trim(),
      key: '',
      connectionMode: _connectionMode,
      tunnelUrl: _tunnelUrlController.text.trim(),
      streamEnabled: _streamEnabled,
      searchApiKey: _searchApiKeyController.text.trim(),
    );

    final success = await provider.testConnection();
    if (mounted) {
      setState(() {
        _isTesting = false;
        _connectionStatus = success ? '连接成功 ✅' : '连接失败 ❌ 请检查配置';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            // 返回时自动保存设置，端口校验由 _saveSettings 内部处理
            await _saveSettings();
            if (mounted && context.mounted) Navigator.pop(context);
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== 服务器连接设置 =====
          _buildSectionTitle('服务器连接'),
          // 连接说明小字提示
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'App 直连本地 Ollama API，需确保 Ollama 已配置 OLLAMA_HOST=0.0.0.0 监听局域网',
              style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // API 地址输入
                  TextField(
                    controller: _hostController,
                    decoration: InputDecoration(
                      labelText: 'API 地址',
                      hintText: '例: 192.168.31.13',
                      prefixIcon: const Icon(Icons.computer),
                      suffixIcon: _buildPasteButton(_hostController),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 端口号输入
                  TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '端口号',
                      hintText: '11434',
                      prefixIcon: const Icon(Icons.router),
                      suffixIcon: _buildPasteButton(_portController),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 测试连接按钮
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isTesting ? null : _testConnection,
                      icon: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find),
                      label: Text(_isTesting ? '测试中...' : '测试连接'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  // 连接状态显示
                  if (_connectionStatus != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _connectionStatus!,
                      style: TextStyle(
                        color: _connectionStatus!.contains('✅')
                            ? Colors.green
                            : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ===== 模型设置 =====
          _buildSectionTitle('模型设置'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Consumer<ChatProvider>(
                builder: (context, provider, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 刷新模型列表按钮
                      Row(
                        children: [
                          const Flexible(
                            child: Text('选择模型', style: TextStyle(fontSize: 16)),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('刷新列表'),
                            onPressed: () => provider.fetchModels(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 模型下拉选择器
                      if (provider.availableModels.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey('model_${provider.availableModels.length}_${provider.selectedModel}'),
                          initialValue: provider.selectedModel,
                          isExpanded: true, // 防止内容溢出
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            isDense: true,
                          ),
                          items: provider.availableModels
                              .map((m) => DropdownMenuItem<String>(
                                    value: m.id,
                                    child: Text(m.name, overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              provider.selectModel(value);
                            }
                          },
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () => provider.fetchModels(),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('获取可用模型列表'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ===== 连接方式 =====
          _buildSectionTitle('连接方式'),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              '局域网直连：手机和电脑在同一 WiFi 下使用；内网穿透：通过 cpolar/ngrok 在外网访问',
              style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RadioGroup<String>(
                groupValue: _connectionMode,
                onChanged: (v) {
                  if (v != null) setState(() => _connectionMode = v);
                },
                child: Column(
                  children: [
                    // 局域网直连
                    RadioListTile<String>(
                      title: const Text('局域网直连'),
                      subtitle: const Text('手机和电脑在同一 WiFi 下使用'),
                      value: AppConfig.modeLan,
                    ),
                    // 内网穿透
                    RadioListTile<String>(
                      title: const Text('内网穿透'),
                      subtitle: const Text('通过 cpolar / ngrok 等工具'),
                      value: AppConfig.modeTunnel,
                    ),
                    // 隧道地址输入（仅在内网穿透模式下显示）
                    if (_connectionMode == AppConfig.modeTunnel)
                      Padding(
                        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                        child: TextField(
                          controller: _tunnelUrlController,
                          decoration: InputDecoration(
                            labelText: '隧道地址',
                            hintText: 'http://6ab1a896.r18.cpolar.top',
                            prefixIcon: const Icon(Icons.link),
                            suffixIcon: _buildPasteButton(_tunnelUrlController),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ===== 其他设置 =====
          _buildSectionTitle('其他设置'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('流式输出'),
                  subtitle: const Text('打字机效果逐字显示回复'),
                  value: _streamEnabled,
                  onChanged: (v) => setState(() => _streamEnabled = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ===== 联网搜索设置 =====
          _buildSectionTitle('联网搜索'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.language, size: 18, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Tavily Search API Key',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '在输入框左侧点击地球图标开启联网搜索，AI 将获取实时搜索结果',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchApiKeyController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'tvly-xxxxxxxxxxxx',
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                      border: const OutlineInputBorder(),
                      suffix: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchApiKeyController.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '已设置',
                                style: TextStyle(
                                  color: Colors.green[600],
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          _buildPasteButton(_searchApiKeyController),
                        ],
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '免费注册: ',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                      GestureDetector(
                        onTap: () async {
                          final uri = Uri.parse('https://app.tavily.com');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Text(
                          'app.tavily.com',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[600],
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // 保存设置按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.blue[500],
                foregroundColor: Colors.white,
              ),
              child: const Text('保存设置', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 构建粘贴按钮 — 从剪贴板读取文本并填入对应的输入框
  Widget _buildPasteButton(TextEditingController controller) {
    return IconButton(
      icon: const Icon(Icons.content_paste_rounded, size: 20),
      tooltip: '粘贴',
      onPressed: () async {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data?.text != null && data!.text!.isNotEmpty) {
          // 记录当前光标位置并插入/替换选中内容
          final text = controller.text;
          final selection = controller.selection;
          final newText = text.replaceRange(
            selection.isValid ? selection.start : text.length,
            selection.isValid ? selection.end : text.length,
            data.text!,
          );
          controller.text = newText;
          // 将光标移动到粘贴内容的末尾
          final cursorPos = (selection.isValid ? selection.start : text.length) +
              data.text!.length;
          controller.selection = TextSelection.collapsed(offset: cursorPos);
        }
      },
    );
  }

  /// 构建分组标题
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }
}
