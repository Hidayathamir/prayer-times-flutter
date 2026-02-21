import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:adhan/adhan.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz2;
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'prayer_data_service.dart';
import 'app_config.dart';
import 'settings_service.dart';
import 'settings_screen.dart';
import 'app_colors.dart';


// ── Prayer Data Model ──────────────────────────────────────────────────
class PrayerInfo {
  final String name;
  final String arabicName;
  final IconData icon;
  final DateTime time;
  final bool isNext;

  PrayerInfo({
    required this.name,
    required this.arabicName,
    required this.icon,
    required this.time,
    this.isNext = false,
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz2.setLocalLocation(tz2.getLocation('Asia/Jakarta'));
  await SettingsService.init();
  await NotificationService.init();
  await PrayerDataService.loadAll();
  runApp(PrayerApp());
}

class PrayerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prayer Times',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.surface,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        colorScheme: ColorScheme.dark(
          primary: AppColors.primaryLight,
          secondary: AppColors.accent,
          surface: AppColors.surface,
        ),
      ),
      home: const PrayerTimesScreen(),
    );
  }
}

class PrayerTimesScreen extends StatefulWidget {
  const PrayerTimesScreen({super.key});

  @override
  State<PrayerTimesScreen> createState() => _PrayerTimesScreenState();
}

