import 'package:flutter_test/flutter_test.dart';
import 'package:track_my_indoor_exercise/upload/oauth_state.dart';

void main() {
  group('generateOAuthState', () {
    test('generates a non-empty string of the requested length', () {
      final state = generateOAuthState();
      expect(state, isNotEmpty);
      expect(state.length, 32);
    });

    test('generates a different value on every call', () {
      final first = generateOAuthState();
      final second = generateOAuthState();
      expect(first, isNot(equals(second)));
    });

    test('honors a custom length', () {
      final state = generateOAuthState(length: 8);
      expect(state.length, 8);
    });
  });

  group('isValidOAuthState', () {
    test('returns true when expected and received match and are non-empty', () {
      expect(isValidOAuthState('abc123', 'abc123'), true);
    });

    test('returns false when received is null', () {
      expect(isValidOAuthState('abc123', null), false);
    });

    test('returns false when expected is null', () {
      expect(isValidOAuthState(null, 'abc123'), false);
    });

    test('returns false when both are null', () {
      expect(isValidOAuthState(null, null), false);
    });

    test('returns false when expected is empty', () {
      expect(isValidOAuthState('', 'abc123'), false);
    });

    test('returns false when values differ', () {
      expect(isValidOAuthState('abc123', 'xyz789'), false);
    });
  });
}
