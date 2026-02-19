import 'package:flutter/material.dart';
import 'package:adhan/adhan.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz2;
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // Required when using async in main
  tz.initializeTimeZones();
  tz2.setLocalLocation(tz2.getLocation('Asia/Jakarta')); // Set local timezone!
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

  bool isLoading = true;

  // 2. This function runs ONCE when the app starts
  @override
  void initState() {
    super.initState();
    _getLocationAndCalculate();
  }

  Future<void> _getLocationAndCalculate() async {
    // 1. Check and request permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Handle denied permission (e.g., show error text)
        return;
      }
    }

    // 2. Get the actual location
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // 3. Plug it into Adhan
    final myCoordinates = Coordinates(position.latitude, position.longitude);
    final params = CalculationMethod.singapore.getParameters();
    params.madhab = Madhab.shafi;
    final today = DateComponents.from(DateTime.now());

    setState(() {
      prayerTimes = PrayerTimes(myCoordinates, today, params);
      isLoading = false; // Hide loading spinner
    });

    // Schedule notifications based on real location
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
      appBar: AppBar(title: const Text('My Prayer Times')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'instant',
            child: const Icon(Icons.flash_on),
            onPressed: () async {
              print("Firing instant notification NOW");
              await NotificationService.showInstantNotification(
                'Instant Test',
                'This notification should appear RIGHT NOW!',
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Instant notification fired!')),
              );
            },
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'direct_schedule',
            backgroundColor: Colors.green,
            child: const Icon(Icons.timer),
            onPressed: () async {
              print("Direct schedule test: 10 seconds from now");
              await NotificationService.scheduleDirectTest(
                888,
                const Duration(seconds: 10),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Direct schedule! Wait 10 sec...'),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'scheduled',
            child: const Icon(Icons.notifications),
            onPressed: () async {
              final fakePrayerTime = DateTime.now().add(
                const Duration(minutes: 15, seconds: 10),
              );

              print("Scheduling test for: $fakePrayerTime");

              await NotificationService.schedulePrayerReminder(
                999, // Test ID
                'Test Maghrib',
                fakePrayerTime,
              );

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Scheduled! Wait ~10 seconds...')),
              );
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
