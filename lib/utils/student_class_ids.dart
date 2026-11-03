List<String> studentClassIdsFromProfile(Map<String, dynamic>? profile) {
  if (profile == null) return const [];

  final classIds = <String>{};

  void addClassId(dynamic value) {
    final id = (value ?? '').toString().trim();
    if (id.isNotEmpty) classIds.add(id);
  }

  addClassId(profile['classId']);

  final rawClassIds = profile['classIds'];
  if (rawClassIds is List) {
    for (final id in rawClassIds) {
      addClassId(id);
    }
  }

  return classIds.toList();
}