class _PrayerTimesScreenState extends State<PrayerTimesScreen>
    with TickerProviderStateMixin {
  final TextEditingController _cityController = TextEditingController();
  PrayerTimes? prayerTimes;
  String? selectedCityName;
  bool isLoading = false;
  List<Map<String, dynamic>> _suggestions = [];
  Timer? _debounce;
  Timer? _countdownTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Update countdown every minute
    _countdownTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    // Restore saved city
    _restoreSavedCity();
  }

  Future<void> _restoreSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('city_name');
    final lat = prefs.getDouble('city_lat');
    final lon = prefs.getDouble('city_lon');

    if (name != null && lat != null && lon != null) {
      setState(() => selectedCityName = name);
      _updatePrayerTimes(lat, lon, save: false);
    }
  }

  @override
  void dispose() {
    _cityController.dispose();
    _debounce?.cancel();
    _countdownTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  // ── Search ───────────────────────────────────────────────────────────
  Future<void> _fetchCities(String query) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=$query&format=json&featuretype=city&limit=5',
    );
    try {
      final response = await http.get(
        url,
        headers: {'User-Agent': 'FlutterPrayerApp/1.0'},
      );
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
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
      }
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  void _onCitySelected(Map<String, dynamic> city) {
    final shortName = city['name'].toString().split(',')[0];
    setState(() {
      _suggestions = [];
      selectedCityName = shortName;
    });
    _updatePrayerTimes(city['lat'], city['lon']);
  }

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
        _showError('No results found.');
      }
    } catch (e) {
      _showError('City not found. Try again.');
    }
    setState(() => isLoading = false);
  }

  // ── GPS ──────────────────────────────────────────────────────────────
  Future<void> _useGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showError('Location services are disabled.');
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showError('Location permission denied.');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      _showError('Location permission permanently denied.');
      return;
    }

    setState(() {
      isLoading = true;
      _suggestions = [];
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final cityName = placemarks.isNotEmpty
          ? (placemarks.first.locality ??
                placemarks.first.subAdministrativeArea ??
                'Unknown')
          : 'Unknown';

      setState(() => selectedCityName = cityName);
      _updatePrayerTimes(position.latitude, position.longitude);
    } catch (e) {
      _showError('Failed to get location.');
    }
    setState(() => isLoading = false);
  }

  // ── Prayer Times ────────────────────────────────────────────────────
  void _updatePrayerTimes(double lat, double lon, {bool save = true}) {
    final coords = Coordinates(lat, lon);
    final params = CalculationMethod.singapore.getParameters();
    params.madhab = Madhab.shafi;
    final today = DateComponents.from(DateTime.now());

    setState(() {
      prayerTimes = PrayerTimes(coords, today, params);
    });

    _fadeController.reset();
    _fadeController.forward();

    _scheduleNotifications();

    // Persist the selection
    if (save) _saveCity(lat, lon);
  }

  Future<void> _saveCity(double lat, double lon) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('city_name', selectedCityName ?? '');
    await prefs.setDouble('city_lat', lat);
    await prefs.setDouble('city_lon', lon);
  }

  Future<void> _scheduleNotifications() async {
    if (prayerTimes == null) return;
    await NotificationService.cancelAll();

    final prayers = {
      'Fajr': prayerTimes!.fajr,
      'Dhuhr': prayerTimes!.dhuhr,
      'Asr': prayerTimes!.asr,
      'Maghrib': prayerTimes!.maghrib,
      'Isha': prayerTimes!.isha,
    };

    int id = 1;
    for (final entry in prayers.entries) {
      final msg = PrayerDataService.getMessageForToday(entry.key);
      await NotificationService.schedulePrayerReminder(
        id++,
        entry.key,
        entry.value,
        notifTitle: msg?.title,
        notifBody: msg?.body,
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────
  PrayerInfo? _getNextPrayer() {
    try {
      return _prayers.firstWhere((p) => p.isNext);
    } catch (_) {
      return null;
    }
  }

  String _formatCountdown(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  // ── UI ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _suggestions = []);
        },
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              if (_suggestions.isNotEmpty) _buildSuggestions(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
      floatingActionButton: AppConfig.devMode ? _buildDebugFab() : null,
    );
  }

  // ── Header ────────────────────────────────────────────────────────────
  // ── Debug FAB ─────────────────────────────────────────────────────────
  Widget _buildDebugFab() {
    return FloatingActionButton(
      backgroundColor: Colors.orange.shade700,
      mini: true,
      tooltip: 'Preview notifications (DEV)',
      onPressed: _showDebugSheet,
      child: const Icon(Icons.bug_report, size: 20),
    );
  }

  void _showDebugSheet() {
    final prayerKeys = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final prayerLabels = ['Subuh', 'Dzuhur', 'Ashar', 'Maghrib', 'Isya'];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '🔔 Preview Notification',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              ...List.generate(prayerKeys.length, (i) {
                final msg = PrayerDataService.getMessageForToday(prayerKeys[i]);
                return ListTile(
                  leading: Icon(
                    Icons.notifications_active,
                    color: Colors.orange.shade400,
                    size: 22,
                  ),
                  title: Text(
                    prayerLabels[i],
                    style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    msg?.title ?? '(no data)',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _previewNotification(prayerKeys[i], prayerLabels[i]);
                  },
                );
              }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _previewNotification(String prayerKey, String label) async {
    final msg = PrayerDataService.getMessageForToday(prayerKey);
    await NotificationService.showPrayerNotification(
      id: 100 + _getPrayerIndex(prayerKey), // Use unique IDs to avoid conflicts
      prayerName: label,
      title: msg?.title ?? '$label Reminder',
      body: msg?.body ?? '$label is coming up soon!',
      isInstant: true,
      enableSnooze: true, // Enable snooze for debug notifications too
    );
  }

  // Helper to get prayer index for unique IDs
  int _getPrayerIndex(String prayerKey) {
    switch (prayerKey) {
      case 'Fajr': return 0;
      case 'Dhuhr': return 1;
      case 'Asr': return 2;
      case 'Maghrib': return 3;
      case 'Isha': return 4;
      default: return 0;
    }
  }

  Widget _buildHeader() {
    final nextPrayer = _getNextPrayer();
    
    DateTime effectiveNow = DateTime.now();
    // In Islam, the new day starts after Maghrib
    if (prayerTimes != null && effectiveNow.isAfter(prayerTimes!.maghrib)) {
      effectiveNow = effectiveNow.add(const Duration(days: 1));
    }
    
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(now);
    
    HijriCalendar.setLocal('en');
    // Adjust -1 day for Indonesian Hijri calendar
    final adjustedDate = effectiveNow.subtract(const Duration(days: 1));
    final hDate = HijriCalendar.fromDate(adjustedDate);
    String hijriStr = '${hDate.hDay} ${hDate.longMonthName} ${hDate.hYear} AH';
    if (hDate.hMonth == 9) { // 9 is Ramadhan
      if (effectiveNow.day != now.day) {
        hijriStr = 'Tonight is Ramadhan Day ${hDate.hDay}';
      } else {
        hijriStr = 'Ramadhan Day ${hDate.hDay}';
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F3D3E), Color(0xFF0A2A4A), Color(0xFF102040)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: title + settings + crescent
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Prayer Times',
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary, size: 22),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettingsScreen(
                            onSettingsChanged: () {
                              // Reschedule notifications with new settings
                              _scheduleNotifications();
                              setState(() {});
                            },
                          ),
                        ),
                      );
                    },
                    tooltip: 'Settings',
                  ),
                  const Text('☪', style: TextStyle(fontSize: 28)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Date
          Text(
            dateStr,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hijriStr,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),

          // Location chip - compact and tappable
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _showLocationPicker,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selectedCityName != null
                    ? AppColors.accent.withOpacity(0.15)
                    : AppColors.primaryLight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selectedCityName != null
                      ? AppColors.accent.withOpacity(0.3)
                      : AppColors.primaryLight.withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selectedCityName != null ? Icons.location_on : Icons.add_location,
                    size: 14,
                    color: selectedCityName != null ? AppColors.accent : AppColors.primaryLight,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    selectedCityName ?? 'Set Location',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: selectedCityName != null ? AppColors.accent : AppColors.primaryLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit,
                    size: 12,
                    color: selectedCityName != null
                        ? AppColors.accent.withOpacity(0.7)
                        : AppColors.primaryLight.withOpacity(0.7),
                  ),
                ],
              ),
            ),
          ),

          // Next prayer countdown
          if (nextPrayer != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.accentGlow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.accent.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(nextPrayer.icon, color: AppColors.accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Next: ${nextPrayer.name}',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          DateFormat.Hm().format(nextPrayer.time),
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatCountdown(
                        nextPrayer.time.difference(DateTime.now()),
                      ),
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.surface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Location Picker Bottom Sheet ──────────────────────────────────────
  void _showLocationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bottomPadding = MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).viewPadding.bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    Text(
                      'Select Location',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Search for a city or use your current location',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Search field
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.searchBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _cityController,
                        style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search city...',
                          hintStyle: GoogleFonts.poppins(
                            color: AppColors.textSecondary.withOpacity(0.6),
                            fontSize: 14,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          suffixIcon: _cityController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _cityController.clear();
                                    setModalState(() => _suggestions = []);
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                        onChanged: (text) {
                          _debounce?.cancel();
                          if (text.trim().length < 3) {
                            setModalState(() => _suggestions = []);
                            return;
                          }
                          _debounce = Timer(const Duration(milliseconds: 500), () {
                            _fetchCities(text.trim()).then((_) {
                              if (mounted) setModalState(() {});
                            });
                          });
                        },
                        onSubmitted: (text) async {
                          if (text.trim().isEmpty) return;
                          Navigator.pop(ctx);
                          await _onSubmitted(text);
                        },
                      ),
                    ),
                    // Suggestions inside bottom sheet
                    if (_suggestions.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          color: AppColors.cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.searchBg, width: 1),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _suggestions.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color: AppColors.searchBg, indent: 48),
                          itemBuilder: (context, index) {
                            final city = _suggestions[index];
                            final parts = city['name'].toString().split(',');
                            final title = parts[0].trim();
                            final subtitle = parts.length > 1
                                ? parts.sublist(1).join(',').trim()
                                : '';

                            return ListTile(
                              dense: true,
                              leading: Icon(Icons.location_on, color: AppColors.accent, size: 18),
                              title: Text(
                                title,
                                style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: subtitle.isNotEmpty
                                  ? Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                _onCitySelected(city);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    // GPS button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _useGPS();
                        },
                        icon: const Icon(Icons.my_location, size: 18),
                        label: Text(
                          'Use Current Location',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _cityController.clear();
      setState(() => _suggestions = []);
    });
  }

  // ── Suggestions Dropdown (legacy - kept for reference but now inside bottom sheet) ──────────────────────────────────────────────
  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.searchBg, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: AppColors.searchBg, indent: 48),
        itemBuilder: (context, index) {
          final city = _suggestions[index];
          final parts = city['name'].toString().split(',');
          final title = parts[0].trim();
          final subtitle = parts.length > 1
              ? parts.sublist(1).join(',').trim()
              : '';

          return ListTile(
            dense: true,
            leading: Icon(Icons.location_on, color: AppColors.accent, size: 18),
            title: Text(
              title,
              style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            subtitle: subtitle.isNotEmpty
                ? Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  )
                : null,
            onTap: () => _onCitySelected(city),
          );
        },
      ),
    );
  }

  // ── Body (prayer list or empty state) ─────────────────────────────────
  Widget _buildBody() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }

    if (prayerTimes == null) {
      return _buildEmptyState();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: _buildPrayerListView(),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mosque_rounded,
            size: 80,
            color: AppColors.textSecondary.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          Text(
            'Find Your Prayer Times',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Set your location to see prayer times',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showLocationPicker,
            icon: const Icon(Icons.location_on),
            label: Text(
              'Set Location',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Prayer List ───────────────────────────────────────────────────────
  Widget _buildPrayerListView() {
    final prayers = _prayers;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      itemCount: prayers.length,
      itemBuilder: (context, index) {
        return _buildPrayerCard(prayers[index], index);
      },
    );
  }

  Widget _buildPrayerCard(PrayerInfo prayer, int index) {
    final timeStr = DateFormat.Hm().format(prayer.time);
    final isPast = prayer.time.isBefore(DateTime.now());

    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 80)),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: prayer.isNext
            ? const LinearGradient(
                colors: [Color(0xFF1A4A3A), Color(0xFF0F3A5A)],
              )
            : null,
        color: prayer.isNext ? null : AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: prayer.isNext
            ? Border.all(color: AppColors.accent.withOpacity(0.4), width: 1.5)
            : Border.all(color: Colors.transparent),
        boxShadow: prayer.isNext
            ? [
                BoxShadow(
                  color: AppColors.accent.withOpacity(0.15),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            // Icon
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: prayer.isNext
                    ? AppColors.accent.withOpacity(0.15)
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                prayer.icon,
                color: prayer.isNext
                    ? AppColors.accent
                    : isPast
                    ? AppColors.textSecondary.withOpacity(0.4)
                    : AppColors.textSecondary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),

            // Name + Arabic
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prayer.name,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: prayer.isNext
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isPast
                          ? AppColors.textSecondary.withOpacity(0.4)
                          : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    prayer.arabicName,
                    style: GoogleFonts.notoSansArabic(
                      fontSize: 12,
                      color: prayer.isNext
                          ? AppColors.accent.withOpacity(0.7)
                          : AppColors.textSecondary.withOpacity(
                              isPast ? 0.3 : 0.6,
                            ),
                    ),
                  ),
                ],
              ),
            ),

            // Time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  timeStr,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: prayer.isNext
                        ? AppColors.accent
                        : isPast
                        ? AppColors.textSecondary.withOpacity(0.4)
                        : AppColors.textPrimary,
                  ),
                ),
                if (prayer.isNext)
                  Text(
                    'Upcoming',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.accent.withOpacity(0.8),
                    ),
                  ),
                if (isPast && !prayer.isNext)
                  Text(
                    'Passed',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textSecondary.withOpacity(0.3),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Renamed to avoid conflict
  List<PrayerInfo> get _prayers {
    if (prayerTimes == null) return [];
    final now = DateTime.now();
    final prayers = [
      PrayerInfo(
        name: 'Fajr',
        arabicName: 'الفجر',
        icon: Icons.nights_stay_rounded,
        time: prayerTimes!.fajr,
      ),
      PrayerInfo(
        name: 'Dhuhr',
        arabicName: 'الظهر',
        icon: Icons.wb_sunny_rounded,
        time: prayerTimes!.dhuhr,
      ),
      PrayerInfo(
        name: 'Asr',
        arabicName: 'العصر',
        icon: Icons.wb_twilight_rounded,
        time: prayerTimes!.asr,
      ),
      PrayerInfo(
        name: 'Maghrib',
        arabicName: 'المغرب',
        icon: Icons.nightlight_round,
        time: prayerTimes!.maghrib,
      ),
      PrayerInfo(
        name: 'Isha',
        arabicName: 'العشاء',
        icon: Icons.dark_mode_rounded,
        time: prayerTimes!.isha,
      ),
    ];
    int nextIndex = prayers.indexWhere((p) => p.time.isAfter(now));
    return prayers.asMap().entries.map((entry) {
      return PrayerInfo(
        name: entry.value.name,
        arabicName: entry.value.arabicName,
        icon: entry.value.icon,
        time: entry.value.time,
        isNext: entry.key == nextIndex,
      );
    }).toList();
  }
}
