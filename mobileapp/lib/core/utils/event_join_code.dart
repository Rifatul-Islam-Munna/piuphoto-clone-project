/// Accepts a code or a planner invitation link.
String normalizeEventJoinCode(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return '';

  final linkCode = RegExp(
    r'(?:[/#]join/|[?&]code=)([a-zA-Z0-9]{6,32})(?:$|[/?#&])',
    caseSensitive: false,
  ).firstMatch(raw);
  if (linkCode != null) return linkCode.group(1)!.toUpperCase();

  return raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

bool isValidEventJoinCode(String code) =>
    RegExp(r'^[A-Z0-9]{6,32}$').hasMatch(code);
