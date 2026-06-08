import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── AI chat history i18n ───────────────────────────────────────────────────

  group('i18n — AI chat history keys', () {
    const List<String> keys = <String>[
      'newChat', 'noChats', 'renameChat', 'deleteChat',
      'aiChats', 'chatHistory',
    ];

    for (final String key in keys) {
      test('EN "$key" translated', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
      test('CS "$key" translated', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('newChat and noChats are different labels', () {
      lang.value = 'en';
      expect(tr('newChat'), isNot(equals(tr('noChats'))));
    });

    test('renameChat and deleteChat are different labels', () {
      lang.value = 'en';
      expect(tr('renameChat'), isNot(equals(tr('deleteChat'))));
    });

    test('aiChats and chatHistory are different labels', () {
      lang.value = 'en';
      expect(tr('aiChats'), isNot(equals(tr('chatHistory'))));
    });
  });

  // ── Chat has_unread parsing ───────────────────────────────────────────────
  // Mirrors: (chat['has_unread'] as int? ?? 0) == 1

  group('AI chat — has_unread flag parsing', () {
    bool _isUnread(Map<String, dynamic> chat) =>
        (chat['has_unread'] as int? ?? 0) == 1;

    test('has_unread=1 → unread', () {
      expect(_isUnread(<String, dynamic>{'has_unread': 1}), isTrue);
    });

    test('has_unread=0 → not unread', () {
      expect(_isUnread(<String, dynamic>{'has_unread': 0}), isFalse);
    });

    test('missing has_unread → not unread (defaults to 0)', () {
      expect(_isUnread(<String, dynamic>{'title': 'Chat'}), isFalse);
    });

    test('has_unread=null → not unread', () {
      expect(_isUnread(<String, dynamic>{'has_unread': null}), isFalse);
    });

    test('has_unread=2 → not unread (only 1 means unread)', () {
      expect(_isUnread(<String, dynamic>{'has_unread': 2}), isFalse);
    });
  });

  // ── Chat title fallback ───────────────────────────────────────────────────
  // Mirrors: title = chat['title'] as String? ?? 'Chat'

  group('AI chat — title fallback', () {
    String _chatTitle(Map<String, dynamic> chat) =>
        chat['title'] as String? ?? 'Chat';

    test('title present → use it', () {
      expect(_chatTitle(<String, dynamic>{'title': 'Sci-fi films'}),
          'Sci-fi films');
    });

    test('null title → "Chat"', () {
      expect(_chatTitle(<String, dynamic>{'title': null}), 'Chat');
    });

    test('missing title → "Chat"', () {
      expect(_chatTitle(<String, dynamic>{}), 'Chat');
    });
  });

  // ── Auto-title from sendChatMessage response ──────────────────────────────
  // Mirrors: newTitle = response['new_title'] as String?

  group('AI chat — auto-title update', () {
    test('new_title present in response → update title', () {
      final Map<String, dynamic> response = <String, dynamic>{
        'reply': <String, dynamic>{'role': 'assistant', 'content': 'Hi!'},
        'new_title': 'Sci-fi recommendations',
      };
      final String? newTitle = response['new_title'] as String?;
      expect(newTitle, 'Sci-fi recommendations');
    });

    test('no new_title in response → keep existing title', () {
      final Map<String, dynamic> response = <String, dynamic>{
        'reply': <String, dynamic>{'role': 'assistant', 'content': 'Hi!'},
      };
      final String? newTitle = response['new_title'] as String?;
      expect(newTitle, isNull);
    });
  });

  // ── updated_at display truncation ─────────────────────────────────────────
  // Mirrors: (chat['updated_at'] as String? ?? '').replaceFirst('T', ' ').substring(0, 16)

  group('AI chat — updated_at display', () {
    test('ISO timestamp truncated to 16 chars', () {
      const String updatedAt = '2026-06-08T14:30:00Z';
      final String display =
          updatedAt.replaceFirst('T', ' ').substring(0, 16);
      expect(display, '2026-06-08 14:30');
    });

    test('T replaced with space', () {
      const String updatedAt = '2026-01-15T09:05:00Z';
      final String display =
          updatedAt.replaceFirst('T', ' ').substring(0, 16);
      expect(display.contains('T'), isFalse);
      expect(display.contains(' '), isTrue);
    });
  });
}
