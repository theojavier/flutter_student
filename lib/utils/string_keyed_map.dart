Map<String, dynamic>? decodeStringKeyedMap(Object? value) {
  if (value == null) return null;
  if (value is! Map) {
    throw const FormatException('Expected a map with string keys.');
  }

  final decoded = <String, dynamic>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('Expected a map with string keys.');
    }
    decoded[entry.key as String] = entry.value;
  }
  return decoded;
}
