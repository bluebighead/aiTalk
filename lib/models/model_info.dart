/// 模型信息 - 从 API 获取的模型数据
class ModelInfo {
  final String id; // 模型 ID（如 llama3.1）
  final String name; // 模型名称

  ModelInfo({required this.id, required this.name});

  /// 从 JSON 创建（解析 /v1/models 响应）
  /// API 返回的 id 即为模型名，name 可能来自独立的 name 字段或回退为 id
  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    final rawName = json['name'] as String?;
    return ModelInfo(
      id: json['id'] as String,
      name: (rawName != null && rawName.isNotEmpty) ? rawName : json['id'] as String,
    );
  }
}
