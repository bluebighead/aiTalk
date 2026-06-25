import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/chat_message.dart';
import '../models/model_info.dart';
import '../services/api_service.dart';
import '../services/web_search_service.dart';
import '../services/storage_service.dart';
import '../services/timer_service.dart';
import '../config/app_config.dart';

/// 发送阶段枚举 - 用于向用户展示当前所处的处理阶段
/// 从发送消息到 AI 完成回复的完整生命周期
enum SendingStage {
  none,           // 空闲状态
  searching,      // 正在联网搜索
  loadingModel,   // 等待模型加载 / 首 token
  generating,     // AI 正在生成内容
  timeout,        // 首 token 超时
}

/// 聊天状态管理 - 核心状态管理器
/// 负责管理多会话、消息列表、API 配置、模型选择、连接状态、联网搜索
/// 使用 ChangeNotifier 实现与 UI 的响应式绑定
class ChatProvider extends ChangeNotifier {
  late ApiService _apiService;
  late WebSearchService _webSearchService;

  // ----- 多会话管理 -----
  final Map<String, List<ChatMessage>> _conversations = {}; // 会话ID -> 消息列表
  List<String> _conversationOrder = []; // 会话ID有序列表
  String _currentConversationId = 'default'; // 当前会话ID

  List<ModelInfo> _availableModels = [];
  String _selectedModel = 'baytout3/qwen3.5-uncensored:9b';
  bool _isLoading = false;
  bool _isStreaming = false;
  bool _streamEnabled = true;
  String? _errorMessage;

  // 设置配置
  String _apiHost = AppConfig.defaultHost;
  String _apiPort = AppConfig.defaultPort;
  String _apiKey = '';
  String _connectionMode = AppConfig.modeLan;
  String _tunnelUrl = AppConfig.defaultTunnelUrl;
  bool _isConnected = false;
  bool _checkingConnection = false;

  // 联网搜索相关
  bool _searchEnabled = false;
  String _searchApiKey = '';

  // 发送阶段与等待状态跟踪
  SendingStage _sendingStage = SendingStage.none; // 当前发送阶段
  bool _firstTokenReceived = false;               // 是否已收到首 token
  Timer? _firstTokenTimer;                        // 首 token 超时计时器

  // 全局超时与停滞检测
  Timer? _globalTimeoutTimer;   // 全局超时计时器：整个请求最长持续时间
  Timer? _stallTimer;           // 停滞检测计时器：收到 token 后重置，超时则认为输出停滞
  static const int _globalTimeoutSeconds = 300; // 全局超时：5 分钟
  static const int _stallTimeoutSeconds = 60;   // 停滞超时：60 秒无新 token

  // AI 思考计时相关
  final ElapsedTimerService elapsedTimerService = ElapsedTimerService();
  StreamSubscription<String>? _streamSubscription;
  Completer<void>? _streamCompleter;
  bool _streamUserStopped = false;
  final StorageService _storageService = StorageService();

  // 翻译相关
  final Map<String, String> _translations = {};
  final Set<String> _translatingIds = {};

  // 侧边栏删除模式
  bool _deleteMode = false;
  final Set<String> _selectedForDelete = {};

  // ----- Getter -----
  /// 当前会话的消息列表
  List<ChatMessage> get messages =>
      _conversations[_currentConversationId] ?? [];

  List<ModelInfo> get availableModels => _availableModels;
  String get selectedModel => _selectedModel;
  bool get isLoading => _isLoading;
  bool get isStreaming => _isStreaming;
  /// 是否正在工作（加载中或流式输出中），UI 应据此禁用发送按钮
  bool get isBusy => _isLoading || _isStreaming;
  bool get streamEnabled => _streamEnabled;
  String? get errorMessage => _errorMessage;
  String get apiHost => _apiHost;
  String get apiPort => _apiPort;
  String get apiKey => _apiKey;
  String get connectionMode => _connectionMode;
  String get tunnelUrl => _tunnelUrl;
  bool get isConnected => _isConnected;
  bool get checkingConnection => _checkingConnection;
  int get elapsedSeconds => elapsedTimerService.elapsedSeconds;
  bool get searchEnabled => _searchEnabled;
  String get searchApiKey => _searchApiKey;
  /// 当前发送阶段（搜索中 / 加载中 / 生成中…）
  SendingStage get sendingStage => _sendingStage;

