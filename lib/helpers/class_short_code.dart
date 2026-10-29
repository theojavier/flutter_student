String classShortCode(String classCode, String subject) {
  const fillerWords = {'of', 'and', 'the', 'in', 'to', 'for', 'a'};
  final words = subject
      .trim()
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .where((word) => !fillerWords.contains(word.toLowerCase()))
      .toList();

  if (words.isEmpty) return classCode;

  final suffix = words.length >= 2 && words.length <= 4
      ? words.map((word) => word[0].toUpperCase()).join()
      : words.first.length > 6
      ? words.first.substring(0, 4).toUpperCase()
      : words.first.toUpperCase();

  return '$classCode-$suffix';
}
