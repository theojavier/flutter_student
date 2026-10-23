// Conditional export - automatically chooses mobile or web implementation
export 'secure_storage_mobile.dart'
    if (dart.library.js_interop) 'secure_storage_web.dart';
