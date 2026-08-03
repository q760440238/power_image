import 'package:flutter/widgets.dart';

/// Backwards-compatible binding that now uses Flutter's standard [ImageCache].
///
/// PowerImage no longer requires applications to install a process-wide custom
/// image cache. New applications can call [WidgetsFlutterBinding.ensureInitialized]
/// directly and omit this class.
@Deprecated('PowerImage no longer requires a custom binding.')
class PowerImageBinding extends WidgetsFlutterBinding {}
