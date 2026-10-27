import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// The user closed the administrator prompt.
class ElevationCancelled implements Exception {
  @override
  String toString() => 'cancelled by the user';
}

/// Starts [exe] with administrator rights in the background: the UAC prompt
/// on Windows, the password prompt on macOS. Returns once the process has
/// been started.
Future<void> runElevated(String exe, List<String> args) async {
  if (Platform.isWindows) {
    _shellExecuteRunAs(exe, args);
  } else if (Platform.isMacOS) {
    await _osascriptAdmin(exe, args);
  } else {
    throw UnsupportedError('administrator mode is not available here');
  }
}

// --- Windows -------------------------------------------------------------

final class _ShellExecuteInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int fMask;
  external Pointer<Void> hwnd;
  external Pointer<Utf16> lpVerb;
  external Pointer<Utf16> lpFile;
  external Pointer<Utf16> lpParameters;
  external Pointer<Utf16> lpDirectory;
  @Int32()
  external int nShow;
  external Pointer<Void> hInstApp;
  external Pointer<Void> lpIDList;
  external Pointer<Utf16> lpClass;
  external Pointer<Void> hkeyClass;
  @Uint32()
  external int dwHotKey;
  external Pointer<Void> hIconOrMonitor;
  external Pointer<Void> hProcess;
}

typedef _ShellExecuteExNative = Int32 Function(Pointer<_ShellExecuteInfo>);
typedef _ShellExecuteExDart = int Function(Pointer<_ShellExecuteInfo>);

const _seeMaskNoCloseProcess = 0x00000040;
const _seeMaskNoAsync = 0x00000100;
const _seeMaskFlagNoUi = 0x00000400;
const _swHide = 0;

/// Quotes one argument the way CommandLineToArgvW reads it back.
String _winQuote(String a) {
  if (a.isNotEmpty && !a.contains(RegExp(r'[\s"]'))) return a;
  final b = StringBuffer('"');
  var slashes = 0;
  for (final ch in a.split('')) {
    if (ch == r'\') {
      slashes++;
    } else if (ch == '"') {
      b.write(r'\' * (slashes * 2 + 1));
      b.write('"');
      slashes = 0;
    } else {
      b.write(r'\' * slashes);
      b.write(ch);
      slashes = 0;
    }
  }
  b.write(r'\' * (slashes * 2));
  b.write('"');
  return b.toString();
}

void _shellExecuteRunAs(String exe, List<String> args) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final shellExecuteEx = shell32
      .lookupFunction<_ShellExecuteExNative, _ShellExecuteExDart>('ShellExecuteExW');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final closeHandle = kernel32.lookupFunction<Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('CloseHandle');

  final info = calloc<_ShellExecuteInfo>();
  final verb = 'runas'.toNativeUtf16();
  final file = exe.toNativeUtf16();
  final params = args.map(_winQuote).join(' ').toNativeUtf16();
  final dir = File(exe).parent.path.toNativeUtf16();
  try {
    info.ref
      ..cbSize = sizeOf<_ShellExecuteInfo>()
      ..fMask = _seeMaskNoCloseProcess | _seeMaskNoAsync | _seeMaskFlagNoUi
      ..lpVerb = verb
      ..lpFile = file
      ..lpParameters = params
      ..lpDirectory = dir
      ..nShow = _swHide;
    if (shellExecuteEx(info) == 0) {
      // Almost always ERROR_CANCELLED: the user said no in the UAC prompt.
      throw ElevationCancelled();
    }
    if (info.ref.hProcess.address != 0) closeHandle(info.ref.hProcess);
  } finally {
    calloc.free(info);
    calloc.free(verb);
    calloc.free(file);
    calloc.free(params);
    calloc.free(dir);
  }
}

// --- macOS ---------------------------------------------------------------

String _shQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

String _appleScriptString(String s) =>
    '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

Future<void> _osascriptAdmin(String exe, List<String> args) async {
  final command =
      '${[exe, ...args].map(_shQuote).join(' ')} > /dev/null 2>&1 &';
  final script =
      'do shell script ${_appleScriptString(command)} with administrator privileges '
      'with prompt ${_appleScriptString('Tek просит пароль, чтобы пустить весь трафик через VPN.')}';
  final result = await Process.run('/usr/bin/osascript', ['-e', script]);
  if (result.exitCode != 0) {
    final err = '${result.stderr}';
    if (err.contains('-128') || err.toLowerCase().contains('cancel')) {
      throw ElevationCancelled();
    }
    throw ProcessException('osascript', const [], err.trim(), result.exitCode);
  }
}
