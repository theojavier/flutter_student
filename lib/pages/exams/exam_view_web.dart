import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

class ExamView extends StatefulWidget {
  final String examId;
  final String studentId;
  final void Function(String examId) onFinish;
  final void Function(String path) onNavigate;

  const ExamView({
    super.key,
    required this.examId,
    required this.studentId,
    required this.onFinish,
    required this.onNavigate,
  });

  @override
  State<ExamView> createState() => _ExamViewState();
}

class _ExamViewState extends State<ExamView> {
  static final Set<String> _registered = {};
  StreamSubscription<html.MessageEvent>? _sub;
  late final String _viewType =
      'exam-html-view-${widget.examId}-${widget.studentId}';

  @override
  void initState() {
    super.initState();

    _sub = html.window.onMessage.listen((event) {
      if (!mounted) return;
      final data = event.data;
      if (data is! Map) return;
      switch (data['action']) {
        case 'finishExam':
          widget.onFinish('${data['examId'] ?? widget.examId}');
          break;
        case 'navigate':
          final path = data['path'];
          if (path is String && path.isNotEmpty) widget.onNavigate(path);
          break;
      }
    });

    if (_registered.add(_viewType)) {
      final examId = widget.examId;
      final studentId = widget.studentId;
      ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
        final iframe = html.IFrameElement()
          ..src = '${html.window.location.origin}/assets/exam.html?examId=$examId'
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%'
          ..allow = 'fullscreen; microphone; camera; clipboard-read; clipboard-write';

        iframe.onLoad.listen((_) {
          iframe.contentWindow?.postMessage(
              {'examId': examId, 'studentId': studentId}, '*');
        });
        return iframe;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      HtmlElementView(key: ValueKey(_viewType), viewType: _viewType);
}
