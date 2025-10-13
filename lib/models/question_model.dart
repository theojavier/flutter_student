import 'package:cloud_firestore/cloud_firestore.dart';

class QuestionModel {
  final String id; // ✅ Firestore document ID
  final String questionText;
  final String type; // multiple-choice, true-false, matching
  final List<String>? options;
  final dynamic correctAnswer; // String or List<String>

  QuestionModel({
    required this.id, // ✅ require ID
    required this.questionText,
    required this.type,
    this.options,
    this.correctAnswer,
  });

  /// ✅ Construct from plain map (used when ID is already known)
  factory QuestionModel.fromMap(String id, Map<String, dynamic> data) {
    final rawOptions = data["options"];
    List<String>? options;
    if (rawOptions is List) {
      options = rawOptions.map((e) => e.toString()).toList();
    }
    return QuestionModel(
      id: id, // assign ID
      questionText: data["questionText"] ?? "",
      type: data["type"] ?? "",
      options: options,
      correctAnswer: data["correctAnswer"],
    );
  }

  /// ✅ Construct directly from Firestore DocumentSnapshot
  factory QuestionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return QuestionModel.fromMap(doc.id, data); // pass doc.id
  }

  /// ✅ Convert to map (for saving to Firestore)
  Map<String, dynamic> toMap() {
    return {
      "questionText": questionText,
      "type": type,
      "options": options,
      "correctAnswer": correctAnswer,
    };
  }
}
