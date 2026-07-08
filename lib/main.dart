import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'crash_log_service.dart';
import 'kio_store.dart';
import 'models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashLogService.install();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runZonedGuarded(
    () => runApp(const KioApp()),
    (error, stack) => CrashLogService.writeError(error, stack, origin: 'zone'),
  );
}

class KioApp extends StatelessWidget {
  const KioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'kio',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5F7CFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF070913),
        textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
      ),
      home: const KioWorkspace(),
    );
  }
}

class KioWorkspace extends StatefulWidget {
  const KioWorkspace({super.key});

  @override
  State<KioWorkspace> createState() => _KioWorkspaceState();
}

class _KioWorkspaceState extends State<KioWorkspace> with TickerProviderStateMixin {
  final KioStore store = KioStore();
  bool drawerOpen = false;
  bool importMenuOpen = false;
  bool presetMenuOpen = false;
  bool projectsExpanded = true;
  bool assetsExpanded = true;
  bool playing = false;
  Timer? playbackTimer;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStoreChanged);
    unawaited(store.load());
  }

  @override
  void dispose() {
    playbackTimer?.cancel();
    store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final project = store.selectedProject;
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        child: store.isLoaded
            ? Stack(
                children: [
                  Positioned.fill(
                    child: _PlayerCanvas(
                      project: project,
                      store: store,
                      onCameraChanged: _updateCameraFromGesture,
                    ),
                  ),
                  Positioned.fill(child: _SubtleChrome(isLandscape: isLandscape)),
                  _TopOverlay(
                    project: project,
                    store: store,
                    onDrawerPressed: () => setState(() => drawerOpen = !drawerOpen),
                  ),
                  _RightControls(
                    importMenuOpen: importMenuOpen,
                    presetMenuOpen: presetMenuOpen,
                    hasImportedCamera: project.settings.hasImportedCamera,
                    presets: project.settings.cameraPresets,
                    onToggleImport: () => setState(() => importMenuOpen = !importMenuOpen),
                    onTogglePreset: project.settings.hasImportedCamera
                        ? null
                        : () => setState(() => presetMenuOpen = !presetMenuOpen),
                    onImport: _importAsset,
                    onAddPreset: _createPreset,
                    onResetPreset: _resetPreset,
                  ),
                  _BottomPlayback(
                    project: project,
                    isPlaying: playing,
                    onPlayPause: _togglePlayback,
                    onSeek: (value) => unawaited(store.updatePlayhead(value.round())),
                    onStep: _stepPlayhead,
                  ),
                  _SidePanel(
                    open: drawerOpen,
                    store: store,
                    projectsExpanded: projectsExpanded,
                    assetsExpanded: assetsExpanded,
                    onClose: () => setState(() => drawerOpen = false),
                    onToggleProjects: () => setState(() => projectsExpanded = !projectsExpanded),
                    onToggleAssets: () => setState(() => assetsExpanded = !assetsExpanded),
                    onImport: _importAsset,
                    onRenameAsset: _renameAsset,
                  ),
                  if (store.isBusy) const _BusyOverlay(),
                ],
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _importAsset(KioAssetType type) async {
    final result = await store.importAsset(type);
    if (!mounted || result == null) return;
    final message = result.isDuplicate
        ? '${result.asset.displayName} is already imported.'
        : '${result.asset.displayName} imported.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _renameAsset(KioAsset asset) async {
    final controller = TextEditingController(text: asset.displayName);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename asset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (nextName != null) await store.renameAsset(asset.id, nextName);
  }

  void _togglePlayback() {
    if (playing) {
      playbackTimer?.cancel();
      playbackTimer = null;
      setState(() => playing = false);
      return;
    }
    setState(() => playing = true);
    playbackTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      final settings = store.selectedProject.settings;
      final next = settings.playhead + 80;
      if (next >= settings.duration) {
        unawaited(store.updatePlayhead(0));
      } else {
        unawaited(store.updatePlayhead(next));
      }
    });
  }

  void _stepPlayhead(int delta) {
    final settings = store.selectedProject.settings;
    unawaited(store.updatePlayhead(settings.playhead + delta));
  }

  void _updateCameraFromGesture(Offset delta, double scaleDelta) {
    final settings = store.selectedProject.settings;
    unawaited(
      store.updateCamera(
        orbitX: (settings.orbitX + delta.dx * 0.12).clamp(-180, 180),
        orbitY: (settings.orbitY + delta.dy * 0.12).clamp(-90, 90),
        zoom: (settings.zoom * scaleDelta).clamp(0.45, 2.6),
      ),
    );
  }

  Future<void> _createPreset() async {
    await store.createCameraPreset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Camera preset created.')),
    );
  }

  Future<void> _resetPreset(CameraPreset preset) async {
    await store.resetCameraPreset(preset.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${preset.name} reset to current camera.')),
    );
  }
}

