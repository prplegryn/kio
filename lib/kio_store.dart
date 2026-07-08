import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class AssetImportResult {
  AssetImportResult({
    required this.asset,
    required this.isDuplicate,
  });

  final KioAsset asset;
  final bool isDuplicate;
}

class KioStore extends ChangeNotifier {
  static const _storageKey = 'kio_state_v1';
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
    _state = _state.copyWith(
      projects: [..._state.projects, project],
      selectedProjectId: project.id,
    );
    await save();
    notifyListeners();
  }

  Future<void> selectProject(String id) async {
    _state = _state.copyWith(selectedProjectId: id);
    await save();
    notifyListeners();
  }

  Future<AssetImportResult?> importAsset(KioAssetType type) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: type.extensions,
      allowMultiple: false,
      withData: false,
    );
    final picked = result?.files.single;
    final sourcePath = picked?.path;
    if (picked == null || sourcePath == null) {
      return null;
    }

    _isBusy = true;
    notifyListeners();
    try {
      final source = File(sourcePath);
      final checksum = await _sha256ForFile(source);
      final duplicate = _state.assets.where((asset) => asset.type == type && asset.sha256 == checksum).firstOrNull;
      if (duplicate != null) {
        await _attachAssetToSelectedProject(duplicate);
        return AssetImportResult(asset: duplicate, isDuplicate: true);
      }

      final root = await _assetsRoot(type);
      await root.create(recursive: true);
      final safeName = _safeFileName(picked.name);
      final copiedName = '${checksum.substring(0, 12)}_$safeName';
      final target = File(p.join(root.path, copiedName));
      await source.copy(target.path);
      final asset = KioAsset(
        id: _uuid.v4(),
        type: type,
        displayName: p.basenameWithoutExtension(picked.name),
        originalName: picked.name,
        fileName: copiedName,
        localPath: target.path,
        sha256: checksum,
        importedAt: DateTime.now(),
      );
      _state = _state.copyWith(assets: [..._state.assets, asset]);
      await _attachAssetToSelectedProject(asset);
      return AssetImportResult(asset: asset, isDuplicate: false);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> renameAsset(String assetId, String displayName) async {
    final clean = displayName.trim();
    if (clean.isEmpty) return;
    _state = _state.copyWith(
      assets: _state.assets
          .map((asset) => asset.id == assetId ? asset.copyWith(displayName: clean) : asset)
          .toList(),
    );
    await save();
    notifyListeners();
  }

  Future<void> setPlayback(bool isPlaying, Timer? timer) async {
    // Playback is driven by the widget timer. This method exists as an explicit
    // persistence point when future audio/video backends are attached.
    await save();
  }

  Future<void> updatePlayhead(int value) async {
    await _updateSelectedProject(
      selectedProject.copyWith(
        updatedAt: DateTime.now(),
        settings: selectedProject.settings.copyWith(
          playhead: value.clamp(0, selectedProject.settings.duration),
        ),
      ),
    );
  }

  Future<void> updateCamera({
    double? orbitX,
    double? orbitY,
    double? zoom,
  }) async {
    await _updateSelectedProject(
      selectedProject.copyWith(
        updatedAt: DateTime.now(),
        settings: selectedProject.settings.copyWith(
          orbitX: orbitX,
          orbitY: orbitY,
          zoom: zoom,
        ),
      ),
    );
  }

  Future<void> createCameraPreset() async {
    final settings = selectedProject.settings;
    final preset = CameraPreset(
      id: _uuid.v4(),
      name: 'Preset ${settings.cameraPresets.length + 1}',
      orbitX: settings.orbitX,
      orbitY: settings.orbitY,
      zoom: settings.zoom,
      createdAt: DateTime.now(),
    );
    await _updateSelectedProject(
      selectedProject.copyWith(
        updatedAt: DateTime.now(),
        settings: settings.copyWith(
          cameraPresets: [...settings.cameraPresets, preset],
        ),
      ),
    );
  }

  Future<void> resetCameraPreset(String presetId) async {
    final settings = selectedProject.settings;
    final updated = settings.cameraPresets.map((preset) {
      if (preset.id != presetId) return preset;
      return preset.copyWith(
        orbitX: settings.orbitX,
        orbitY: settings.orbitY,
        zoom: settings.zoom,
      );
    }).toList();
    await _updateSelectedProject(
      selectedProject.copyWith(
        updatedAt: DateTime.now(),
        settings: settings.copyWith(cameraPresets: updated),
      ),
    );
  }

  KioAsset? assetById(String? id) {
    if (id == null) return null;
    return _state.assets.where((asset) => asset.id == id).firstOrNull;
  }

  Iterable<KioAsset> assetsByType(KioAssetType type) {
    return _state.assets.where((asset) => asset.type == type);
  }

  Future<void> _attachAssetToSelectedProject(KioAsset asset) async {
    final settings = selectedProject.settings;
    final nextSettings = switch (asset.type) {
      KioAssetType.model => settings.copyWith(modelAssetId: asset.id),
      KioAssetType.motion => settings.copyWith(motionAssetId: asset.id),
      KioAssetType.music => settings.copyWith(musicAssetId: asset.id),
      KioAssetType.camera => settings.copyWith(cameraAssetId: asset.id),
    };
    await _updateSelectedProject(
      selectedProject.copyWith(
        updatedAt: DateTime.now(),
        settings: nextSettings,
      ),
    );
  }

  Future<void> _updateSelectedProject(KioProject project) async {
    _state = _state.copyWith(
      projects: _state.projects.map((item) => item.id == project.id ? project : item).toList(),
    );
    await save();
    notifyListeners();
  }

  Future<Directory> _assetsRoot(KioAssetType type) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'kio_assets', type.directoryName));
  }

  Future<String> _sha256ForFile(File file) async {
    final input = file.openRead();
    final digest = await sha256.bind(input).first;
    return digest.toString();
  }

  String _safeFileName(String name) {
    final baseName = p.basename(name).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return baseName.isEmpty ? 'asset.bin' : baseName;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
