import 'package:flutter_test/flutter_test.dart';
import 'package:student_app/models/grade.dart';

void main() {
  group('Grade.fromJson', () {
    test('parses the grades API response fields and percentage', () {
      final grade = Grade.fromJson({
        'type': 'assignment',
        'id': 42,
        'sync_uuid': 'submission-sync-id',
        'title': 'Science Report',
        'subject_id': 7,
        'subject': 'Science 7',
        'class_id': 12,
        'class': 'Grade 7 - B',
        'score': 7,
        'max_score': 10,
        'percentage': 70,
        'graded_at': '2026-10-09T01:00:00.000000Z',
        'feedback': 'Clear explanation.',
      });

      expect(grade.id, '42');
      expect(grade.type, 'assignment');
      expect(grade.title, 'Science Report');
      expect(grade.subject, 'Science 7');
      expect(grade.className, 'Grade 7 - B');
      expect(grade.score, 7);
      expect(grade.maxScore, 10);
      expect(grade.percentage, 70);
      expect(grade.feedback, 'Clear explanation.');
      expect(grade.syncUuid, 'submission-sync-id');
      expect(grade.gradedAt, DateTime.parse('2026-10-09T01:00:00.000000Z'));
    });

    test('computes percentage and round-trips nullable cached fields', () {
      final grade = Grade.fromJson({
        'type': 'quiz',
        'id': 11,
        'title': 'Quiz #1',
        'subject': {'id': 3, 'name': 'Mathematics 7'},
        'class': {'id': 4, 'display_name': 'Grade 7 - A'},
        'score': 3,
        'max_score': 4,
        'graded_at': null,
        'feedback': null,
      });

      final restored = Grade.fromJson(grade.toJson());
      expect(restored.subject, 'Mathematics 7');
      expect(restored.className, 'Grade 7 - A');
      expect(restored.percentage, 75);
      expect(restored.gradedAt, isNull);
      expect(restored.feedback, isNull);
    });

    test(
      'rejects malformed grade records rather than treating them as empty',
      () {
        expect(
          () => Grade.fromJson({'type': 'quiz', 'title': 'Missing ID'}),
          throwsFormatException,
        );
        expect(
          () => Grade.fromJson({
            'id': 1,
            'title': 'Invalid score',
            'score': 'not-a-number',
          }),
          throwsFormatException,
        );
      },
    );
  });
}
