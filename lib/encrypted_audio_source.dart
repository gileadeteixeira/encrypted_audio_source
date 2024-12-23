library encrypted_audio_source;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mp3_info/mp3_info.dart';
import 'package:rxdart/rxdart.dart';

export 'encrypted_audio_source.dart';

class EncryptedAudioSource extends StreamAudioSource {
  ///Decryption function
  final List<int> Function(List<int> encrypted) _decrypter;

  ///Size of response's body
  int? _sourceLength;

  final String _contentType;

  ///Controller for decrypted bytes stream.
  StreamController<List<int>>? _decryptionController;

  ///The base stream, where encrypted bytes are received. Typically a streamed response
  Stream<List<int>>? _encrytedStream;

  ///Accumulator for decrypted bytes. The [decryptedStream] is internally listened after a delay.
  ///So, to workaround this behavior, the current accumulation will be immediately sent on first listen, and
  ///then the next bytes will be added.
  final List<int> _decryptedBytes = [];

  Stream<List<int>>? get _decryptedStream => _decryptionController?.stream;

  ///Start position for decrypted addition.
  ///Ex.: chunkFirstLength = 100, {startPosition: 0, endPosition: 99}, so next addition will be {startPosition: 100, endPosition: 200}
  int _decryptedOffset = 0;

  StreamController<Duration>? _durationController;
  Stream<Duration>? get totalDurationStream => _durationController?.stream;

  Duration? _totalDuration;
  Duration? get totalDuration => _totalDuration;

  late final Future<StreamedResponse> Function() _generator;

  bool _initialized = false;
  
  EncryptedAudioSource({
    required Future<StreamedResponse> Function() generator,
    required List<int> Function(List<int> encrypted) decrypter,
    String contentType = 'audio/mpeg'
  }) :
    _generator = generator,
    _decrypter = decrypter,
    _contentType = contentType;

  void _addOnController() {
    if (_decryptionController != null) {
      _decryptionController!.add(_decryptedBytes.sublist(_decryptedOffset));
      _decryptedOffset = _decryptedBytes.length;
    }
  }

  Future<void> _finish() async {
    MP3Info info = MP3Processor.fromBytes(Uint8List.fromList(_decryptedBytes));
    _durationController?.add(info.duration);
    _totalDuration = info.duration;

    await Future<void>.delayed(const Duration(milliseconds: 3000));
    _decryptionController?.close();
    _durationController?.close();
    debugPrint("[$EncryptedAudioSource] - Finished");
  }

  Future<void> _initialize() async {
    if (_initialized) return;

    final streamedResponse = await _generator.call();
    
    _sourceLength = streamedResponse.contentLength;

    _encrytedStream ??= streamedResponse.stream
      .doOnData((bytes) {
        final decrypted = _decrypter.call(bytes);
        _decryptedBytes.addAll(decrypted);
      })
      .doOnDone(() => _finish())
      .doOnError((error, stackTrace) async {
        debugPrint("[$EncryptedAudioSource] - Error: ${error.toString()}");
        debugPrint(stackTrace.toString());
        await _finish();
      })
      .asBroadcastStream();

    _decryptionController ??= StreamController<List<int>>.broadcast(
      onListen: () {
        if (_decryptedBytes.isNotEmpty && _decryptedOffset == 0) {
          _addOnController();
        }

        _encrytedStream?.listen((bytes) {
          _addOnController();
        });
      },
    );

    _durationController ??= StreamController<Duration>.broadcast();

    _initialized = false;
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    await _initialize();

    // final length = _sourceLength ?? _decryptedBytes.length;
    final length = _decryptedBytes.length;

    start ??= 0;
    end ??= length;

    return StreamAudioResponse(
      sourceLength: length,
      // contentLength: end - start,
      contentLength: -1,
      // offset: start,
      offset: null,
      // stream: _decryptedStream,
      stream: _decryptedBytes.isEmpty
        ? _decryptedStream!
        : (Platform.isIOS ? _decryptedStream! : Stream.value(_decryptedBytes.sublist(start, end))),
      contentType: _contentType,
    );
  }
}
