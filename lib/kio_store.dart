import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class AssetImportException implements Exception {
  AssetImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AssetImportResult {
  AssetImportResult({required this.asset, required this.isDuplicate});
  final KioAsset asset;
  final bool isDuplicate;
}

class KioStore extends ChangeNotifier {
  static const _storageKey = 'kio_state_v3';
  final _uuid = const Uuid();

  KioState _state = KioState.defaultState();
  bool _isLoaded = false;
  bool _isBusy = false;

  KioState get state => _state;
  bool get isLoaded => _isLoaded;
  bool get isBusy => _isBusy;
  KioProject get selectedProject => _state.selectedProject;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        _state = KioState.decode(raw);
      } catch (_) {
        _state = KioState.defaultState();
      }
    }
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _state.encode());
  }

  Future<void> createProject() async {
    final now = DateTime.now();
    final project = KioProject(
      id: _uuid.v4(),
      name: 'Project ${_state.projects.length + 1}',
      createdAt: now,
      updatedAt: now,
      settings: ProjectSettings(),
    );
    _state = _state.copyWith(projects: [..._state.projects, project], selectedProjectId: project.id);
    await save();
    notifyListeners();
  }

  Future<void> selectProject(String id) async {
    _state = _state.copyWith(selectedProjectId: id);
    await save();
    notifyListeners();
  }

  Future<AssetImportResult?> importAssetToLibrary(KioAssetType type) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: type.extensions,
      allowMultiple: false,
      withData: false,
    );
    final picked = result?.files.single;
    final sourcePath = picked?.path;
    if (picked == null || sourcePath == null) return null;

    _isBusy = true;
    notifyListeners();
    try {
      final source = File(sourcePath);
      final checksum = await _sha256ForFile(source);
      final duplicate = _firstAsset((a) => a.type == type && a.sha256 == checksum);
      if (duplicate != null) {
        return AssetImportResult(asset: duplicate, isDuplicate: true);
      }

      final asset = type == KioAssetType.model
          ? await _importModelZip(source, picked.name, checksum)
          : await _importSingleFile(type, source, picked.name, checksum);

      _state = _state.copyWith(assets: [..._state.assets, asset]);
      await save();
      return AssetImportResult(asset: asset, isDuplicate: false);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> attachAssetToSelectedProject(KioAsset asset) async {
    final s = selectedProject.settings;
    final next = switch (asset.type) {
      KioAssetType.model => s.copyWith(modelAssetId: asset.id, playhead: 0, duration: 0),
      KioAssetType.motion => s.copyWith(motionAssetId: asset.id, playhead: 0, duration: 0),
      KioAssetType.music => s.copyWith(musicAssetId: asset.id, playhead: 0, duration: 0),
      KioAssetType.camera => s.copyWith(cameraAssetId: asset.id),
    };
    await _updateSelectedProject(selectedProject.copyWith(updatedAt: DateTime.now(), settings: next));
  }

  Future<void> renameAsset(String assetId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    _state = _state.copyWith(
      assets: _state.assets.map((a) => a.id == assetId ? a.copyWith(displayName: clean) : a).toList(),
    );
    await save();
    notifyListeners();
  }

  Future<void> updatePlayhead(int value) async {
    final s = selectedProject.settings;
    await _updateSelectedProject(
      selectedProject.copyWith(
        updatedAt: DateTime.now(),
        settings: s.copyWith(playhead: value.clamp(0, s.duration).toInt()),
      ),
    );
  }

  Future<void> updateCamera({double? orbitX, double? orbitY, double? zoom}) async {
    final s = selectedProject.settings;
    await _updateSelectedProject(
      selectedProject.copyWith(
        updatedAt: DateTime.now(),
        settings: s.copyWith(orbitX: orbitX, orbitY: orbitY, zoom: zoom),
      ),
    );
  }

  Future<void> createCameraPreset() async {
    final s = selectedProject.settings;
    final preset = CameraPreset(
      id: _uuid.v4(),
      name: 'Preset ${s.cameraPresets.length + 1}',
      orbitX: s.orbitX,
      orbitY: s.orbitY,
      zoom: s.zoom,
      createdAt: DateTime.now(),
    );
    await _updateSelectedProject(
      selectedProject.copyWith(
        updatedAt: DateTime.now(),
        settings: s.copyWith(cameraPresets: [...s.cameraPresets, preset]),
      ),
    );
  }

  Future<void> applyCameraPreset(String id) async {
    CameraPreset? found;
    for (final preset in selectedProject.settings.cameraPresets) {
      if (preset.id == id) found = preset;
    }
    if (found == null) return;
    await updateCamera(orbitX: found.orbitX, orbitY: found.orbitY, zoom: found.zoom);
  }

  Future<void> resetCameraPreset(String id) async {
    final s = selectedProject.settings;
    final next = s.cameraPresets
        .map((preset) => preset.id == id ? preset.copyWith(orbitX: s.orbitX, orbitY: s.orbitY, zoom: s.zoom) : preset)
        .toList();
    await _updateSelectedProject(
      selectedProject.copyWith(updatedAt: DateTime.now(), settings: s.copyWith(cameraPresets: next)),
    );
  }

  KioAsset? assetById(String? id) => id == null ? null : _firstAsset((a) => a.id == id);
  List<KioAsset> assetsByType(KioAssetType type) => _state.assets.where((a) => a.type == type).toList();

  Future<KioAsset> _importSingleFile(KioAssetType type, File source, String originalName, String checksum) async {
    final root = await _assetRoot(type);
    await root.create(recursive: true);
    final target = File(p.join(root.path, '${checksum.substring(0, 12)}_${_safeFileName(originalName)}'));
    await source.copy(target.path);
    return KioAsset(
      id: _uuid.v4(),
      type: type,
      displayName: p.basenameWithoutExtension(originalName),
      originalName: originalName,
      localPath: target.path,
      sha256: checksum,
      importedAt: DateTime.now(),
      entryFile: p.basename(target.path),
    );
  }

  Future<KioAsset> _importModelZip(File source, String originalName, String checksum) async {
    if (p.extension(originalName).toLowerCase() != '.zip') {
      throw AssetImportException('Model import only supports ZIP packages.');
    }

    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await source.readAsBytes(), verify: true);
    } catch (_) {
      throw AssetImportException('Invalid ZIP package.');
    }

    final files = archive.files.where((e) => e.isFile).toList();
    final modelFiles = files.where((e) {
      final n = e.name.toLowerCase();
      return n.endsWith('.pmx') || n.endsWith('.pmd');
    }).toList();

    if (modelFiles.isEmpty) {
      throw AssetImportException('Model ZIP must contain at least one PMX or PMD file.');
    }

    final root = await _assetRoot(KioAssetType.model);
    await root.create(recursive: true);
    final folder = '${checksum.substring(0, 12)}_${_safeFileName(p.basenameWithoutExtension(originalName))}';
    final targetDir = Directory(p.join(root.path, folder));
    if (targetDir.existsSync()) await targetDir.delete(recursive: true);
    await targetDir.create(recursive: true);

    for (final entry in files) {
      final relative = _safeRelativePath(entry.name);
      if (relative == null) continue;
      final out = File(p.join(targetDir.path, relative));
      await out.parent.create(recursive: true);
      final content = entry.content;
      if (content is List<int>) await out.writeAsBytes(content);
    }

    return KioAsset(
      id: _uuid.v4(),
      type: KioAssetType.model,
      displayName: p.basenameWithoutExtension(originalName),
      originalName: originalName,
      localPath: targetDir.path,
      sha256: checksum,
      importedAt: DateTime.now(),
      entryFile: _safeRelativePath(modelFiles.first.name),
    );
  }

  Future<void> _updateSelectedProject(KioProject project) async {
    _state = _state.copyWith(
      projects: _state.projects.map((p) => p.id == project.id ? project : p).toList(),
    );
    await save();
    notifyListeners();
  }

  KioAsset? _firstAsset(bool Function(KioAsset asset) test) {
    for (final asset in _state.assets) {
      if (test(asset)) return asset;
    }
    return null;
  }

  Future<Directory> _assetRoot(KioAssetType type) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'kio_assets', type.dir));
  }

  Future<String> _sha256ForFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _safeFileName(String name) {
    final out = p.basename(name).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return out.isEmpty ? 'asset' : out;
  }

  String? _safeRelativePath(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    if (normalized == '..' || normalized.startsWith('../') || p.posix.isAbsolute(normalized)) return null;
    final parts = normalized.split('/').map(_safeFileName).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    return parts.join('/');
  }
}
