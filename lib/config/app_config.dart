/// aiTalk 应用配置常量
/// 包含默认值、SharedPreferences 键名等
class AppConfig {
  // 默认 Ollama 连接配置
  static const String defaultHost = '192.168.31.13'; // 默认局域网 IP
  static const String defaultPort = '11434'; // Ollama 默认端口

  // 默认内网穿透地址（无默认值，由用户在设置页面输入）
  static const String defaultTunnelUrl = '';

  // SharedPreferences 存储 Key
  static const String keyApiHost = 'api_host';
  static const String keyApiPort = 'api_port';
  static const String keySelectedModel = 'selected_model';
  static const String keyConnectionMode = 'connection_mode';
  static const String keyTunnelUrl = 'tunnel_url';
  static const String keyStreamEnabled = 'stream_enabled';
  static const String keySearchApiKey = 'search_api_key'; // 搜索 API Key

  // 默认 Tavily Search API Key（无默认值，由用户在设置页面输入）
  static const String defaultSearchApiKey = '';

  // 连接模式
  static const String modeLan = 'lan';
  static const String modeTunnel = 'tunnel';
}
