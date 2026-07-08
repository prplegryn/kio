import 'dart:async';
import 'dart:math' as math;

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
  runZonedGuarded(
    () => runApp(const KioApp()),
    (error, stack) => CrashLogService.writeError(error, stack, origin: 'zone'),
  );
}

class KioApp extends StatelessWidget {
  const KioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp(
      title: 'kio',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        scaffoldBackgroundColor: KioColors.bg,
        textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: Colors.white),
      ),
      home: const KioWorkspace(),
    );
  }
}

class KioColors {
  static const bg = Color(0xFF07080D);
  static const panel = Color(0xFF11141D);
  static const panel2 = Color(0xFF181C28);
  static const line = Color(0xFF2A3040);
  static const muted = Color(0xFF8A91A3);
  static const blue = Color(0xFF6D83FF);
  static const disabled = Color(0xFF343948);
}

class KioWorkspace extends StatefulWidget {
  const KioWorkspace({super.key});

  @override
  State<KioWorkspace> createState() => _KioWorkspaceState();
}

class _KioWorkspaceState extends State<KioWorkspace> {
  final store = KioStore();
  Timer? timer;
  bool drawerOpen = false;
  bool importOpen = false;
  bool presetOpen = false;
  bool projectsOpen = true;
  bool assetsOpen = true;
  bool playing = false;

  @override
  void initState() {
    super.initState();
    store.addListener(_refresh);
    unawaited(store.load());
  }

  @override
  void dispose() {
    timer?.cancel();
    store.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (!store.isLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    final project = store.selectedProject;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _PlayerCanvas(project: project, store: store, onCameraChanged: _updateCamera)),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: _IconTile(icon: Icons.menu_rounded, label: 'Library', onTap: () => setState(() => drawerOpen = true)),
          ),
          _RightControls(
            project: project,
            importOpen: importOpen,
            presetOpen: presetOpen,
            onToggleImport: () => setState(() => importOpen = !importOpen),
            onTogglePreset: project.settings.hasImportedCamera ? null : () => setState(() => presetOpen = !presetOpen),
            onSelectAsset: _showAssetPicker,
            onAddPreset: _addPreset,
            onApplyPreset: (preset) => unawaited(store.applyCameraPreset(preset.id)),
            onResetPreset: _resetPreset,
          ),
          _BottomPlayback(
            project: project,
            playing: playing,
            onPlayPause: _togglePlayback,
            onSeek: (v) => unawaited(store.updatePlayhead(v.round())),
          ),
          _SidePanel(
            open: drawerOpen,
            store: store,
            projectsOpen: projectsOpen,
            assetsOpen: assetsOpen,
            onClose: () => setState(() => drawerOpen = false),
            onToggleProjects: () => setState(() => projectsOpen = !projectsOpen),
            onToggleAssets: () => setState(() => assetsOpen = !assetsOpen),
            onCreateProject: () => unawaited(store.createProject()),
            onSelectProject: (id) => unawaited(store.selectProject(id)),
            onImportAsset: _importAsset,
            onRenameAsset: _renameAsset,
          ),
          if (store.isBusy) const Positioned.fill(child: ColoredBox(color: Color(0x99000000), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))),
        ],
      ),
    );
  }

  Future<void> _importAsset(KioAssetType type) async {
    try {
      final result = await store.importAssetToLibrary(type);
      if (!mounted || result == null) return;
      _toast(result.isDuplicate ? '${result.asset.displayName} already exists.' : '${result.asset.displayName} imported.');
    } on AssetImportException catch (e) {
      _toast(e.message);
    } catch (e, s) {
      await CrashLogService.writeError(e, s, origin: 'asset-import');
      _toast('Import failed. Crash log saved.');
    }
  }

  Future<void> _showAssetPicker(KioAssetType type) async {
    final assets = store.assetsByType(type);
    if (assets.isEmpty) {
      _toast('Import ${type.label.toLowerCase()} assets from Library first.');
      return;
    }
    final picked = await showDialog<KioAsset>(
      context: context,
      builder: (_) => _AssetPickerDialog(type: type, assets: assets),
    );
    if (picked != null) {
      await store.attachAssetToSelectedProject(picked);
      _toast('${picked.displayName} applied.');
    }
  }

  Future<void> _renameAsset(KioAsset asset) async {
    final c = TextEditingController(text: asset.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KioColors.panel,
        title: const Text('Rename asset'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) await store.renameAsset(asset.id, name);
  }

  void _togglePlayback() {
    final duration = store.selectedProject.settings.duration;
    if (duration <= 0) {
      _toast('No playable timeline yet.');
      return;
    }
    if (playing) {
      timer?.cancel();
      timer = null;
      setState(() => playing = false);
      return;
    }
    setState(() => playing = true);
    timer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      final s = store.selectedProject.settings;
      unawaited(store.updatePlayhead(s.playhead + 80 >= s.duration ? 0 : s.playhead + 80));
    });
  }

  void _updateCamera(Offset delta, double scale) {
    final s = store.selectedProject.settings;
    unawaited(store.updateCamera(
      orbitX: (s.orbitX + delta.dx * .12).clamp(-180.0, 180.0).toDouble(),
      orbitY: (s.orbitY + delta.dy * .12).clamp(-90.0, 90.0).toDouble(),
      zoom: (s.zoom * scale).clamp(.45, 2.6).toDouble(),
    ));
  }

  Future<void> _addPreset() async {
    await store.createCameraPreset();
    _toast('Camera preset created.');
  }

  Future<void> _resetPreset(CameraPreset preset) async {
    await store.resetCameraPreset(preset.id);
    _toast('${preset.name} reset.');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }
}