  // ----- 多会话 Getter -----
  /// 当前会话ID
  String get currentConversationId => _currentConversationId;
  /// 所有会话ID的有序列表
  List<String> get conversationOrder => List.unmodifiable(_conversationOrder);
  /// 删除模式是否开启
  bool get deleteMode => _deleteMode;
  /// 待删除的会话ID集合
  Set<String> get selectedForDelete => _selectedForDelete;

  /// 获取会话的标题（取第一条用户消息或第一条消息的前20字）
  String getConversationTitle(String convId) {
    final msgs = _conversations[convId] ?? [];
    if (msgs.isEmpty) return '新对话';
    final firstUserMsg = msgs.where((m) => m.isUser).firstOrNull;
    final text = firstUserMsg?.content ?? msgs.first.content;
    return text.length > 20 ? '${text.substring(0, 20)}...' : text;
  }

  // ----- 翻译相关 Getter -----
  String? getTranslation(String messageId) => _translations[messageId];
  bool isTranslating(String messageId) => _translatingIds.contains(messageId);

  // ----- 测试辅助方法 -----
  void setHttpClient(http.Client client) {
    _apiService.httpClient = client;
  }

  void setConnected(bool value) {
    _isConnected = value;
  }

  // ----- 多会话操作 -----
  /// 初始化 - 从本地存储加载配置、会话和聊天记录
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiHost = prefs.getString(AppConfig.keyApiHost) ?? AppConfig.defaultHost;
    _apiPort = prefs.getString(AppConfig.keyApiPort) ?? AppConfig.defaultPort;
    _selectedModel = prefs.getString(AppConfig.keySelectedModel) ?? _selectedModel;
    _connectionMode = prefs.getString(AppConfig.keyConnectionMode) ?? AppConfig.modeLan;
    _tunnelUrl = prefs.getString(AppConfig.keyTunnelUrl) ?? AppConfig.defaultTunnelUrl;
    _streamEnabled = prefs.getBool(AppConfig.keyStreamEnabled) ?? true;
    _searchApiKey = prefs.getString(AppConfig.keySearchApiKey) ?? AppConfig.defaultSearchApiKey;

    _initApiService();
    _initWebSearchService();

    // 从本地加载多会话数据
    final conversations = await _storageService.loadConversations();
    if (conversations.isNotEmpty) {
      _conversations.addAll(conversations);
    }

    final order = await _storageService.loadConversationOrder();
    if (order.isNotEmpty) {
      _conversationOrder = order.where((id) => _conversations.containsKey(id)).toList();
    }

    // 确保至少有一个会话
    if (_conversations.isEmpty) {
      _conversations['default'] = [];
      _conversationOrder = ['default'];
    }

    // 确保当前会话ID有效
    if (!_conversations.containsKey(_currentConversationId)) {
      _currentConversationId = _conversationOrder.first;
    }

