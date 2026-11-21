// phase-06
// Shared list tail helper. One home, one name — agent loop and chat
// controller both cap their histories with it.
extension TakeLast<T> on List<T> {
  List<T> takeLast(int n) =>
      length <= n ? this : sublist(length - n);
}