class _PlayerCanvas extends StatefulWidget {
  const _PlayerCanvas({required this.project, required this.store, required this.onCameraChanged});
  final KioProject project;
  final KioStore store;
  final void Function(Offset delta, double scale) onCameraChanged;

  @override
  State<_PlayerCanvas> createState() => _PlayerCanvasState();
}

class _PlayerCanvasState extends State<_PlayerCanvas> {
  Offset last = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final s = widget.project.settings;
    final model = widget.store.assetById(s.modelAssetId);
    final motion = widget.store.assetById(s.motionAssetId);
    final music = widget.store.assetById(s.musicAssetId);
    final camera = widget.store.assetById(s.cameraAssetId);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (d) => last = d.focalPoint,
      onScaleUpdate: (d) {
        final delta = d.focalPoint - last;
        last = d.focalPoint;
        widget.onCameraChanged(delta, d.scale == 0 ? 1 : d.scale);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _StagePainter(orbitX: s.orbitX, orbitY: s.orbitY, zoom: s.zoom)),
          Center(child: _SelectionSummary(model: model, motion: motion, music: music, camera: camera)),
        ],
      ),
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.model, required this.motion, required this.music, required this.camera});
  final KioAsset? model;
  final KioAsset? motion;
  final KioAsset? music;
  final KioAsset? camera;

  @override
  Widget build(BuildContext context) {
    final rows = [(KioAssetType.model, model), (KioAssetType.motion, motion), (KioAssetType.music, music), (KioAssetType.camera, camera)];
    final empty = rows.every((r) => r.$2 == null);
    return Container(
      width: 250,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: KioColors.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: KioColors.line)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(empty ? 'No project assets selected' : 'Current project', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          for (final row in rows) _AssetMiniLine(type: row.$1, asset: row.$2),
        ],
      ),
    );
  }
}

class _AssetMiniLine extends StatelessWidget {
  const _AssetMiniLine({required this.type, required this.asset});
  final KioAssetType type;
  final KioAsset? asset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(type.icon, size: 15, color: asset == null ? KioColors.muted : KioColors.blue),
          const SizedBox(width: 8),
          SizedBox(width: 48, child: Text(type.label, style: const TextStyle(fontSize: 11, color: KioColors.muted))),
          Expanded(child: Text(asset?.displayName ?? 'Not selected', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _StagePainter extends CustomPainter {
  _StagePainter({required this.orbitX, required this.orbitY, required this.zoom});
  final double orbitX;
  final double orbitY;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF10131D), Color(0xFF07080D)]).createShader(rect));
    final grid = Paint()..color = const Color(0xFF23283A)..strokeWidth = 1;
    final axis = Paint()..color = KioColors.blue..strokeWidth = 1.2;
    final horizon = size.height * .62 + orbitY * .15;
    for (var i = -16; i <= 16; i++) {
      final x = size.width / 2 + i * 30 * zoom;
      canvas.drawLine(Offset(x, horizon), Offset(size.width / 2 + i * 78 * zoom, size.height), grid);
    }
    for (var i = 0; i < 12; i++) {
      final y = horizon + i * i * 3.1;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    canvas.drawLine(Offset(size.width / 2 + orbitX * .2, horizon - 180), Offset(size.width / 2 + orbitX * .2, size.height), axis);
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => orbitX != old.orbitX || orbitY != old.orbitY || zoom != old.zoom;
}


