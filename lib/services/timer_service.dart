import 'dart:async';
import 'package:flutter/foundation.dart';

/// 计时器服务 — 独立于 ChatProvider 的 ChangeNotifier
/// 用于实时更新"思考中"秒数，避免每秒 tick 触发 ChatProvider 全量 rebuild
class ElapsedTimerService extends ChangeNotifier {
  int _elapsedSeconds = 0;
  DateTime? _startTime;
  Timer? _timer;

  /// 当前已过去的秒数
  int get elapsedSeconds => _elapsedSeconds;

  /// 开始计时
  void start() {
    _elapsedSeconds = 0;
    _startTime = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedSeconds = DateTime.now().difference(_startTime!).inSeconds;
      notifyListeners(); // 仅通知计时器监听者，不影响 ChatProvider
    });
  }

  /// 停止计时并返回耗时秒数
  double stop() {
    _timer?.cancel();
    _timer = null;
    _startTime = null;
    final elapsed = _elapsedSeconds.toDouble();
    _elapsedSeconds = 0;
    return elapsed;
  }

  /// 重置
  void reset() {
    _timer?.cancel();
    _timer = null;
    _startTime = null;
    _elapsedSeconds = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
