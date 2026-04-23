/// notification_settings_screen.dart
/// ─────────────────────────────────────────────────────────────────────────────
/// Notification & Haptic Settings screen in the Profile tab.
///
/// Blueprint §4 — Non-Functional Standards:
///   • Per-channel on/off toggles (Medicine, Goal, Appointment).
///   • Haptic preview buttons for each pattern.
///   • Silent Mode Detection status — shows current ignored counts and
///     the "escalate to Critical Alerts" CTA for any channel at threshold.
///   • Critical Alerts toggle with explanation.
///   • Timezone preference carried over from [TimezoneService].
///
/// All settings persist via SharedPreferences through their respective services.
/// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vitalpath/services/haptic_service.dart';
import 'package:vitalpath/services/notification_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _notifService = NotificationService();
  final _haptics = HapticService();

  // Per-channel state
  final Map<String, bool> _channelEnabled = {
    NotificationChannel.medicineReminder: true,
    NotificationChannel.goalSuccess: true,
    NotificationChannel.appointment: true,
  };

  final Map<String, bool> _criticalEnabled = {};
  Map<String, int> _ignoredCounts = {};

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final counts = await _notifService.getAllIgnoredCounts();
    final criticalStates = <String, bool>{};
    final enabledStates = <String, bool>{};

    for (final ch in NotificationChannel.all) {
      criticalStates[ch] = await _notifService.isCriticalAlertsEnabled(ch);
      enabledStates[ch] = await _notifService.isChannelEnabled(ch);
    }

    if (mounted) {
      setState(() {
        _ignoredCounts = counts;
        _criticalEnabled.addAll(criticalStates);
        _channelEnabled.addAll(enabledStates);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Notifications & Haptics',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Channel settings ───────────────────────────────────────
                _SectionHeader(title: 'Notification Channels'),
                const SizedBox(height: 8),

                _ChannelSettingCard(
                  channelId: NotificationChannel.medicineReminder,
                  title: 'Medicine Reminders',
                  subtitle: 'Dose alerts and missed medication notifications',
                  icon: Icons.medication_rounded,
                  iconColor: const Color(0xFF00897B),
                  isEnabled: _channelEnabled[NotificationChannel.medicineReminder] ?? true,
                  isCritical: _criticalEnabled[NotificationChannel.medicineReminder] ?? false,
                  ignoredCount: _ignoredCounts[NotificationChannel.medicineReminder] ?? 0,
                  silentThreshold: 5,
                  onToggle: (v) async {
                    await _notifService.setChannelEnabled(
                        NotificationChannel.medicineReminder, v);
                    setState(() => _channelEnabled[
                        NotificationChannel.medicineReminder] = v);
                  },
                  onCriticalToggle: (v) async {
                    if (v) {
                      await _notifService.enableCriticalAlerts(
                          NotificationChannel.medicineReminder);
                    } else {
                      await _notifService.disableCriticalAlerts(
                          NotificationChannel.medicineReminder);
                    }
                    setState(() => _criticalEnabled[
                        NotificationChannel.medicineReminder] = v);
                  },
                  onHapticPreview: () => _haptics.medicineReminder(),
                ),
                const SizedBox(height: 10),

                _ChannelSettingCard(
                  channelId: NotificationChannel.goalSuccess,
                  title: 'Goal Achievements',
                  subtitle: 'Step goals, medication streaks, activity targets',
                  icon: Icons.emoji_events_rounded,
                  iconColor: const Color(0xFFF57C00),
                  isEnabled: _channelEnabled[NotificationChannel.goalSuccess] ?? true,
                  isCritical: _criticalEnabled[NotificationChannel.goalSuccess] ?? false,
                  ignoredCount: _ignoredCounts[NotificationChannel.goalSuccess] ?? 0,
                  silentThreshold: 5,
                  onToggle: (v) async {
                    await _notifService.setChannelEnabled(
                        NotificationChannel.goalSuccess, v);
                    setState(() =>
                        _channelEnabled[NotificationChannel.goalSuccess] = v);
                  },
                  onCriticalToggle: (v) async {
                    if (v) {
                      await _notifService.enableCriticalAlerts(
                          NotificationChannel.goalSuccess);
                    } else {
                      await _notifService.disableCriticalAlerts(
                          NotificationChannel.goalSuccess);
                    }
                    setState(() =>
                        _criticalEnabled[NotificationChannel.goalSuccess] = v);
                  },
                  onHapticPreview: () => _haptics.goalSuccess(),
                ),
                const SizedBox(height: 10),

                _ChannelSettingCard(
                  channelId: NotificationChannel.appointment,
                  title: 'Appointment Alerts',
                  subtitle: 'Confirmation, reminders, and schedule changes',
                  icon: Icons.calendar_month_rounded,
                  iconColor: const Color(0xFF1565C0),
                  isEnabled: _channelEnabled[NotificationChannel.appointment] ?? true,
                  isCritical: _criticalEnabled[NotificationChannel.appointment] ?? false,
                  ignoredCount: _ignoredCounts[NotificationChannel.appointment] ?? 0,
                  silentThreshold: 5,
                  onToggle: (v) async {
                    await _notifService.setChannelEnabled(
                        NotificationChannel.appointment, v);
                    setState(() =>
                        _channelEnabled[NotificationChannel.appointment] = v);
                  },
                  onCriticalToggle: (v) async {
                    if (v) {
                      await _notifService.enableCriticalAlerts(
                          NotificationChannel.appointment);
                    } else {
                      await _notifService.disableCriticalAlerts(
                          NotificationChannel.appointment);
                    }
                    setState(() =>
                        _criticalEnabled[NotificationChannel.appointment] = v);
                  },
                  onHapticPreview: () => _haptics.appointmentConfirmed(),
                ),

                const SizedBox(height: 24),

                // ── Haptic patterns ────────────────────────────────────────
                _SectionHeader(title: 'Haptic Patterns'),
                const SizedBox(height: 8),
                _HapticPreviewCard(haptics: _haptics),

                const SizedBox(height: 24),

                // ── About ─────────────────────────────────────────────────
                _InfoCard(
                  icon: Icons.info_outline_rounded,
                  text:
                      'Critical Alerts (iOS) bypass Do Not Disturb and mute '
                      'switches. These require a special Apple entitlement and '
                      'are intended for safety-critical health notifications only.',
                ),
              ],
            ),
    );
  }
}

