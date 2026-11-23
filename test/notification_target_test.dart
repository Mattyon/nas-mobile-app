import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/notification_target.dart';

void main() {
  String? target(String? event, {Object? itemId}) =>
      notificationTarget(<String, dynamic>{'event': event, 'item_id': itemId});

  test('a new version opens the store', () {
    expect(target('app.release'), 'store');
    expect(kStoreUrl, contains('id=mattyzem.nas'));
  });

  test('ready to watch opens that title when it says which', () {
    String? t(String event, String kind, Object id) =>
        notificationTarget(<String, dynamic>{'event': event, 'kind': kind, 'item_id': id});
    expect(t('movie.ready', 'movie', 12), 'movie:12');
    expect(t('tv.ready', 'tv', 49), 'tv:49');
    expect(t('tv.first_ready', 'tv', 49), 'tv:49');
  });

  test('ready to watch opens the library', () {
    for (final String e in <String>['movie.ready', 'tv.ready', 'tv.first_ready', 'tv.new_episodes', 'tv.premiere']) {
      expect(target(e), 'tab:2', reason: e);
    }
  });

  test('a download in trouble opens downloads', () {
    expect(target('download.failed'), 'tab:1');
    expect(target('download.still_stalled'), 'tab:1');
  });

  test('nothing found opens the search', () {
    expect(target('download.nothing_found'), 'tab:0');
    expect(target('czech.unavailable'), 'tab:0');
  });

  test('an AI reply opens its chat', () {
    expect(target('chat.reply', itemId: 'c-1'), 'chat:c-1');
    expect(target('chat.reply'), isNull);
  });

  test('server alerts', () {
    expect(target('monitor'), 'kuma');
    expect(target('backup.failed'), 'health');
    expect(target('mobile.failed'), 'health');
  });

  test('an old notification without an event only opens the app', () {
    expect(target(null), isNull);
    expect(notificationTarget(<String, dynamic>{}), isNull);
  });
}
