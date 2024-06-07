library encrypted_audio_source;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

class EncryptedAudioSource extends StreamAudioSource {
  ///Decryption function
  final List<int> Function(List<int> encrypted) _decrypter;

  ///Size of response's body
  final int? _sourceLength;

  final String _contentType;

  ///Controller for decrypted bytes stream.
  late final StreamController<List<int>> _decryptionController;

  ///The base stream, where encrypted bytes are received. Typically a streamed response
  late final Stream<List<int>> _encrytedStream;

  ///Accumulator for decrypted bytes. The [_decryptedStream] is internally listened after a delay.
  ///So, to workaround this behavior, the current accumulation will be immediately sent on first listen, and
  ///then the next bytes will be added.
  final List<int> _decryptedBytes = [];

  Stream<List<int>> get _decryptedStream => _decryptionController.stream;

  ///Start position for decrypted addition.
  ///Ex.: chunkFirstLength = 100, {startPosition: 0, endPosition: 99}, so next addition will be {startPosition: 100, endPosition: 200}
  int _decryptedOffset = 0;
  
  EncryptedAudioSource({
    required Stream<List<int>> encryptedStream,
    required List<int> Function(List<int> encrypted) decrypter,
    int? sourceLength,
    String contentType = 'audio/mpeg'
  }) :
    _sourceLength = sourceLength,
    _decrypter = decrypter,
    _contentType = contentType
  {
    _encrytedStream = encryptedStream
      .doOnData((bytes) {
        final decrypted = _decrypter.call(bytes);
        _decryptedBytes.addAll(decrypted);
      })
      .doOnDone(_closeStream)
      .doOnError((error, stackTrace) async {
        debugPrint(error.toString());
        debugPrint(stackTrace.toString());
        await _closeStream();
      })
      .asBroadcastStream();

    _decryptionController = StreamController<List<int>>.broadcast(
      onListen: () {
        if (_decryptedBytes.isNotEmpty && _decryptedOffset == 0) {
          _addOnController();
        }

        _encrytedStream.listen((bytes) {
          _addOnController();
        });
      },
    );
  }

  void _addOnController() {
    _decryptionController.add(_decryptedBytes.sublist(_decryptedOffset));
    _decryptedOffset = _decryptedBytes.length;
  }

  Future<void> _closeStream() async {
    await Future<void>.delayed(const Duration(milliseconds: 3000));
    _decryptionController.close();
    debugPrint("[$EncryptedAudioSource] - Decryption stream was closed");
  }

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final length = _sourceLength ?? _decryptedBytes.length;

    start ??= 0;
    end ??= length;

    return StreamAudioResponse(
      sourceLength: length,
      // contentLength: end - start,
      contentLength: -1,
      offset: start,
      stream: _decryptedStream,
      contentType: _contentType,
    );
  }
}
