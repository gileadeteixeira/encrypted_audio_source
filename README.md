# encrypted_audio_source 

This extension allows the playback of encrypted audios through [audio_service](https://pub.dev/packages/audio_service) plugin.

## How it works

Basically this is an implementation of `StreamAudioSource`, mentioned in [just_audio documentation](https://pub.dev/packages/just_audio#working-with-stream-audio-sources).

The stream to be listened to will be the encrypted bytes stream. Consequently, a decryption function is needed, which will process and store the decrypted bytes internally.

```dart
encryptedStream.doOnData((encryptedBytes) {
    final List<int> decryptedBytes = _decrypter.call(encryptedBytes);
    _decryptedBytes.addAll(decryptedBytes);
})
```

## Usage

The first step is to define the encryption logic to be implemented. Consider using packages like [pointycastle](https://pub.dev/packages/pointycastle), [encrypt](https://pub.dev/packages/encrypt) or [crypto](https://pub.dev/packages/crypto). Either way, you will need a decryption function to handle the encrypted byte stream.

```dart
class MyEncrypter {
  static List<int> encrypt(List<int> originalBytes) {
    ///
  }

  static List<int> decrypt(List<int> encryptedBytes) {
    ///
  }
}
```

Once this is done, provide a stream of the audio file's encrypted data, and your decrypter to a new `EncryptedAudioSource`. For demonstration purposes, the example was implemented using a `StreamedResponse`.

Then, provide your `EncryptedAudioSource` to your `AudioPlayer`, via `setAudioSource` method.

```dart
// [...]
final player = AudioPlayer();

final Uri uri = Uri.parse("URL_OF_ENCRYPTED_AUDIO");
final http.Request request = http.Request('GET', uri);
final StreamedResponse response = await request.send();
final ByteStream stream = response.stream;

final myCustomSource = EncryptedAudioSource(
    encryptedStream: stream,
    decrypter: MyEncrypter.decrypt
    sourceLength: response.contentLength,
    contentType: 'audio/mpeg'
);

player.setAudioSource(myCustomSource);

/// You can handle the delayed duration result through [myCustomSource.totalDurationStream]

// [...]
```

After all this, you will be able to play your encrypted audios, through the implementation of [audio_service](https://pub.dev/packages/audio_service).
