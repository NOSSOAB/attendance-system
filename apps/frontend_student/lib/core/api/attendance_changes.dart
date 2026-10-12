/// Submit only teacher edits. Sending the entire displayed roster can overwrite
/// attendance received since the screen loaded, including late check-ins.
List<Map<String, dynamic>> buildAttendanceChanges({
  required List<Map<String, dynamic>> students,
  required Map<int, Map<String, dynamic>> edits,
}) {
  final changes = <Map<String, dynamic>>[];
  for (final student in students) {
    final id = (student['studentId'] as num?)?.toInt();
    final edit = edits[id];
    if (edit == null) continue;
    final loadedStatus = student['status'] as Map<String, dynamic>?;
    if (edit['status'] == (loadedStatus?['code'] ?? 'ABSENT') &&
        edit['note'] == (student['note'] ?? '')) {
      continue;
    }
    changes.add({
      'studentId': id,
      'recordId': student['recordId'],
      'expectedUpdatedAt': student['updatedAt'],
      'status': edit['status'],
      'note': edit['note'],
    });
  }
  return changes;
}
