// lib/features/home/home_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:gap/gap.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/capture_models.dart';
import '../camera/camera_screen.dart';
import '../camera/providers/camera_providers.dart';
import '../session/session_dashboard_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    await ref.read(sessionProvider.notifier).createSession(name);
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SessionDashboardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Gap(20),

              // Header
              Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  ),
                  child: const Icon(Icons.camera_enhance,
                      color: AppColors.primary, size: 20),
                ),
                const Gap(12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CERAMIC CAPTURE',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: AppColors.textPrimary)),
                    Text('Stage 1 — Photogrammetry Rig',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ]).animate().fadeIn(duration: 400.ms),

              const Gap(40),

              // Stage overview cards
              const Text('CAPTURE STAGES',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 2,
                      color: AppColors.textSecondary)),
              const Gap(12),
              ...capturePassSequence.asMap().entries.map((e) {
                final cfg = passConfigs[e.value]!;
                return _StageCard(config: cfg, index: e.key)
                    .animate(delay: (e.key * 60).ms)
                    .fadeIn()
                    .slideX(begin: 0.1, end: 0);
              }),

              const Spacer(),

              // New session panel
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.3), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('NEW SESSION',
                        style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 2,
                            color: AppColors.textSecondary)),
                    const Gap(12),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Piece name (e.g. Tang Dynasty Vase)',
                        hintStyle: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 13),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                    ),
                    const Gap(12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _startSession,
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('BEGIN CAPTURE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w800, letterSpacing: 1),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.1, end: 0),

              const Gap(12),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageCard extends StatelessWidget {
  final PassConfig config;
  final int index;
  const _StageCard({required this.config, required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: config.color.withOpacity(0.25), width: 1),
      ),
      child: Row(children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: config.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(config.icon, color: config.color, size: 14),
        ),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(config.title,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text(config.subtitle,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: config.color.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: config.color.withOpacity(0.5)),
          ),
          child: Center(
            child: Text('${index + 1}',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: config.color)),
          ),
        ),
      ]),
    );
  }
}
