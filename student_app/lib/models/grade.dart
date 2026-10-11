class Grade {
  const Grade({
    required this.id,
    required this.type,
    required this.title,
    required this.subject,
    required this.className,
    required this.score,
    required this.maxScore,
    required this.percentage,
    required this.gradedAt,
    required this.feedback,
    this.syncUuid,
    this.localAttempt = false,
    this.syncState,
  });

  final String id;
  final String type;
  final String title;
  final String? subject;
  final String? className;
  final double? score;
  final double? maxScore;
  final double? percentage;
  final DateTime? gradedAt;
  final String? feedback;
  final String? syncUuid;
  final bool localAttempt;
  final String? syncState;

  factory Grade.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('A grade must be a JSON object.');
    }

    final json = Map<String, dynamic>.from(value);
    final id = json['id']?.toString();
    final title = json['title']?.toString();
    if (id == null || id.isEmpty || title == null || title.isEmpty) {
      throw const FormatException('A grade must include an ID and title.');
    }

    final subjectValue = json['subject'];
    final classValue = json['class'];
    final subject = subjectValue is Map
        ? subjectValue['name']?.toString()
        : subjectValue?.toString() ?? json['subject_name']?.toString();
    final className = classValue is Map
        ? classValue['display_name']?.toString() ??
              classValue['name']?.toString()
        : classValue?.toString() ?? json['class_name']?.toString();
    final score = _gradeNumber(json['score'], 'score');
    final maxScore = _gradeNumber(
      json['max_score'] ?? json['total_points'],
      'max_score',
    );
    final percentage =
        _gradeNumber(json['percentage'], 'percentage') ??
        (score != null && maxScore != null && maxScore > 0
            ? score / maxScore * 100
            : null);
    final gradedAtValue = json['graded_at'] ?? json['gradedAt'];
    final gradedAt = gradedAtValue == null
        ? null
        : DateTime.tryParse(gradedAtValue.toString());
    if (gradedAtValue != null && gradedAt == null) {
      throw const FormatException('A grade has an invalid graded_at date.');
    }

    return Grade(
      id: id,
      type: json['type']?.toString() ?? 'grade',
      title: title,
      subject: subject,
      className: className,
      score: score,
      maxScore: maxScore,
      percentage: percentage,
      gradedAt: gradedAt,
      feedback: json['feedback']?.toString(),
      syncUuid: json['sync_uuid']?.toString(),
      localAttempt: json['local_attempt'] == true,
      syncState: json['sync_state']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'title': title,
    'subject': subject,
    'class': className,
    'score': score,
    'max_score': maxScore,
    'percentage': percentage,
    'graded_at': gradedAt?.toIso8601String(),
    'feedback': feedback,
    'sync_uuid': syncUuid,
    'local_attempt': localAttempt,
    'sync_state': syncState,
  };
}

double? _gradeNumber(Object? value, String field) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final number = double.tryParse(value.toString());
  if (number == null) {
    throw FormatException('A grade has an invalid $field value.');
  }
  return number;
}
