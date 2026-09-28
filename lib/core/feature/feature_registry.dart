import 'debug_feature.dart';

/// 调试功能注册表 —— 整个应用的功能扩展点。
class FeatureRegistry {
  final List<DebugFeature> _features = [];

  /// 已注册的功能（按注册顺序）。
  List<DebugFeature> get features => List.unmodifiable(_features);

  /// 注册一个功能；重复 id 会被忽略。
  void register(DebugFeature feature) {
    if (_features.any((f) => f.id == feature.id)) return;
    _features.add(feature);
  }

  /// 按 id 查找功能。
  DebugFeature? findById(String id) {
    for (final f in _features) {
      if (f.id == id) return f;
    }
    return null;
  }
}
