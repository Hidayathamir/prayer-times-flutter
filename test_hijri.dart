import 'package:hijri/hijri_calendar.dart';
void main() {
  HijriCalendar.setLocal('en');
  // Mock Feb 21 04:00
  var beforeMaghrib = DateTime(2026, 2, 21, 4, 0);
  var adjustedBefore = beforeMaghrib.subtract(const Duration(days: 1));
  var hBefore = HijriCalendar.fromDate(adjustedBefore);
  
  // Mock Feb 21 21:00 (after maghrib, assuming maghrib is around 18:00)
  var afterMaghrib = DateTime(2026, 2, 21, 21, 0);
  var effectiveAfter = afterMaghrib.add(const Duration(days: 1));
  var adjustedAfter = effectiveAfter.subtract(const Duration(days: 1));
  var hAfter = HijriCalendar.fromDate(adjustedAfter);
  
  print("Feb 21 04:00: Ramadhan Day ${hBefore.hDay} (Month ${hBefore.hMonth})");
  print("Feb 21 21:00: Tonight is Ramadhan Day ${hAfter.hDay} (Month ${hAfter.hMonth})");
}
