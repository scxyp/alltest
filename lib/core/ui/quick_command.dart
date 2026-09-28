/// 可复用的快捷发送指令。
class QuickCommand {
  QuickCommand({
    required this.id,
    required this.name,
    required this.content,
    this.asHex = false,
  });

  String id;
  String name;
  String content;
  bool asHex;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'content': content,
        'asHex': asHex,
      };

  factory QuickCommand.fromJson(Map<String, dynamic> json) => QuickCommand(
        id: json['id'] as String? ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? '',
        content: json['content'] as String? ?? '',
        asHex: json['asHex'] as bool? ?? false,
      );
}

/// 发送历史记录中的一条。
class SendHistoryItem {
  SendHistoryItem({
    required this.content,
    required this.asHex,
    required this.time,
  });

  final String content;
  final bool asHex;
  final DateTime time;

  Map<String, dynamic> toJson() => {
        'content': content,
        'asHex': asHex,
        'time': time.toIso8601String(),
      };

  factory SendHistoryItem.fromJson(Map<String, dynamic> json) =>
      SendHistoryItem(
        content: json['content'] as String? ?? '',
        asHex: json['asHex'] as bool? ?? false,
        time: DateTime.tryParse(json['time'] as String? ?? '') ??
            DateTime.now(),
      );
}
