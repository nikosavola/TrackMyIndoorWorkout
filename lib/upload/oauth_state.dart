import 'dart:math';

/// Shared helpers for validating OAuth 2.0 redirects that arrive through a
/// custom URL scheme (e.g. `stravaflutter://redirect`).
///
/// Custom URL schemes are not verified by the OS (unlike Android App Links
/// or iOS Universal Links): any other app installed on the device can
/// register the same scheme and could, in theory, receive or spoof a
/// redirect meant for this app. Requiring every redirect to echo back a
/// random `state` value that was generated right before launching the
/// authorization request - and never persisted to disk - mitigates that
/// class of attack, since a spoofed/replayed redirect will not know the
/// value that was generated for the in-flight request.

/// Generates a cryptographically random string suitable for use as an
/// OAuth 2.0 `state` parameter.
String generateOAuthState({int length = 32}) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  return List.generate(length, (_) => chars[random.nextInt(chars.length)]).join();
}

/// Returns true only if [received] is non-null, non-empty and equal to
/// [expected]. Used to validate the `state` query parameter of an
/// incoming OAuth redirect against the value generated for the
/// corresponding outgoing authorization request.
bool isValidOAuthState(String? expected, String? received) {
  return expected != null && expected.isNotEmpty && received != null && received == expected;
}