class _RightControls extends StatelessWidget {
  const _RightControls({
    required this.project,
    required this.importOpen,
    required this.presetOpen,
    required this.onToggleImport,
    required this.onTogglePreset,
    required this.onSelectAsset,
    required this.onAddPreset,
    required this.onApplyPreset,
    required this.onResetPreset,
  });

  final KioProject project;
  final bool importOpen;
  final bool presetOpen;
  final VoidCallback onToggleImport;
  final VoidCallback? onTogglePreset;
  final void Function(KioAssetType type) onSelectAsset;
  final VoidCallback onAddPreset;
  final void Function(CameraPreset preset) onApplyPreset;
  final void Function(CameraPreset preset) onResetPreset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      top: MediaQuery.of(context).padding.top + 70,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _Flyout(
            open: importOpen,
            anchor: _IconTile(icon: Icons.add_rounded, label: 'Use', onTap: onToggleImport, accent: true),
            children: [
              for (final type in KioAssetType.values)
                _MiniTile(icon: type.icon, label: type.label, onTap: () => onSelectAsset(type)),
            ],
          ),
          const SizedBox(height: 8),
          _Flyout(
            open: presetOpen,
            anchor: _IconTile(icon: Icons.photo_camera_rounded, label: 'Preset', onTap: onTogglePreset, disabled: onTogglePreset == null),
            children: [
              _MiniTile(icon: Icons.add_rounded, label: 'Add', onTap: onAddPreset),
              for (final preset in project.settings.cameraPresets)
                _MiniTile(
                  icon: Icons.bookmark_rounded,
                  label: preset.name,
                  onTap: () => onApplyPreset(preset),
                  onLongPress: () => onResetPreset(preset),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Flyout extends StatelessWidget {
  const _Flyout({required this.open, required this.anchor, required this.children});
  final bool open;
  final Widget anchor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: open ? Row(children: [...children, const SizedBox(width: 8)]) : const SizedBox.shrink(),
        ),
        anchor,
      ],
    );
  }
}

class _BottomPlayback extends StatelessWidget {
  const _BottomPlayback({required this.project, required this.playing, required this.onPlayPause, required this.onSeek});
  final KioProject project;
  final bool playing;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    final s = project.settings;
    final max = math.max(0, s.duration).toDouble();
    return Positioned(
      left: 8,
      right: 8,
      bottom: MediaQuery.of(context).padding.bottom + 8,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        decoration: BoxDecoration(color: KioColors.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: KioColors.line)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
              child: Slider(value: max <= 0 ? 0 : s.playhead.clamp(0, s.duration).toDouble(), min: 0, max: max <= 0 ? 1 : max, onChanged: max <= 0 ? null : onSeek),
            ),
            Row(
              children: [
                Text(_formatTime(s.playhead), style: const TextStyle(fontSize: 10, color: KioColors.muted)),
                const Spacer(),
                _RoundButton(icon: Icons.skip_previous_rounded, onTap: () {}),
                const SizedBox(width: 8),
                _RoundButton(icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded, onTap: onPlayPause, primary: true),
                const SizedBox(width: 8),
                _RoundButton(icon: Icons.skip_next_rounded, onTap: () {}),
                const Spacer(),
                Text(_formatTime(s.duration), style: const TextStyle(fontSize: 10, color: KioColors.muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(int ms) {
  final total = math.max(0, ms ~/ 1000);
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.open,
    required this.store,
    required this.projectsOpen,
    required this.assetsOpen,
    required this.onClose,
    required this.onToggleProjects,
    required this.onToggleAssets,
    required this.onCreateProject,
    required this.onSelectProject,
    required this.onImportAsset,
    required this.onRenameAsset,
  });

  final bool open;
  final KioStore store;
  final bool projectsOpen;
  final bool assetsOpen;
  final VoidCallback onClose;
  final VoidCallback onToggleProjects;
  final VoidCallback onToggleAssets;
  final VoidCallback onCreateProject;
  final ValueChanged<String> onSelectProject;
  final ValueChanged<KioAssetType> onImportAsset;
  final ValueChanged<KioAsset> onRenameAsset;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: open ? 0 : -296,
      top: 0,
      bottom: 0,
      width: 296,
      child: Material(
        color: KioColors.panel,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                child: Row(
                  children: [
                    const Text('Library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close_rounded, size: 20), onPressed: onClose),
                  ],
                ),
              ),
              const Divider(height: 1, color: KioColors.line),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(10),
                  children: [
                    _SectionHeader(title: 'Projects', open: projectsOpen, onTap: onToggleProjects),
                    if (projectsOpen) ...[
                      for (final project in store.state.projects)
                        _ProjectTile(project: project, selected: project.id == store.state.selectedProjectId, onTap: () => onSelectProject(project.id)),
                      _SmallButton(icon: Icons.add_rounded, label: 'New project', onTap: onCreateProject),
                    ],
                    const SizedBox(height: 12),
                    _SectionHeader(title: 'Assets', open: assetsOpen, onTap: onToggleAssets),
                    if (assetsOpen) ...[
                      _ImportAssetRow(onImportAsset: onImportAsset),
                      const SizedBox(height: 8),
                      if (store.state.assets.isEmpty) const _EmptyHint('No imported assets.'),
                      for (final asset in store.state.assets)
                        _AssetTile(asset: asset, onLongPress: () => onRenameAsset(asset)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.open, required this.onTap});
  final String title;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: KioColors.muted)),
            const Spacer(),
            Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project, required this.selected, required this.onTap});
  final KioProject project;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ListCard(icon: Icons.folder_rounded, title: project.name, subtitle: selected ? 'Active project' : 'Tap to switch', selected: selected, onTap: onTap);
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({required this.asset, required this.onLongPress});
  final KioAsset asset;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final hint = asset.type == KioAssetType.model ? 'ZIP package' : asset.originalName;
    return _ListCard(icon: asset.type.icon, title: asset.displayName, subtitle: '${asset.type.label} · $hint', onLongPress: onLongPress);
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.icon, required this.title, required this.subtitle, this.selected = false, this.onTap, this.onLongPress});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF202640) : KioColors.panel2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? KioColors.blue : KioColors.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? KioColors.blue : KioColors.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: KioColors.muted)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}


