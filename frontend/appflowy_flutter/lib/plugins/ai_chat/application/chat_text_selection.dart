import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What is selected in the chat right now.
///
/// A chat has two kinds of selectable text with two different selection
/// systems: the person's own messages sit in Flutter's `SelectionArea`, while
/// an answer is rendered by the editor, which runs its own selection service
/// and hides that text from the region around it. Ctrl+C has to work over both,
/// so both report here and the last one to be selected wins.
class ChatTextSelection extends ChangeNotifier {
  ChatTextSelection._();

  static final ChatTextSelection instance = ChatTextSelection._();

  String _text = '';

  String get text => _text;

  bool get hasSelection => _text.trim().isNotEmpty;

  void report(String? text) {
    final value = text ?? '';
    if (value == _text) {
      return;
    }
    _text = value;
    notifyListeners();
  }

  /// Copies whatever is selected. Answers whether there was anything.
  Future<bool> copy() async {
    if (!hasSelection) {
      return false;
    }
    await Clipboard.setData(ClipboardData(text: _text));
    return true;
  }
}
