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
  late int _snoozeSeconds;

  @override
  void initState() {
    super.initState();
    _notificationMinutes = SettingsService.notificationMinutesBefore;
    _snoozeSeconds = SettingsService.snoozeDurationSeconds;
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
          // Notification Time Section
          _buildSectionHeader('Notification Time'),
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
            subtitle: 'Notify $minutes minutes before prayer time',
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
        children: SettingsService.snoozeDurationOptions.map((seconds) {
          final isSelected = _snoozeSeconds == seconds;
          return _buildOptionTile(
            title: SettingsService.formatSnoozeDuration(seconds),
            subtitle: 'Snooze reminder after $seconds seconds',
            isSelected: isSelected,
            onTap: () => _selectSnoozeDuration(seconds),
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
              Icon(Icons.info_outline, color: AppColors.primaryLight, size: 20),
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
            'Notification Time',
            'You will receive a reminder at the selected time before each prayer.',
          ),
          const SizedBox(height: 8),
          _buildInfoItem(
            'Snooze Duration',
            'When you tap "Remind me later" on a notification, you\'ll get another reminder after this duration.',
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
          content: Text(
            'Notification time set to ${SettingsService.formatNotificationTime(minutes)}',
          ),
          backgroundColor: AppColors.primaryLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _selectSnoozeDuration(int seconds) async {
    if (_snoozeSeconds == seconds) return;

    setState(() => _snoozeSeconds = seconds);
    await SettingsService.setSnoozeDurationSeconds(seconds);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Snooze duration set to ${SettingsService.formatSnoozeDuration(seconds)}',
          ),
          backgroundColor: AppColors.primaryLight,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
}
