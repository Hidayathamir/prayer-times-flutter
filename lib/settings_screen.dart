import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'settings_service.dart';
import 'app_colors.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const SettingsScreen({super.key, this.onSettingsChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _notificationMinutes;
  late int _snoozeMinutes;

  @override
  void initState() {
    super.initState();
    _notificationMinutes = SettingsService.notificationMinutesBefore;
    _snoozeMinutes = SettingsService.snoozeDurationMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Alarm Time Section
            _buildSectionHeader('Alarm Time'),
            const SizedBox(height: 8),
            _buildNotificationTimeCard(),
            const SizedBox(height: 24),

            // Snooze Duration Section
            _buildSectionHeader('Snooze Duration'),
            const SizedBox(height: 8),
            _buildSnoozeDurationCard(),
            const SizedBox(height: 24),

            // Info card
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildNotificationTimeCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight, width: 1),
      ),
      child: Column(
        children: SettingsService.notificationTimeOptions.map((minutes) {
          final isSelected = _notificationMinutes == minutes;
          return _buildOptionTile(
            title: SettingsService.formatNotificationTime(minutes),
            subtitle: 'Alarm rings $minutes minutes before prayer time',
            isSelected: isSelected,
            onTap: () => _selectNotificationTime(minutes),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSnoozeDurationCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.surfaceLight, width: 1),
      ),
      child: Column(
        children: SettingsService.snoozeDurationOptions.map((minutes) {
          final isSelected = _snoozeMinutes == minutes;
          return _buildOptionTile(
            title: SettingsService.formatSnoozeDuration(minutes),
            subtitle: 'Re-rings after $minutes minutes',
            isSelected: isSelected,
            onTap: () => _selectSnoozeDuration(minutes),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOptionTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? AppColors.accent : Colors.transparent,
          border: Border.all(
            color: isSelected ? AppColors.accent : AppColors.textSecondary,
            width: 2,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, size: 14, color: AppColors.surface)
            : null,
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? AppColors.accent : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
      trailing: isSelected
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Active',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primaryLight.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alarm_on, color: AppColors.primaryLight, size: 20),
              const SizedBox(width: 8),
              Text(
                'How it works',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoItem(
            'Native Alarm',
            'Uses Android\'s alarm system — rings even if the app is killed or the phone is in silent/vibrate mode.',
          ),
          const SizedBox(height: 8),
          _buildInfoItem(
            'Alarm Time',
            'The alarm rings at the selected number of minutes before each prayer time.',
          ),
          const SizedBox(height: 8),
          _buildInfoItem(
            'Snooze',
            'When the alarm rings, tap "Snooze" on the alarm screen to delay it by the configured duration.',
          ),
          const SizedBox(height: 8),
          _buildInfoItem(
            'Battery Optimisation',
            'For best reliability, allow this app to ignore battery optimisation in your phone\'s settings.',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          description,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  void _selectNotificationTime(int minutes) async {
    if (_notificationMinutes == minutes) return;
    setState(() => _notificationMinutes = minutes);
    await SettingsService.setNotificationMinutesBefore(minutes);
    widget.onSettingsChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Alarm set to ${SettingsService.formatNotificationTime(minutes)}'),
          backgroundColor: AppColors.primaryLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _selectSnoozeDuration(int minutes) async {
    if (_snoozeMinutes == minutes) return;
    setState(() => _snoozeMinutes = minutes);
    await SettingsService.setSnoozeDurationMinutes(minutes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Snooze set to ${SettingsService.formatSnoozeDuration(minutes)}'),
          backgroundColor: AppColors.primaryLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}
