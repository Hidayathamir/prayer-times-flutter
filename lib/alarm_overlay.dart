import 'dart:async';
import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'alarm_service.dart';
import 'app_colors.dart';
import 'settings_service.dart';

/// Full-screen overlay shown when a prayer alarm rings.
/// Displayed by pushing this route on top of the app.
class AlarmOverlayScreen extends StatefulWidget {
  final AlarmSettings alarmSettings;

  const AlarmOverlayScreen({super.key, required this.alarmSettings});

  @override
  State<AlarmOverlayScreen> createState() => _AlarmOverlayScreenState();
}

class _AlarmOverlayScreenState extends State<AlarmOverlayScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _snoozed = false;

  // Extract prayer name from alarm notification title
  String get _prayerName {
    // Title format: "Fajr – 15 minutes" or custom CSV title
    final title = widget.alarmSettings.notificationSettings.title;
    // Try to find a known prayer name in the title
    for (final name in ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha',
                         'Subuh', 'Dzuhur', 'Ashar', 'Isya']) {
      if (title.contains(name)) return name;
    }
    // Fallback: title up to first separator
    return title.split(RegExp(r'[–\-|]'))[0].trim();
  }

  String get _nowTime => DateFormat.Hm().format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _stop() async {
    await Alarm.stop(widget.alarmSettings.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze() async {
    setState(() => _snoozed = true);
    final snoozeMinutes = SettingsService.snoozeDurationMinutes;
    await AlarmService.snooze(
      id: widget.alarmSettings.id,
      minutes: snoozeMinutes,
      prayerName: _prayerName,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Snoozed for $snoozeMinutes minutes'),
          backgroundColor: AppColors.primaryLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing mosque icon
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent.withOpacity(0.12),
                          border: Border.all(
                            color: AppColors.accent.withOpacity(0.4),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.mosque_rounded,
                          size: 64,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Time
                    Text(
                      _nowTime,
                      style: GoogleFonts.poppins(
                        fontSize: 56,
                        fontWeight: FontWeight.w300,
                        color: AppColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Prayer name
                    Text(
                      _prayerName,
                      style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.alarmSettings.notificationSettings.body,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                children: [
                  // Snooze button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _snoozed ? null : _snooze,
                      icon: const Icon(Icons.snooze_rounded),
                      label: Text(
                        'Snooze ${SettingsService.formatSnoozeDuration(SettingsService.snoozeDurationMinutes)}',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(
                          color: AppColors.textSecondary.withOpacity(0.4),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Stop button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _stop,
                      icon: const Icon(Icons.stop_circle_rounded),
                      label: Text(
                        'Stop Alarm',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
