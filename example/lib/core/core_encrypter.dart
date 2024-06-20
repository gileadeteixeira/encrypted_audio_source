import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;

class CoreEncrypter {
  static final key = enc.Key.fromUtf8("Vi9CbjJhVkVBcDNv"); //AES-128
  static final iv = enc.IV.fromUtf8("N0poeHJacXV0NFd3");
  // static final key = enc.Key.fromSecureRandom(16); //AES-128
  // static final iv = enc.IV.fromSecureRandom(16);

  static final myEncrypter = enc.Encrypter(
    enc.AES(key, mode: enc.AESMode.ctr, padding: null)
  );

  static final myDecrypter = pc.CTRStreamCipher(pc.AESEngine())
    ..init(false, pc.ParametersWithIV(
      pc.KeyParameter(key.bytes),
      iv.bytes
    ));  

  static List<int> encrypt(List<int> bytes) {
    return myEncrypter.encryptBytes(bytes, iv: iv).bytes;
  }

  static List<int> decrypt(List<int> encryptedBytes) {
    enc.Encrypted en = enc.Encrypted(Uint8List.fromList(encryptedBytes));
    return myDecrypter.process(en.bytes);
  }
}