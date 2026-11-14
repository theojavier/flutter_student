import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FaceIdentityStorage {
  static const _maxPhotoBytes = 2 * 1024 * 1024;
  static const _referencePath = 'face-references';

  static Reference _referenceForCurrentUser() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('Sign in before setting up face verification.');
    }
    return FirebaseStorage.instance.ref().child(
      '$_referencePath/$uid/reference.jpg',
    );
  }

  static Future<dynamic> handleAction(
    String action,
    Map<String, dynamic> data,
  ) async {
    final reference = _referenceForCurrentUser();
    switch (action) {
      case 'getFaceReference':
        try {
          final metadata = await reference.getMetadata();
          final bytes = await reference.getData(_maxPhotoBytes);
          if (bytes == null || bytes.isEmpty) {
            throw StateError('The saved face reference could not be read.');
          }
          return {
            'exists': true,
            'jpegBase64': base64Encode(bytes),
            'createdAt': metadata.timeCreated?.toIso8601String(),
          };
        } on FirebaseException catch (error) {
          if (error.code == 'object-not-found') {
            return const {'exists': false};
          }
          rethrow;
        }

      case 'saveFaceReference':
        final encodedPhoto = data['jpegBase64'];
        if (encodedPhoto is! String || encodedPhoto.isEmpty) {
          throw const FormatException('The face photo is missing.');
        }
        try {
          await reference.getMetadata();
          throw StateError(
            'A face reference already exists and cannot be replaced.',
          );
        } on FirebaseException catch (error) {
          if (error.code != 'object-not-found') rethrow;
        }
        final photoBytes = base64Decode(encodedPhoto);
        if (photoBytes.length > _maxPhotoBytes ||
            photoBytes.length < 3 ||
            photoBytes[0] != 0xff ||
            photoBytes[1] != 0xd8 ||
            photoBytes[2] != 0xff) {
          throw const FormatException('The face photo is invalid.');
        }

        await reference.putData(
          Uint8List.fromList(photoBytes),
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: const {'purpose': 'student-face-verification-v1'},
          ),
        );
        final metadata = await reference.getMetadata();
        return {
          'success': true,
          'createdAt': metadata.timeCreated?.toIso8601String(),
        };

      default:
        throw ArgumentError.value(action, 'action', 'Unknown face action.');
    }
  }
}
