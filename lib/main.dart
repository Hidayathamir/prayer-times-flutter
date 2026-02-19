import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:adhan/adhan.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz2;
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'prayer_data_service.dart';
import 'app_config.dart';

// ── Color Palette ──────────────────────────────────────────────────────
class AppColors {
  static const Color primary = Color(0xFF0D4F4F);
  static const Color primaryLight = Color(0xFF1A7A7A);
  static const Color accent = Color(0xFFE8B931);
  static const Color accentGlow = Color(0x40E8B931);
  static const Color surface = Color(0xFF0A1A2E);
  static const Color surfaceLight = Color(0xFF132742);
  static const Color cardBg = Color(0xFF15304D);
  static const Color textPrimary = Color(0xFFF0F0F0);
  static const Color textSecondary = Color(0xFFAABBCC);
  static const Color searchBg = Color(0xFF1C3A5C);
}

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
      _cityController.text = name;
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
  void _onTextChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
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
    _cityController.text = shortName;
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

      _cityController.text = cityName;
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
              _buildSearchBar(),
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
        return Padding(
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
        );
      },
    );
  }

  Future<void> _previewNotification(String prayerKey, String label) async {
    final msg = PrayerDataService.getMessageForToday(prayerKey);
    await NotificationService.showInstantNotification(
      msg?.title ?? '$label Reminder',
      msg?.body ?? '$label is coming up soon!',
    );
  }

  Widget _buildHeader() {
    final nextPrayer = _getNextPrayer();
    final now = DateTime.now();
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(now);

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
          // Top row: title + crescent
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
              const Text('☪', style: TextStyle(fontSize: 28)),
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

          // City
          if (selectedCityName != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: AppColors.accent),
                const SizedBox(width: 4),
                Text(
                  selectedCityName!,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.accent,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],

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

  // ── Search Bar ────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.searchBg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
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
                            setState(() => _suggestions = []);
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                onChanged: _onTextChanged,
                onSubmitted: _onSubmitted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryLight.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              tooltip: 'Use my location',
              icon: const Icon(
                Icons.my_location,
                color: Colors.white,
                size: 22,
              ),
              onPressed: _useGPS,
            ),
          ),
        ],
      ),
    );
  }

  // ── Suggestions Dropdown ──────────────────────────────────────────────
  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 68, 0),
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
            'Search for a city or use GPS',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: AppColors.textSecondary.withOpacity(0.5),
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
