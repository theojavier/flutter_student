import 'package:flutter/foundation.dart';

class ExamLockState {
  ExamLockState._();

  static final ValueNotifier<bool> isInExam = ValueNotifier<bool>(false);
}