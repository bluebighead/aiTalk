import 'package:flutter_test/flutter_test.dart';
import 'package:ai_talk/models/model_info.dart';

void main() {
  group('ModelInfo 模型解析测试', () {
    test('从 JSON 解析完整数据', () {
      final json = {
        'id': 'llama3.1',
        'name': 'Llama 3.1',
        'object': 'model',
        'created': 1234567890,
      };

      final model = ModelInfo.fromJson(json);

      expect(model.id, 'llama3.1');
      expect(model.name, 'Llama 3.1');
    });

    test('name 缺失时回退为 id', () {
      final json = {
        'id': 'qwen2.5',
        'object': 'model',
      };

      final model = ModelInfo.fromJson(json);

      expect(model.id, 'qwen2.5');
      expect(model.name, 'qwen2.5'); // 回退为 id
    });

    test('name 为空字符串时仍回退为 id', () {
      final json = {
        'id': 'gemma2:2b',
        'name': '',
        'object': 'model',
      };

      final model = ModelInfo.fromJson(json);

      expect(model.id, 'gemma2:2b');
      expect(model.name, 'gemma2:2b'); // 空字符串回退
    });

    test('所有字段都正确赋值', () {
      final json = {
        'id': 'dzgg/Qwen3.5-Uncensored-HauhauCS-Aggressive:4b',
        'name': 'dzgg/Qwen3.5-Uncensored-HauhauCS-Aggressive:4b',
      };

      final model = ModelInfo.fromJson(json);

      expect(model.id,
          'dzgg/Qwen3.5-Uncensored-HauhauCS-Aggressive:4b');
      expect(model.name,
          'dzgg/Qwen3.5-Uncensored-HauhauCS-Aggressive:4b');
    });
  });
}
