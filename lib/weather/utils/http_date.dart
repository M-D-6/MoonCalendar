/// Parses an RFC 1123 HTTP date ("Tue, 15 Nov 1994 08:12:31 GMT"); falls back to ISO 8601.
DateTime? parseHttpDate(String? value) {
  if (value == null) return null;
  final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})').firstMatch(value);
  if (m != null) {
    const months = <String>['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final month = months.indexOf(m.group(2)!.toLowerCase()) + 1;
    if (month > 0) {
      return DateTime.utc(int.parse(m.group(3)!), month, int.parse(m.group(1)!), int.parse(m.group(4)!), int.parse(m.group(5)!), int.parse(m.group(6)!));
    }
  }
  return DateTime.tryParse(value);
}
