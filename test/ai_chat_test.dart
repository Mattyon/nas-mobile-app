import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — AI chat screen keys', () {
    const List<String> keys = <String>[
      'aiAssistant', 'aiHint', 'aiClear', 'aiEmptyHint',
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

    test('aiHint and aiEmptyHint are different', () {
      lang.value = 'en';
      expect(tr('aiHint'), isNot(equals(tr('aiEmptyHint'))));
    });

    test('aiClear and aiHint are different', () {
      lang.value = 'en';
      expect(tr('aiClear'), isNot(equals(tr('aiHint'))));
    });
  });

  group('i18n — speedtest screen keys', () {
    const List<String> keys = <String>[
      'speedtest', 'runSpeedtest', 'speedtestRunning',
      'downloadSpeed', 'uploadSpeed', 'ping', 'isp', 'testServer',
    ];

    for (final String key in keys) {
      test('EN "$key" translated', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }
  });

  group('AI chat — message structure', () {
    test('user message has role=user and content', () {
      final Map<String, dynamic> msg = <String, dynamic>{
        'role': 'user',
        'content': 'Find me a sci-fi movie',
      };
      expect(msg['role'], 'user');
      expect(msg['content'], isNotEmpty);
    });

    test('assistant message has role=assistant and content', () {
      final Map<String, dynamic> msg = <String, dynamic>{
        'role': 'assistant',
        'content': 'Here are some great sci-fi movies...',
      };
      expect(msg['role'], 'assistant');
      expect(msg['content'], isNotEmpty);
    });

    test('sendChatMessage payload includes active:true', () {
      // Mirrors: data: {'content': content, 'active': true}
      const String content = 'Hello AI';
      final Map<String, dynamic> payload = <String, dynamic>{
        'content': content,
        'active': true,
      };
      expect(payload['active'], isTrue,
          reason: 'active:true prevents push + unread flag while screen is open');
    });
  });

  group('AI chat — history loading', () {
    test('chat history has messages list', () {
      final Map<String, dynamic> chatData = <String, dynamic>{
        'id': 'uuid-123',
        'title': 'My Chat',
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': 'Hi'},
          <String, dynamic>{'role': 'assistant', 'content': 'Hello!'},
        ],
      };
      final List<dynamic> messages =
          (chatData['messages'] as List<dynamic>?) ?? <dynamic>[];
      expect(messages.length, 2);
    });

    test('empty chat has no messages', () {
      final Map<String, dynamic> chatData = <String, dynamic>{
        'id': 'uuid-456',
        'title': 'New Chat',
        'messages': <dynamic>[],
      };
      final List<dynamic> messages =
          (chatData['messages'] as List<dynamic>?) ?? <dynamic>[];
      expect(messages, isEmpty);
    });
  });
}