class _ImportAssetRow extends StatelessWidget {
  const _ImportAssetRow({required this.onImportAsset});
  final ValueChanged<KioAssetType> onImportAsset;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final type in KioAssetType.values)
          _SmallButton(icon: type.icon, label: type.label, onTap: () => onImportAsset(type)),
      ],
    );
  }
}

class _AssetPickerDialog extends StatelessWidget {
  const _AssetPickerDialog({required this.type, required this.assets});
  final KioAssetType type;
  final List<KioAsset> assets;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KioColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
              child: Row(
                children: [
                  Icon(type.icon, size: 18, color: KioColors.blue),
                  const SizedBox(width: 8),
                  Text('Choose ${type.label}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, size: 19)),
                ],
              ),
            ),
            const Divider(height: 1, color: KioColors.line),
            Flexible(
              child: ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: assets.length,
                itemBuilder: (_, i) => _ListCard(
                  icon: assets[i].type.icon,
                  title: assets[i].displayName,
                  subtitle: assets[i].originalName,
                  onTap: () => Navigator.pop(context, assets[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.label, required this.onTap, this.accent = false, this.disabled = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final color = disabled ? KioColors.disabled : (accent ? KioColors.blue : KioColors.panel);
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 54,
        height: 46,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14), border: Border.all(color: accent && !disabled ? KioColors.blue : KioColors.line)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  const _MiniTile({required this.icon, required this.label, required this.onTap, this.onLongPress});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 50,
        height: 42,
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(color: KioColors.panel, borderRadius: BorderRadius.circular(13), border: Border.all(color: KioColors.line)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15),
            const SizedBox(height: 2),
            Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, this.primary = false});
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: primary ? 42 : 34,
        height: primary ? 42 : 34,
        decoration: BoxDecoration(
          color: primary ? KioColors.blue : KioColors.panel2,
          shape: BoxShape.circle,
          border: Border.all(color: primary ? KioColors.blue : KioColors.line),
        ),
        child: Icon(icon, size: primary ? 24 : 20),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(color: KioColors.panel2, borderRadius: BorderRadius.circular(11), border: Border.all(color: KioColors.line)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: KioColors.blue),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: KioColors.panel2, borderRadius: BorderRadius.circular(12), border: Border.all(color: KioColors.line)),
      child: Text(text, style: const TextStyle(fontSize: 11, color: KioColors.muted)),
    );
  }
}
