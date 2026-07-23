/// Debug-only rebuild counters for Phase 4 validation.
///
/// This library is intentionally not exported by the package entrypoints.
abstract final class MdPlayerRebuildDiagnostics {
  static int _surfaceBuilds = 0;
  static int _controlsBuilds = 0;
  static int _progressBuilds = 0;
  static int _bufferingBuilds = 0;
  static int _qualityBuilds = 0;

  static void surface() => _debug(() => _surfaceBuilds++);
  static void controls() => _debug(() => _controlsBuilds++);
  static void progress() => _debug(() => _progressBuilds++);
  static void buffering() => _debug(() => _bufferingBuilds++);
  static void quality() => _debug(() => _qualityBuilds++);

  static void reset() => _debug(() {
        _surfaceBuilds = 0;
        _controlsBuilds = 0;
        _progressBuilds = 0;
        _bufferingBuilds = 0;
        _qualityBuilds = 0;
      });

  static Map<String, int> snapshot() {
    final Map<String, int> result = <String, int>{};
    assert(_run(() => result.addAll(<String, int>{
          'surface': _surfaceBuilds,
          'controls': _controlsBuilds,
          'progress': _progressBuilds,
          'buffering': _bufferingBuilds,
          'quality': _qualityBuilds,
        })));
    return result;
  }

  static bool _run(void Function() callback) {
    callback();
    return true;
  }

  static void _debug(void Function() callback) {
    assert(_run(callback));
  }
}
