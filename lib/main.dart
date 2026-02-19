import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:adhan/adhan.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz2;
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz2.setLocalLocation(tz2.getLocation('Asia/Jakarta'));
  await NotificationService.init();
  runApp(const MaterialApp(home: PrayerTimesScreen()));
}

class PrayerTimesScreen extends StatefulWidget {
  const PrayerTimesScreen({super.key});

  @override
  State<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends State<PrayerTimesScreen> {
  final TextEditingController _cityController = TextEditingController();
  PrayerTimes? prayerTimes;
  String? selectedCityName;
  bool isLoading = false;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _cityController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Search cities with debounce ──────────────────────────────────────
  void _onTextChanged(String text) {
    // Cancel previous timer so we don't spam the API
    _debounce?.cancel();

    if (text.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    // Wait 500ms after the user stops typing, then search
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchCities(text.trim());
    });
  }

  Future<void> _fetchCities(String query) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=$query&format=json&featuretype=city&limit=5',
    );

    try {
      print('[Search] Fetching cities for: "$query"');
      final response = await http.get(url, headers: {
        'User-Agent': 'FlutterPrayerApp/1.0',
      });

      print('[Search] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        print('[Search] Found ${data.length} results');

        if (!mounted) return;
        setState(() {
          _suggestions = data.map<Map<String, dynamic>>((item) {
            return {
              'name': item['display_name'] as String,
              'lat': double.parse(item['lat']),
              'lon': double.parse(item['lon']),
            };
          }).toList();
        });
      } else {
        print('[Search] Error: ${response.body}');
      }
    } catch (e) {
      print('[Search] Exception: $e');
    }
  }

  // ── Select a city from suggestions ───────────────────────────────────
  void _onCitySelected(Map<String, dynamic> city) {
    final shortName = city['name'].toString().split(',')[0];
    _cityController.text = shortName;
    setState(() {
      _suggestions = [];
      selectedCityName = shortName;
    });
    _updatePrayerTimes(city['lat'], city['lon']);
  }

  // ── Submit typed text with Enter key ─────────────────────────────────
  Future<void> _onSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      isLoading = true;
      _suggestions = [];
    });

    try {
      final locations = await locationFromAddress(text.trim());
      if (locations.isNotEmpty) {
        setState(() => selectedCityName = text.trim());
        _updatePrayerTimes(locations.first.latitude, locations.first.longitude);
      } else {
        _showError('No results found for "$text"');
      }
    } catch (e) {
      _showError('City not found. Try again.');
    }

    setState(() => isLoading = false);
  }

  // ── GPS auto-detect ──────────────────────────────────────────────────
  Future<void> _useGPS() async {
    // 1. Check if location service is enabled
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('Location services are disabled. Please enable them.');
      return;
    }

    // 2. Check & request permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Location permission denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showError('Location permission permanently denied. Enable it in settings.');
      return;
    }

    // 3. Get position
    setState(() {
      isLoading = true;
      _suggestions = [];
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // 4. Reverse geocode to get city name
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final cityName = placemarks.isNotEmpty
          ? (placemarks.first.locality ?? placemarks.first.subAdministrativeArea ?? 'Unknown')
          : 'Unknown';

      _cityController.text = cityName;
      setState(() => selectedCityName = cityName);
      _updatePrayerTimes(position.latitude, position.longitude);
    } catch (e) {
      _showError('Failed to get location: $e');
    }

    setState(() => isLoading = false);
  }

  // ── Core prayer time calculation ─────────────────────────────────────
  void _updatePrayerTimes(double lat, double lon) {
    final coords = Coordinates(lat, lon);
    final params = CalculationMethod.singapore.getParameters();
    params.madhab = Madhab.shafi;
    final today = DateComponents.from(DateTime.now());

    setState(() {
      prayerTimes = PrayerTimes(coords, today, params);
    });

    // Schedule notifications for the new city
    _scheduleNotifications();
  }

  Future<void> _scheduleNotifications() async {
    if (prayerTimes == null) return;

    // Cancel all old reminders first
    await NotificationService.cancelAll();

    // Schedule reminder 15min before each prayer
    await NotificationService.schedulePrayerReminder(1, 'Fajr', prayerTimes!.fajr);
    await NotificationService.schedulePrayerReminder(2, 'Dhuhr', prayerTimes!.dhuhr);
    await NotificationService.schedulePrayerReminder(3, 'Asr', prayerTimes!.asr);
    await NotificationService.schedulePrayerReminder(4, 'Maghrib', prayerTimes!.maghrib);
    await NotificationService.schedulePrayerReminder(5, 'Isha', prayerTimes!.isha);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    String fmt(DateTime dt) => DateFormat.Hm().format(dt);

    return Scaffold(
      appBar: AppBar(title: const Text('My Prayer Times')),
      body: GestureDetector(
        // Dismiss keyboard & suggestions when tapping outside
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _suggestions = []);
        },
        child: Column(
          children: [
            // ── Search bar ──
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        hintText: 'Type a city name...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: _cityController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _cityController.clear();
                                  setState(() => _suggestions = []);
                                },
                              )
                            : null,
                      ),
                      onChanged: _onTextChanged,
                      onSubmitted: _onSubmitted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Use my location',
                    icon: const Icon(Icons.my_location, color: Colors.blue),
                    onPressed: _useGPS,
                  ),
                ],
              ),
            ),

            // ── Suggestion list ──
            if (_suggestions.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, index) {
                    final city = _suggestions[index];
                    final parts = city['name'].toString().split(',');
                    final title = parts[0].trim();
                    final subtitle =
                        parts.length > 1 ? parts.sublist(1).join(',').trim() : '';

                    return ListTile(
                      dense: true,
                      leading:
                          Icon(Icons.location_on, color: Colors.blue.shade400, size: 20),
                      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: subtitle.isNotEmpty
                          ? Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
                          : null,
                      onTap: () => _onCitySelected(city),
                    );
                  },
                ),
              ),

            // ── Prayer times list ──
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : prayerTimes == null
                      ? const Center(
                          child: Text(
                            'Type a city or tap the GPS icon',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            if (selectedCityName != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8, top: 4),
                                child: Text(
                                  'Prayer times for $selectedCityName',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            _prayerTile('Fajr', fmt(prayerTimes!.fajr)),
                            _prayerTile('Dhuhr', fmt(prayerTimes!.dhuhr)),
                            _prayerTile('Asr', fmt(prayerTimes!.asr)),
                            _prayerTile('Maghrib', fmt(prayerTimes!.maghrib)),
                            _prayerTile('Isha', fmt(prayerTimes!.isha)),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prayerTile(String name, String time) {
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
