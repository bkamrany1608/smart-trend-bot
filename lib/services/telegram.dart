import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class Telegram {
  final String token, chat;
  Telegram(this.token, this.chat);
  bool get ok => token.isNotEmpty && chat.isNotEmpty;

  Future<bool> send(String text) async {
    if (!ok) return false;
    try {
      final r = await http
          .post(Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
              body: {'chat_id': chat, 'text': text.length > 3900 ? text.substring(0, 3900) : text})
          .timeout(const Duration(seconds: 15));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendFile(String path, {String caption = ''}) async {
    if (!ok) return false;
    try {
      final req = http.MultipartRequest('POST', Uri.parse('https://api.telegram.org/bot$token/sendDocument'))
        ..fields['chat_id'] = chat
        ..fields['caption'] = caption
        ..files.add(await http.MultipartFile.fromPath('document', path));
      final r = await req.send().timeout(const Duration(seconds: 60));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
