export 'blob_store_stub.dart' show PlatformBlobStore;
export 'blob_store_stub.dart'
    if (dart.library.io) 'blob_store_io.dart'
    if (dart.library.js_interop) 'blob_store_web.dart';
