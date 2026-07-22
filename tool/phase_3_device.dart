import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    exitCode = 64;
    return;
  }
  final List<dynamic> devices =
      jsonDecode(await utf8.decoder.bind(stdin).join()) as List<dynamic>;
  final Map<String, dynamic>? selected =
      devices.cast<Map<String, dynamic>?>().firstWhere(
            (Map<String, dynamic>? device) => device?['id'] == arguments.single,
            orElse: () => null,
          );
  if (selected == null) {
    stderr.writeln('Selected device is not connected: ${arguments.single}');
    exitCode = 2;
    return;
  }
  if (!'${selected['targetPlatform']}'.startsWith('android-')) {
    stderr.writeln('Phase 3 cache validation requires an Android device');
    exitCode = 2;
    return;
  }
  stdout.writeln(selected['emulator'] == true ? 'emulator' : 'physical');
}