class _SubtleChrome extends StatelessWidget {
  const _SubtleChrome({required this.isLandscape});

  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: isLandscape ? const Alignment(0.2, -0.2) : Alignment.topCenter,
            radius: 1.1,
            colors: const [
              Color(0x224F67FF),
              Color(0x00000000),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopOverlay extends StatelessWidget {
  const _TopOverlay({
    required this.project,
    required this.store,
    required this.onDrawerPressed,
  });

  final KioProject project;
  final KioStore store;
  final VoidCallback onDrawerPressed;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 12;
    return Positioned(
      left: 16,
      right: 16,
      top: top,
      child: Row(
        children: [
          _GlassIconButton(
            icon: Icons.menu_rounded,
            label: 'Open library',
            onTap: onDrawerPressed,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          project.name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _assetLine(store, project),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.white.withOpacity(0.62), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _Pill(text: 'screen = export', icon: Icons.fit_screen_rounded),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _assetLine(KioStore store, KioProject project) {
    final s = project.settings;
    final model = store.assetById(s.modelAssetId)?.displayName ?? 'No model';
    final motion = store.assetById(s.motionAssetId)?.displayName ?? 'No motion';
    final music = store.assetById(s.musicAssetId)?.displayName ?? 'No music';
    return '$model · $motion · $music';
  }
}

class _PlayerCanvas extends StatefulWidget {
  const _PlayerCanvas({
    required this.project,
    required this.store,
    required this.onCameraChanged,
  });

  final KioProject project;
  final KioStore store;
  final void Function(Offset delta, double scaleDelta) onCameraChanged;

  @override
  State<_PlayerCanvas> createState() => _PlayerCanvasState();
}

class _PlayerCanvasState extends State<_PlayerCanvas> {
  Offset lastFocal = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final settings = widget.project.settings;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (details) => lastFocal = details.focalPoint,
      onScaleUpdate: (details) {
        final delta = details.focalPoint - lastFocal;
        lastFocal = details.focalPoint;
        widget.onCameraChanged(delta, details.scale == 0 ? 1 : details.scale);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _StagePainter(
              orbitX: settings.orbitX,
              orbitY: settings.orbitY,
              zoom: settings.zoom,
            ),
          ),
          Center(
            child: Transform.scale(
              scale: settings.zoom,
              child: Transform.translate(
                offset: Offset(settings.orbitX * 0.18, settings.orbitY * 0.18),
                child: const _DancerFigure(),
              ),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 108,
            child: _GlassPanel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.threed_rotation_rounded, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Drag empty space to orbit · Pinch to zoom',
                    style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter({
    required this.orbitX,
    required this.orbitY,
    required this.zoom,
  });

  final double orbitX;
  final double orbitY;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF15182A), Color(0xFF090B13)],
      ).createShader(rect);
    canvas.drawRect(rect, bg);

    final glow = Paint()
      ..shader = RadialGradient(
        center: Alignment(orbitX / 250, -0.35 + orbitY / 400),
        radius: 0.9,
        colors: const [Color(0x335F7CFF), Color(0x00000000)],
      ).createShader(rect);
    canvas.drawRect(rect, glow);

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = const Color(0xFF5F7CFF).withOpacity(0.35)
      ..strokeWidth = 1.5;
    final horizon = size.height * 0.62;
    for (var i = -12; i <= 12; i++) {
      final x = size.width / 2 + i * 34 * zoom;
      canvas.drawLine(Offset(x, horizon), Offset(size.width / 2 + i * 85 * zoom, size.height), gridPaint);
    }
    for (var i = 0; i < 12; i++) {
      final y = horizon + i * i * 3.2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    canvas.drawLine(Offset(size.width / 2, horizon - 200), Offset(size.width / 2, size.height), axisPaint);
    canvas.drawLine(Offset(0, horizon + 92), Offset(size.width, horizon + 92), axisPaint);
  }

  @override
  bool shouldRepaint(covariant _StagePainter oldDelegate) {
    return orbitX != oldDelegate.orbitX || orbitY != oldDelegate.orbitY || zoom != oldDelegate.zoom;
  }
}

class _DancerFigure extends StatelessWidget {
  const _DancerFigure();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 390,
      child: CustomPaint(painter: _DancerPainter()),
    );
  }
}

class _DancerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.38);
    final stroke = Paint()
      ..color = Colors.white.withOpacity(0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = Colors.white.withOpacity(0.13)
      ..style = PaintingStyle.fill;
    final accent = Paint()
      ..color = const Color(0xFF8EA0FF).withOpacity(0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(Rect.fromCenter(center: center.translate(0, -92), width: 58, height: 62), fill);
    canvas.drawLine(center.translate(-54, -94), center.translate(-122, 18), accent);
    canvas.drawLine(center.translate(54, -94), center.translate(122, 18), accent);
    final body = Path()
      ..moveTo(center.dx - 34, center.dy - 52)
      ..lineTo(center.dx + 34, center.dy - 52)
      ..lineTo(center.dx + 45, center.dy + 48)
      ..lineTo(center.dx - 45, center.dy + 48)
      ..close();
    canvas.drawPath(body, fill);
    canvas.drawLine(center.translate(-32, -42), center.translate(-88, -118), stroke);
    canvas.drawLine(center.translate(-88, -118), center.translate(-116, -170), stroke);
    canvas.drawLine(center.translate(32, -32), center.translate(94, -10), stroke);
    canvas.drawLine(center.translate(94, -10), center.translate(124, -28), stroke);
    canvas.drawLine(center.translate(-20, 48), center.translate(-58, 132), stroke);
    canvas.drawLine(center.translate(-58, 132), center.translate(-36, 208), stroke);
    canvas.drawLine(center.translate(24, 48), center.translate(56, 138), stroke);
    canvas.drawLine(center.translate(56, 138), center.translate(98, 102), stroke);
    canvas.drawOval(Rect.fromCenter(center: center.translate(-36, 218), width: 50, height: 18), fill);
    canvas.drawOval(Rect.fromCenter(center: center.translate(106, 98), width: 46, height: 18), fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RightControls extends StatelessWidget {
  const _RightControls({
    required this.importMenuOpen,
    required this.presetMenuOpen,
    required this.hasImportedCamera,
    required this.presets,
    required this.onToggleImport,
    required this.onTogglePreset,
    required this.onImport,
    required this.onAddPreset,
    required this.onResetPreset,
  });

  final bool importMenuOpen;
  final bool presetMenuOpen;
  final bool hasImportedCamera;
  final List<CameraPreset> presets;
  final VoidCallback onToggleImport;
  final VoidCallback? onTogglePreset;
  final void Function(KioAssetType type) onImport;
  final VoidCallback onAddPreset;
  final void Function(CameraPreset preset) onResetPreset;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 122;
    return Positioned(
      right: 16,
      top: top,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _RadialFlyout(
            open: importMenuOpen,
            anchor: _GlassIconButton(
              icon: Icons.file_upload_rounded,
              label: 'Import',
              onTap: onToggleImport,
              accent: true,
            ),
            children: [
              _MiniAction(icon: KioAssetType.model.icon, label: 'Model', onTap: () => onImport(KioAssetType.model)),
              _MiniAction(icon: KioAssetType.motion.icon, label: 'Motion', onTap: () => onImport(KioAssetType.motion)),
              _MiniAction(icon: KioAssetType.music.icon, label: 'Music', onTap: () => onImport(KioAssetType.music)),
              _MiniAction(icon: KioAssetType.camera.icon, label: 'Camera', onTap: () => onImport(KioAssetType.camera)),
            ],
          ),
          const SizedBox(height: 14),
          _RadialFlyout(
            open: presetMenuOpen && !hasImportedCamera,
            anchor: _GlassIconButton(
              icon: Icons.video_camera_back_rounded,
              label: 'Preset',
              onTap: onTogglePreset,
              disabled: hasImportedCamera,
            ),
            children: [
              _MiniAction(icon: Icons.add_rounded, label: 'Add', onTap: onAddPreset),
              for (final preset in presets)
                _MiniAction(
                  icon: Icons.bookmark_rounded,
                  label: preset.name,
                  onTap: () => onResetPreset(preset),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadialFlyout extends StatelessWidget {
  const _RadialFlyout({
    required this.open,
    required this.anchor,
    required this.children,
  });

  final bool open;
  final Widget anchor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      height: 64,
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          for (var i = 0; i < children.length; i++)
            AnimatedPositioned(
              duration: Duration(milliseconds: 220 + i * 35),
              curve: Curves.easeOutCubic,
              right: open ? 74.0 + i * 72 : 0,
              top: 0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: open ? 1 : 0,
                child: IgnorePointer(ignoring: !open, child: children[i]),
              ),
            ),
          anchor,
        ],
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GlassIconButton(icon: icon, label: label, onTap: onTap, compact: true),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _BottomPlayback extends StatelessWidget {
  const _BottomPlayback({
    required this.project,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onSeek,
    required this.onStep,
  });

  final KioProject project;
  final bool isPlaying;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final void Function(int delta) onStep;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 18;
    final settings = project.settings;
    return Positioned(
      left: 18,
      right: 18,
      bottom: bottom,
      child: _GlassPanel(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                min: 0,
                max: settings.duration.toDouble(),
                value: settings.playhead.clamp(0, settings.duration).toDouble(),
                onChanged: onSeek,
              ),
            ),
            Row(
              children: [
                Text(
                  _formatTime(settings.playhead),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  ' / ${_formatTime(settings.duration)}',
                  style: TextStyle(color: Colors.white.withOpacity(0.5)),
                ),
                const Spacer(),
                _RoundButton(icon: Icons.skip_previous_rounded, onTap: () => onStep(-1000)),
                const SizedBox(width: 12),
                _RoundButton(
                  icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  onTap: onPlayPause,
                  large: true,
                ),
                const SizedBox(width: 12),
                _RoundButton(icon: Icons.skip_next_rounded, onTap: () => onStep(1000)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.open,
    required this.store,
    required this.projectsExpanded,
    required this.assetsExpanded,
    required this.onClose,
    required this.onToggleProjects,
    required this.onToggleAssets,
    required this.onImport,
    required this.onRenameAsset,
  });

  final bool open;
  final KioStore store;
  final bool projectsExpanded;
  final bool assetsExpanded;
  final VoidCallback onClose;
  final VoidCallback onToggleProjects;
  final VoidCallback onToggleAssets;
  final void Function(KioAssetType type) onImport;
  final void Function(KioAsset asset) onRenameAsset;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final panelWidth = width > 700 ? 380.0 : width * 0.82;
    return Stack(
      children: [
        if (open)
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: AnimatedOpacity(
                opacity: open ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Container(color: Colors.black.withOpacity(0.38)),
              ),
            ),
          ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          left: open ? 0 : -panelWidth - 24,
          top: 0,
          bottom: 0,
          width: panelWidth,
          child: SafeArea(
            right: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _GlassPanel(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('kio', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                        const Spacer(),
                        _GlassIconButton(icon: Icons.close_rounded, label: 'Close', onTap: onClose, compact: true),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _ExpandableBlock(
                      title: 'Projects',
                      subtitle: 'Current scene state',
                      expanded: projectsExpanded,
                      onToggle: onToggleProjects,
                      child: Column(
                        children: [
                          for (final project in store.state.projects)
                            _ProjectTile(
                              project: project,
                              selected: project.id == store.state.selectedProjectId,
                              onTap: () => unawaited(store.selectProject(project.id)),
                            ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => unawaited(store.createProject()),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('New project'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: _ExpandableBlock(
                        title: 'Assets',
                        subtitle: 'Imported local copies',
                        expanded: assetsExpanded,
                        onToggle: onToggleAssets,
                        child: Column(
                          children: [
                            _ImportRow(onImport: onImport),
                            const SizedBox(height: 10),
                            Expanded(
                              child: ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  for (final type in KioAssetType.values)
                                    _AssetGroup(
                                      type: type,
                                      assets: store.assetsByType(type).toList(),
                                      onLongPress: onRenameAsset,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandableBlock extends StatelessWidget {
  const _ExpandableBlock({
    required this.title,
    required this.subtitle,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.48))),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 240),
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: child,
            ),
            secondChild: const SizedBox(width: double.infinity),
            crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          ),
        ],
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({
    required this.project,
    required this.selected,
    required this.onTap,
  });

  final KioProject project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF5F7CFF).withOpacity(0.2) : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? const Color(0xFF8EA0FF) : Colors.white.withOpacity(0.06)),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_rounded, color: selected ? const Color(0xFFAAB6FF) : Colors.white60),
              const SizedBox(width: 10),
              Expanded(child: Text(project.name, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (selected) const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFFAAB6FF)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportRow extends StatelessWidget {
  const _ImportRow({required this.onImport});

  final void Function(KioAssetType type) onImport;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in KioAssetType.values)
          ActionChip(
            avatar: Icon(type.icon, size: 16),
            label: Text(type.label),
            onPressed: () => onImport(type),
          ),
      ],
    );
  }
}

class _AssetGroup extends StatelessWidget {
  const _AssetGroup({
    required this.type,
    required this.assets,
    required this.onLongPress,
  });

  final KioAssetType type;
  final List<KioAsset> assets;
  final void Function(KioAsset asset) onLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(type.label.toUpperCase(), style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.42), fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (assets.isEmpty)
            Text('No ${type.label.toLowerCase()} assets', style: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 12))
          else
            for (final asset in assets)
              GestureDetector(
                onLongPress: () => onLongPress(asset),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      Icon(type.icon, color: const Color(0xFFAAB6FF), size: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(asset.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(asset.originalName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.44))),
                          ],
                        ),
                      ),
                      const Icon(Icons.more_horiz_rounded, size: 18),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.35)),
        child: const Center(
          child: _GlassPanel(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Copying asset into kio...'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
    this.accent = false,
    this.disabled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool compact;
  final bool accent;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 50.0 : 58.0;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: disabled
                ? Colors.white.withOpacity(0.08)
                : accent
                    ? const Color(0xFF5F7CFF).withOpacity(0.92)
                    : Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(accent ? 0.18 : 0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(icon, color: disabled ? Colors.white38 : Colors.white, size: compact ? 22 : 25),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.large = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: large ? 56 : 42,
        height: large ? 56 : 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: large ? Colors.white : Colors.white.withOpacity(0.1),
        ),
        child: Icon(icon, color: large ? const Color(0xFF121525) : Colors.white),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: const Color(0xFF121525).withOpacity(0.72),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.11)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.26),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF5F7CFF).withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF8EA0FF).withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFAAB6FF)),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFAAB6FF))),
        ],
      ),
    );
  }
}
