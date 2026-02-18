import 'package:flutter/material.dart';
import 'package:adhan/adhan.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MaterialApp(home: PrayerTimesScreen()));
}

// We use StatefulWidget because the times change every day
class PrayerTimesScreen extends StatefulWidget {
  const PrayerTimesScreen({super.key});

  @override
  State<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends State<PrayerTimesScreen> {
  // 1. Define variables to hold the data
  late PrayerTimes prayerTimes;

  // 2. This function runs ONCE when the app starts
  @override
  void initState() {
    super.initState();
    _calculatePrayers();
  }

  void _calculatePrayers() {
    // HARDCODED LOCATION: Jakarta (We will make this dynamic later)
    final myCoordinates = Coordinates(-6.2088, 106.8456);

    // Calculation parameters (standard for Indonesia/Singapore)
    final params = CalculationMethod.singapore.getParameters();
    params.madhab = Madhab.shafi;

    // Calculate for TODAY
    final today = DateComponents.from(DateTime.now());

    setState(() {
      prayerTimes = PrayerTimes(myCoordinates, today, params);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Helper to format time (e.g., 18:05)
    String format(DateTime dt) => DateFormat.Hm().format(dt);

    return Scaffold(
      appBar: AppBar(title: const Text('Jakarta Prayer Times')),
      body: ListView(
        children: [
          _buildRow('Fajr', format(prayerTimes.fajr)),
          _buildRow('Sunrise', format(prayerTimes.sunrise)),
          _buildRow('Dhuhr', format(prayerTimes.dhuhr)),
          _buildRow('Asr', format(prayerTimes.asr)),
          _buildRow('Maghrib', format(prayerTimes.maghrib)),
          _buildRow('Isha', format(prayerTimes.isha)),
        ],
      ),
    );
  }

  // A helper widget to avoid repeating code
  Widget _buildRow(String name, String time) {
    return ListTile(
      leading: const Icon(Icons.access_time),
      title: Text(name),
      trailing: Text(
        time,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}
