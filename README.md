# AI Talk

基于 Flutter 的 AI 聊天客户端，连接本地 Ollama API（或其他 OpenAI 兼容 API），提供流畅的对话体验。

## 主要功能

- **AI 对话** — 支持流式输出（打字机效果），实时显示 AI 回复
- **多会话管理** — 侧边栏管理多个对话，支持新建、切换和清空会话
- **模型切换** — 自动获取 Ollama 可用模型列表，在输入框上方快速切换
- **联网搜索** — 集成 Tavily Search API，开启后 AI 可获取实时搜索结果
- **连接方式** — 支持局域网直连和内网穿透（cpolar / ngrok），适配不同使用场景
- **连接检测** — 一键测试 API 连接状态，顶部状态指示灯实时显示
- **Markdown 渲染** — AI 回复以 Markdown 格式展示，支持代码高亮
- **深色/浅色主题** — 跟随系统主题自动切换

## 快速开始

1. 确保本地已运行 [Ollama](https://ollama.com/)，并配置 `OLLAMA_HOST=0.0.0.0` 监听局域网
2. 通过 `flutter run` 启动应用
3. 在设置页面配置 Ollama API 地址和端口（默认 `192.168.31.13:11434`）
4. 刷新模型列表，选择一个模型开始对话

## 联网搜索（可选）

在设置页面填入 [Tavily](https://app.tavily.com) API Key，即可在输入框左侧开启联网搜索功能。

## 技术栈

- Flutter + Dart
- Provider（状态管理）
- Material 3（Material Design 3）
- Ollama API / OpenAI 兼容 API
- Tavily Search API
