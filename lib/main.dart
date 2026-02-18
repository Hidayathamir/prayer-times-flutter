import 'package:flutter/material.dart';
import 'package:adhan/adhan.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required when using async in main
  tz.initializeTimeZones();
  await NotificationService.init(); // Start the notification engine
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
    final myCoordinates = Coordinates(-6.2088, 106.8456); // Jakarta
    final params = CalculationMethod.singapore.getParameters();
    params.madhab = Madhab.shafi;
    final today = DateComponents.from(DateTime.now());

    setState(() {
      prayerTimes = PrayerTimes(myCoordinates, today, params);
    });

    // --- NEW: Schedule Notifications ---
    // We use unique IDs (1, 2, 3...) for each prayer
    NotificationService.schedulePrayerReminder(1, 'Fajr', prayerTimes.fajr);
    NotificationService.schedulePrayerReminder(2, 'Dhuhr', prayerTimes.dhuhr);
    NotificationService.schedulePrayerReminder(3, 'Asr', prayerTimes.asr);
    NotificationService.schedulePrayerReminder(
      4,
      'Maghrib',
      prayerTimes.maghrib,
    );
    NotificationService.schedulePrayerReminder(5, 'Isha', prayerTimes.isha);
  }

  @override
  Widget build(BuildContext context) {
    // Helper to format time (e.g., 18:05)
    String format(DateTime dt) => DateFormat.Hm().format(dt);

    return Scaffold(
      appBar: AppBar(title: const Text('Jakarta Prayer Times')),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.notifications),
        onPressed: () {
          NotificationService.showInstantNotification(
            'Test',
            'This is a notification from Flutter!',
          );
        },
      ),
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