// ── Channel settings card ──────────────────────────────────────────────────────
class _ChannelSettingCard extends StatelessWidget {
  final String channelId;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final bool isEnabled;
  final bool isCritical;
  final int ignoredCount;
  final int silentThreshold;
  final ValueChanged<bool> onToggle;
  final ValueChanged<bool> onCriticalToggle;
  final VoidCallback onHapticPreview;

  const _ChannelSettingCard({
    required this.channelId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.isEnabled,
    required this.isCritical,
    required this.ignoredCount,
    required this.silentThreshold,
    required this.onToggle,
    required this.onCriticalToggle,
    required this.onHapticPreview,
  });

  bool get _atSilentThreshold => ignoredCount >= silentThreshold;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          // ── Main toggle ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A1A2E))),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  onChanged: onToggle,
                  activeColor: const Color(0xFF00897B),
                ),
              ],
            ),
          ),

          // ── Silent Mode Detection warning ───────────────────────────────
          if (_atSilentThreshold) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.notifications_off_rounded,
                      size: 16, color: Color(0xFFF57C00)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Silent Mode Detected — $ignoredCount notifications ignored. '
                      'Upgrade to Critical Alerts to ensure you never miss a dose.',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFE65100), height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Critical Alerts toggle ──────────────────────────────────────
          if (isEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  Icon(
                    Icons.notification_important_rounded,
                    size: 16,
                    color: isCritical
                        ? const Color(0xFFE53935)
                        : Colors.grey[400],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Critical Alerts',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: isCritical
                                ? const Color(0xFFE53935)
                                : const Color(0xFF555566),
                          ),
                        ),
                        Text(
                          'Bypasses Do Not Disturb and mute',
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isCritical,
                    onChanged: onCriticalToggle,
                    activeColor: const Color(0xFFE53935),
                  ),
                ],
              ),
            ),
          ],

          // ── Haptic preview ──────────────────────────────────────────────
          if (isEnabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                onHapticPreview();
              },
              icon: const Icon(Icons.vibration_rounded,
                  size: 16, color: Color(0xFF9E9E9E)),
              label: const Text(
                'Preview Haptic',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF9E9E9E)),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Haptic preview card ───────────────────────────────────────────────────────
class _HapticPreviewCard extends StatelessWidget {
  final HapticService haptics;

  const _HapticPreviewCard({required this.haptics});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tap to feel each pattern:',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF555566)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HapticButton(
                  label: 'Medicine\nReminder',
                  description: 'Short, sharp\ndouble pulse',
                  icon: Icons.medication_rounded,
                  color: const Color(0xFF00897B),
                  onTap: () => haptics.medicineReminder(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HapticButton(
                  label: 'Goal\nSuccess',
                  description: 'Long,\ncelebratory',
                  icon: Icons.emoji_events_rounded,
                  color: const Color(0xFFF57C00),
                  onTap: () => haptics.goalSuccess(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HapticButton extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HapticButton({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: color.withOpacity(0.12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Icon(icon, size: 26, color: color),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: color.withOpacity(0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Colors.grey[500],
          letterSpacing: 0.8,
        ),
      );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoCard({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: Colors.grey[400]),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 12.5, color: Colors.grey[500], height: 1.5),
              ),
            ),
          ],
        ),
      );
}
