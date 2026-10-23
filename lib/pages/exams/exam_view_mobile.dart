import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
  static const _origin = 'https://student-099266.web.app';

  late final Future<String> _tokenFuture =
      FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('getExamCustomToken')
          .call({'examId': widget.examId})
          .then((r) => r.data['token'] as String);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _tokenFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('Could not start exam session: ${snap.error}'),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final url =
            '$_origin/assets/exam.html'
            '?examId=${widget.examId}&studentId=${widget.studentId}&platform=mobile';

        return InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(url)),
          initialUserScripts: UnmodifiableListView([
            UserScript(
              source: 'window.__customToken = ${jsonEncode(snap.data)};',
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            ),
          ]),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            allowsInlineMediaPlayback: true,
            cacheEnabled: false,
          ),
          onPermissionRequest: (controller, request) async {
            return PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
          onWebViewCreated: (controller) {
            controller.addJavaScriptHandler(
              handlerName: 'flutterMessage',
              callback: (args) {
                final data = args.isNotEmpty ? args.first : null;
                if (data is! Map) return;
                switch (data['action']) {
                  case 'finishExam':
                    widget.onFinish('${data['examId'] ?? widget.examId}');
                    break;
                  case 'navigate':
                    final path = data['path'];
                    if (path is String && path.isNotEmpty)
                      widget.onNavigate(path);
                    break;
                }
              },
            );
          },
          onConsoleMessage: (c, m) => debugPrint('[exam.html] ${m.message}'),
        );
      },
    );
  }
}