    debugPrint('[Provider] 已恢复 ${_conversations.length} 个会话, 当前: $_currentConversationId');
  }

  /// 创建新会话
  void createNewConversation() {
    final id = 'conv_${DateTime.now().millisecondsSinceEpoch}';
    _conversations[id] = [];
    _conversationOrder.insert(0, id);
    _currentConversationId = id;
    _errorMessage = null;
    _translations.clear();
    _translatingIds.clear();
    _saveConversations();
    notifyListeners();
  }

  /// 切换到指定会话
  void switchConversation(String convId) {
    if (!_conversations.containsKey(convId) || convId == _currentConversationId) return;
    // 如果正在流式输出，先停止
    if (_isStreaming) stopStreaming();
    _currentConversationId = convId;
    _errorMessage = null;
    _translations.clear();
    _translatingIds.clear();
    notifyListeners();
  }

  /// 切换删除模式
  void toggleDeleteMode() {
    _deleteMode = !_deleteMode;
    if (!_deleteMode) _selectedForDelete.clear();
    notifyListeners();
  }

  /// 切换会话选中状态（删除模式下）
  void toggleConversationSelection(String convId) {
    if (_selectedForDelete.contains(convId)) {
      _selectedForDelete.remove(convId);
    } else {
      _selectedForDelete.add(convId);
    }
    notifyListeners();
  }

  /// 删除选中的会话
  Future<void> deleteSelectedConversations() async {
    if (_selectedForDelete.isEmpty) return;

    for (final id in _selectedForDelete) {
      _conversations.remove(id);
      _conversationOrder.remove(id);
    }

    // 如果删除了当前会话，切换到第一个可用会话
    if (!_conversations.containsKey(_currentConversationId)) {
      _currentConversationId =
          _conversationOrder.isNotEmpty ? _conversationOrder.first : 'default';
      if (!_conversations.containsKey(_currentConversationId)) {
        _conversations[_currentConversationId] = [];
        _conversationOrder.add(_currentConversationId);
      }
    }

    _selectedForDelete.clear();
    _deleteMode = false;
    _translations.clear();
    _translatingIds.clear();
    await _saveConversations();
    notifyListeners();
  }

  /// 后台保存所有会话（不触发 notifyListeners）
  Future<void> _saveConversations() async {
    await _storageService.saveConversations(_conversations, _conversationOrder);
  }

  void _initApiService() {
    _apiService = ApiService(
      host: _apiHost,
      port: _apiPort,
      apiKey: _apiKey,
      connectionMode: _connectionMode,
      tunnelUrl: _tunnelUrl,
    );
  }

  void _initWebSearchService() {
    _webSearchService = WebSearchService(apiKey: _searchApiKey);
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.keyApiHost, _apiHost);
    await prefs.setString(AppConfig.keyApiPort, _apiPort);
    await prefs.setString(AppConfig.keySelectedModel, _selectedModel);
    await prefs.setString(AppConfig.keyConnectionMode, _connectionMode);
    await prefs.setString(AppConfig.keyTunnelUrl, _tunnelUrl);
    await prefs.setBool(AppConfig.keyStreamEnabled, _streamEnabled);
    await prefs.setString(AppConfig.keySearchApiKey, _searchApiKey);
  }

  Future<void> updateConfig({
    required String host,
    required String port,
    required String key,
    required String connectionMode,
    required String tunnelUrl,
    required bool streamEnabled,
    String? searchApiKey,
  }) async {
    _apiHost = host;
    _apiPort = port;
    _apiKey = key;
    _connectionMode = connectionMode;
    _tunnelUrl = tunnelUrl;
    _streamEnabled = streamEnabled;
    if (searchApiKey != null) {
      _searchApiKey = searchApiKey;
      _webSearchService.updateApiKey(_searchApiKey);
    }

    _initApiService();
    await _saveConfig();
    notifyListeners();
  }

  void toggleSearch() {
    _searchEnabled = !_searchEnabled;
    notifyListeners();
  }

  Future<void> selectModel(String modelId) async {
    _selectedModel = modelId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConfig.keySelectedModel, modelId);
    notifyListeners();
  }

  Future<void> fetchModels() async {
    _errorMessage = null;
    try {
      _availableModels = await _apiService.fetchModels();
      if (_availableModels.isNotEmpty &&
          !_availableModels.any((m) => m.id == _selectedModel)) {
        _selectedModel = _availableModels.first.id;
        await _saveConfig();
      }
      notifyListeners();
    } catch (e) {
      _errorMessage = '获取模型列表失败: $e';
      notifyListeners();
    }
  }

  Future<bool> testConnection() async {
    try {
      return await _apiService.testConnection();
    } catch (e) {
      return false;
    }
  }

  Future<void> checkConnection() async {
    _checkingConnection = true;
    notifyListeners();
    try {
      _isConnected = await _apiService.testConnection();
    } catch (e) {
      _isConnected = false;
    }
    _checkingConnection = false;
    notifyListeners();
  }

  Future<void> refreshModelsAndConnection() async {
    _checkingConnection = true;
    notifyListeners();
    try {
      _availableModels = await _apiService.fetchModels();
      _isConnected = true;
      if (_availableModels.isNotEmpty &&
          !_availableModels.any((m) => m.id == _selectedModel)) {
        _selectedModel = _availableModels.first.id;
        await _saveConfig();
      }
    } catch (e) {
      _isConnected = false;
    }
    _checkingConnection = false;
    notifyListeners();
  }

  void _startThinkTimer() {
    elapsedTimerService.start();
  }

  double _stopThinkTimer() {
    return elapsedTimerService.stop();
  }

  Future<void> _safeWakelockDisable() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  void _cancelPreviousStream() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _streamCompleter = null;
    _cancelAllTimers();
  }

  /// 取消所有计时器（首 token 超时、全局超时、停滞检测）
  void _cancelAllTimers() {
    _firstTokenTimer?.cancel();
    _firstTokenTimer = null;
    _globalTimeoutTimer?.cancel();
    _globalTimeoutTimer = null;
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  /// 启动全局超时计时器
  /// 超过最大时长后强制停止请求，防止电脑端模型持续运行造成损害
  void _startGlobalTimeout() {
    _globalTimeoutTimer?.cancel();
    _globalTimeoutTimer = Timer(Duration(seconds: _globalTimeoutSeconds), () {
      debugPrint('[Provider] 全局超时（$_globalTimeoutSeconds秒），强制停止请求');
      _errorMessage = 'AI 响应超时（${_globalTimeoutSeconds ~/ 60} 分钟），已自动停止以保护设备';
      stopStreaming();
    });
  }

  /// 重置停滞检测计时器
  /// 每收到一个 token 时调用，如果长时间无新 token 则自动停止
  void _resetStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(Duration(seconds: _stallTimeoutSeconds), () {
      debugPrint('[Provider] 输出停滞（$_stallTimeoutSeconds秒无新 token），自动停止');
      _errorMessage = 'AI 输出停滞（$_stallTimeoutSeconds秒无新内容），已自动停止以保护设备';
      stopStreaming();
    });
  }

  /// 发送消息 - 核心方法
  /// 支持联网搜索与 AI 调用并行、发送阶段跟踪、首 token 超时提示
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty) return;

    _cancelPreviousStream();

    final convMsgs = _conversations[_currentConversationId] ?? [];
    final userMessage = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      conversationId: _currentConversationId,
      role: MessageRole.user,
      content: content.trim(),
    );
    convMsgs.add(userMessage);
    _errorMessage = null;
    _firstTokenReceived = false;

    // 根据是否开启搜索设置初始阶段
    _sendingStage = _searchEnabled ? SendingStage.searching : SendingStage.loadingModel;
    _isLoading = true;
    // 启动全局超时计时器：超过最大时长后强制停止，保护电脑端模型
    _startGlobalTimeout();
    notifyListeners();

    try {
      // 并行搜索：搜索和 AI 调用同时启动，搜索最多等 2.5 秒，不阻塞 AI
      String? searchContext;
      if (_searchEnabled) {
        try {
          searchContext = await _webSearchService
              .search(content.trim())
              .timeout(const Duration(milliseconds: 2500));
        } on TimeoutException {
          debugPrint('[Provider] 搜索未在 2.5 秒内完成，AI 调用继续');
        } catch (e) {
          // 搜索异常（如 API 返回格式错误等）不阻断 AI 调用，仅记录日志
          debugPrint('[Provider] 搜索异常，AI 调用继续: $e');
        }

        // 搜索阶段结束，切换到等待模型加载
        _sendingStage = SendingStage.loadingModel;
        notifyListeners();
      }

      // 搜索结果出错时不阻断 AI 调用，仅记录日志
      if (searchContext != null && searchContext.startsWith('⚠️')) {
        debugPrint('[Provider] 搜索失败，继续使用 AI 模型回复: $searchContext');
        searchContext = null;
      }

      // 构建 API 消息（如果搜索完成则注入上下文）
      final apiMessages = _buildApiMessages(userMessage, searchContext);

      if (_streamEnabled) {
        await _sendStreamingMessage(apiMessages);
      } else {
        await _sendNormalMessage(apiMessages);
      }

      _sendingStage = SendingStage.none;
      await _saveConversations();
    } catch (e) {
      _stopThinkTimer();
      _cancelAllTimers();
      _isLoading = false;
      _isStreaming = false;
      _sendingStage = SendingStage.none;
      _safeWakelockDisable();
      _cancelPreviousStream();
      _errorMessage = '发送消息失败: $e';
      notifyListeners();
    }
  }

  List<ChatMessage> _buildApiMessages(ChatMessage userMessage, String? searchContext) {
    final convMsgs = _conversations[_currentConversationId] ?? [];
    if (searchContext == null) return List.from(convMsgs);

    final searchSystemMessage = ChatMessage(
      id: 'search_ctx_${DateTime.now().millisecondsSinceEpoch.toString()}',
      conversationId: _currentConversationId,
      role: MessageRole.system,
      content: searchContext,
    );
    return [
      ...convMsgs.where((m) => m.id != userMessage.id),
      searchSystemMessage,
      userMessage,
    ];
  }

  Future<void> _sendStreamingMessage(List<ChatMessage> apiMessages) async {
    final convMsgs = _conversations[_currentConversationId] ?? [];

    final aiMessage = ChatMessage(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch.toString()}',
      conversationId: _currentConversationId,
      role: MessageRole.assistant,
      content: '',
      isStreaming: true,
    );
    convMsgs.add(aiMessage);
    _isLoading = false;
    _isStreaming = true;
    _startThinkTimer();
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    notifyListeners();

    // 启动首 token 超时计时器（25 秒内没有收到任何 token 则提示超时）
    _firstTokenReceived = false;
    _firstTokenTimer?.cancel();
    _firstTokenTimer = Timer(const Duration(seconds: 25), () {
      if (!_firstTokenReceived) {
        _sendingStage = SendingStage.timeout;
        notifyListeners();
      }
    });

    // 启动停滞检测计时器：收到每个 token 后重置，超时则自动停止
    _resetStallTimer();

    final buffer = StringBuffer();
    final aiIndex = convMsgs.length - 1;
    bool completedNormally = false;
    String? streamError;

    _streamUserStopped = false;

    _streamCompleter = Completer<void>();
    _streamSubscription = _apiService
        .sendChatStream(
          messages: apiMessages,
          model: _selectedModel,
          // 首 token 回调：取消超时计时器，切换到生成阶段
          onFirstToken: () {
            _firstTokenReceived = true;
            _firstTokenTimer?.cancel();
            _firstTokenTimer = null;
            _sendingStage = SendingStage.generating;
            notifyListeners();
          },
        )
        .listen(
          (chunk) {
            buffer.write(chunk);
            convMsgs[aiIndex] = convMsgs[aiIndex].copyWith(
              content: buffer.toString(),
            );
            // 每收到一个 token，重置停滞检测计时器
            _resetStallTimer();
            notifyListeners();
          },
          onDone: () {
            completedNormally = true;
            _cancelAllTimers();
            try { _streamCompleter?.complete(); } catch (_) {}
          },
          onError: (e) {
            streamError = e.toString();
            completedNormally = false;
            _cancelAllTimers();
            try { _streamCompleter?.complete(); } catch (_) {}
          },
          cancelOnError: false,
        );

    await _streamCompleter!.future;
    _streamSubscription = null;
    _streamCompleter = null;

    if (_streamUserStopped) {
      _cancelAllTimers();
      _isStreaming = false;
      _safeWakelockDisable();
      notifyListeners();
      return;
    }

    if (completedNormally && streamError == null) {
      final totalTime = _stopThinkTimer();
      convMsgs[aiIndex] = convMsgs[aiIndex].copyWith(
        isStreaming: false,
        thinkTimeSeconds: totalTime,
      );
    } else if (streamError != null) {
      final totalTime = _stopThinkTimer();
      final friendlyError = _friendlyError(streamError!);
      if (buffer.isEmpty) {
        convMsgs[aiIndex] = convMsgs[aiIndex].copyWith(
          content: friendlyError,
          isStreaming: false,
          thinkTimeSeconds: totalTime,
        );
      } else {
        convMsgs[aiIndex] = convMsgs[aiIndex].copyWith(
          content: '${buffer.toString()}\n\n---\n⚠️ $friendlyError',
          isStreaming: false,
          thinkTimeSeconds: totalTime,
        );
      }
    }
    _isStreaming = false;
    _safeWakelockDisable();
    notifyListeners();
  }

  Future<void> _sendNormalMessage(List<ChatMessage> apiMessages) async {
    final convMsgs = _conversations[_currentConversationId] ?? [];

    _startThinkTimer();
    final response = await _apiService.sendChat(
      messages: apiMessages,
      model: _selectedModel,
    );
    final totalTime = _stopThinkTimer();

    final aiMessage = ChatMessage(
      id: 'ai_${DateTime.now().millisecondsSinceEpoch.toString()}',
      conversationId: _currentConversationId,
      role: MessageRole.assistant,
      content: response,
      thinkTimeSeconds: totalTime,
    );
    convMsgs.add(aiMessage);
    _isLoading = false;
    notifyListeners();
  }

  void stopStreaming() {
    if (!_isStreaming && !_isLoading) return;

    _streamUserStopped = true;
    _streamSubscription?.cancel();
    _streamSubscription = null;

    if (_streamCompleter != null && !_streamCompleter!.isCompleted) {
      _streamCompleter!.complete();
    }

    _cancelAllTimers();

    final totalTime = _stopThinkTimer();
    final convMsgs = _conversations[_currentConversationId] ?? [];
    if (convMsgs.isNotEmpty && convMsgs.last.isStreaming) {
      final lastIndex = convMsgs.length - 1;
      convMsgs[lastIndex] = convMsgs[lastIndex].copyWith(
        isStreaming: false,
        thinkTimeSeconds: totalTime,
      );
    }
    _isLoading = false;
    _isStreaming = false;
    _sendingStage = SendingStage.none;
    _safeWakelockDisable();
    notifyListeners();
  }

  String _friendlyError(String msg) {
    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'AI 响应超时，请检查网络或模型状态后重试';
    }
    if (msg.contains('SocketException') || msg.contains('Connection refused')) {
      return '无法连接到服务器，请检查连接状态';
    }
    if (msg.contains('HandshakeException') || msg.contains('TLS')) {
      return 'SSL/TLS 连接错误，请检查隧道地址是否使用 https';
    }
    return 'AI 回复中断: $msg';
  }

  // ----- 翻译 -----
  Future<String> translateMessage(String messageId, String content) async {
    if (_translations.containsKey(messageId)) {
      return _translations[messageId]!;
    }

    _translatingIds.add(messageId);
    notifyListeners();

    try {
      final result = await _apiService.translate(content, _selectedModel);
      _translations[messageId] = result;
      return result;
    } catch (e) {
      return '翻译失败: $e';
    } finally {
      _translatingIds.remove(messageId);
      notifyListeners();
    }
  }

  /// 清空当前会话的消息
  Future<void> clearCurrentConversation() async {
    if (_isStreaming) stopStreaming();
    _conversations[_currentConversationId] = [];
    _errorMessage = null;
    _stopThinkTimer();
    _firstTokenTimer?.cancel();
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _streamCompleter = null;
    _sendingStage = SendingStage.none;
    await _safeWakelockDisable();
    _translations.clear();
    _translatingIds.clear();
    await _saveConversations();
    notifyListeners();
  }

  /// 完整清空所有会话（原 clearMessages 替代）
  Future<void> clearMessages() async {
    if (_isStreaming) stopStreaming();
    _conversations.clear();
    _conversationOrder.clear();
    _translations.clear();
    _translatingIds.clear();
    // 重建默认会话
    _conversations['default'] = [];
    _conversationOrder = ['default'];
    _currentConversationId = 'default';
    _errorMessage = null;
    _stopThinkTimer();
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _streamCompleter = null;
    await _safeWakelockDisable();
    await _storageService.clearAll();
    notifyListeners();
  }

  @override
  void dispose() {
    elapsedTimerService.dispose();
    _streamSubscription?.cancel();
    _cancelAllTimers();
    _safeWakelockDisable();
    super.dispose();
  }
}
