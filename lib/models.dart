import 'dart:convert';
import 'package:flutter/material.dart';

enum KioAssetType { model, motion, face, music, camera }

extension KioAssetTypeX on KioAssetType {
  String get label => switch (this) {
        KioAssetType.model => 'Model',
        KioAssetType.motion => 'Motion',
        KioAssetType.face => 'Face',
        KioAssetType.music => 'Music',
        KioAssetType.camera => 'Camera',
      };

  String get dir => switch (this) {
        KioAssetType.model => 'models',
        KioAssetType.motion => 'motions',
        KioAssetType.face => 'faces',
        KioAssetType.music => 'music',
        KioAssetType.camera => 'cameras',
      };

  IconData get icon => switch (this) {
        KioAssetType.model => Icons.view_in_ar_rounded,
        KioAssetType.motion => Icons.directions_run_rounded,
        KioAssetType.face => Icons.face_rounded,
        KioAssetType.music => Icons.music_note_rounded,
        KioAssetType.camera => Icons.videocam_rounded,
      };

  List<String> get extensions => switch (this) {
        KioAssetType.model => const ['zip'],
        KioAssetType.motion => const ['vmd', 'nmd'],
        KioAssetType.face => const ['vmd', 'nmd'],
        KioAssetType.music => const ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'],
        KioAssetType.camera => const ['vmd', 'nmd'],
      };

  static KioAssetType fromName(String name) {
    for (final type in KioAssetType.values) {
      if (type.name == name) return type;
    }
    return KioAssetType.model;
  }
}

class KioAsset {
  KioAsset({
    required this.id,
    required this.type,
    required this.displayName,
    required this.originalName,
    required this.localPath,
    required this.sha256,
    required this.importedAt,
    this.durationMs = 0,
    this.entryFile,
  });

  final String id;
  final KioAssetType type;
  final String displayName;
  final String originalName;
  final String localPath;
  final String sha256;
  final DateTime importedAt;
  final int durationMs;
  final String? entryFile;

  KioAsset copyWith({String? displayName, int? durationMs}) {
    return KioAsset(
      id: id,
      type: type,
      displayName: displayName ?? this.displayName,
      originalName: originalName,
      localPath: localPath,
      sha256: sha256,
      importedAt: importedAt,
      durationMs: durationMs ?? this.durationMs,
      entryFile: entryFile,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'displayName': displayName,
        'originalName': originalName,
        'localPath': localPath,
        'sha256': sha256,
        'importedAt': importedAt.toIso8601String(),
        'durationMs': durationMs,
        'entryFile': entryFile,
      };

  factory KioAsset.fromJson(Map<String, dynamic> json) => KioAsset(
        id: json['id'] as String,
        type: KioAssetTypeX.fromName(json['type'] as String),
        displayName: json['displayName'] as String,
        originalName: json['originalName'] as String,
        localPath: json['localPath'] as String,
        sha256: json['sha256'] as String,
        importedAt: DateTime.parse(json['importedAt'] as String),
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        entryFile: json['entryFile'] as String?,
      );
}

class CameraPreset {
  CameraPreset({
    required this.id,
    required this.name,
    required this.orbitX,
    required this.orbitY,
    required this.zoom,
    required this.createdAt,
  });

  final String id;
  final String name;
  final double orbitX;
  final double orbitY;
  final double zoom;
  final DateTime createdAt;

  CameraPreset copyWith({double? orbitX, double? orbitY, double? zoom}) {
    return CameraPreset(
      id: id,
      name: name,
      orbitX: orbitX ?? this.orbitX,
      orbitY: orbitY ?? this.orbitY,
      zoom: zoom ?? this.zoom,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'orbitX': orbitX,
        'orbitY': orbitY,
        'zoom': zoom,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CameraPreset.fromJson(Map<String, dynamic> json) => CameraPreset(
        id: json['id'] as String,
        name: json['name'] as String,
        orbitX: (json['orbitX'] as num).toDouble(),
        orbitY: (json['orbitY'] as num).toDouble(),
        zoom: (json['zoom'] as num).toDouble(),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

class ProjectSettings {
  ProjectSettings({
    this.modelAssetId,
    this.motionAssetId,
    this.faceAssetId,
    this.musicAssetId,
    this.cameraAssetId,
    this.playhead = 0,
    this.duration = 0,
    this.orbitX = 0,
    this.orbitY = 0,
    this.zoom = 1,
    this.cameraPresets = const [],
  });

  final String? modelAssetId;
  final String? motionAssetId;
  final String? faceAssetId;
  final String? musicAssetId;
  final String? cameraAssetId;
  final int playhead;
  final int duration;
  final double orbitX;
  final double orbitY;
  final double zoom;
  final List<CameraPreset> cameraPresets;

  bool get hasImportedCamera => cameraAssetId != null;

  ProjectSettings copyWith({
    Object? modelAssetId = _sentinel,
    Object? motionAssetId = _sentinel,
    Object? faceAssetId = _sentinel,
    Object? musicAssetId = _sentinel,
    Object? cameraAssetId = _sentinel,
    int? playhead,
    int? duration,
    double? orbitX,
    double? orbitY,
    double? zoom,
    List<CameraPreset>? cameraPresets,
  }) {
    return ProjectSettings(
      modelAssetId: modelAssetId == _sentinel ? this.modelAssetId : modelAssetId as String?,
      motionAssetId: motionAssetId == _sentinel ? this.motionAssetId : motionAssetId as String?,
      faceAssetId: faceAssetId == _sentinel ? this.faceAssetId : faceAssetId as String?,
      musicAssetId: musicAssetId == _sentinel ? this.musicAssetId : musicAssetId as String?,
      cameraAssetId: cameraAssetId == _sentinel ? this.cameraAssetId : cameraAssetId as String?,
      playhead: playhead ?? this.playhead,
      duration: duration ?? this.duration,
      orbitX: orbitX ?? this.orbitX,
      orbitY: orbitY ?? this.orbitY,
      zoom: zoom ?? this.zoom,
      cameraPresets: cameraPresets ?? this.cameraPresets,
    );
  }

  Map<String, dynamic> toJson() => {
        'modelAssetId': modelAssetId,
        'motionAssetId': motionAssetId,
        'faceAssetId': faceAssetId,
        'musicAssetId': musicAssetId,
        'cameraAssetId': cameraAssetId,
        'playhead': playhead,
        'duration': duration,
        'orbitX': orbitX,
        'orbitY': orbitY,
        'zoom': zoom,
        'cameraPresets': cameraPresets.map((e) => e.toJson()).toList(),
      };

  factory ProjectSettings.fromJson(Map<String, dynamic> json) => ProjectSettings(
        modelAssetId: json['modelAssetId'] as String?,
        motionAssetId: json['motionAssetId'] as String?,
        faceAssetId: json['faceAssetId'] as String?,
        musicAssetId: json['musicAssetId'] as String?,
        cameraAssetId: json['cameraAssetId'] as String?,
        playhead: (json['playhead'] as num?)?.toInt() ?? 0,
        duration: (json['duration'] as num?)?.toInt() ?? 0,
        orbitX: (json['orbitX'] as num?)?.toDouble() ?? 0,
        orbitY: (json['orbitY'] as num?)?.toDouble() ?? 0,
        zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
        cameraPresets: (json['cameraPresets'] as List<dynamic>? ?? const [])
            .map((e) => CameraPreset.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class KioProject {
  KioProject({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.settings,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ProjectSettings settings;

  KioProject copyWith({String? name, DateTime? updatedAt, ProjectSettings? settings}) {
    return KioProject(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      settings: settings ?? this.settings,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'settings': settings.toJson(),
      };

  factory KioProject.fromJson(Map<String, dynamic> json) => KioProject(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        settings: ProjectSettings.fromJson(json['settings'] as Map<String, dynamic>),
      );
}

class KioState {
  KioState({
    required this.projects,
    required this.assets,
    required this.selectedProjectId,
  });

  final List<KioProject> projects;
  final List<KioAsset> assets;
  final String selectedProjectId;

  KioProject get selectedProject {
    for (final project in projects) {
      if (project.id == selectedProjectId) return project;
    }
    return projects.first;
  }

  KioState copyWith({List<KioProject>? projects, List<KioAsset>? assets, String? selectedProjectId}) {
    return KioState(
      projects: projects ?? this.projects,
      assets: assets ?? this.assets,
      selectedProjectId: selectedProjectId ?? this.selectedProjectId,
    );
  }

  Map<String, dynamic> toJson() => {
        'projects': projects.map((e) => e.toJson()).toList(),
        'assets': assets.map((e) => e.toJson()).toList(),
        'selectedProjectId': selectedProjectId,
      };

  factory KioState.fromJson(Map<String, dynamic> json) {
    final loadedProjects = (json['projects'] as List<dynamic>? ?? const [])
        .map((e) => KioProject.fromJson(e as Map<String, dynamic>))
        .toList();
    final projects = loadedProjects.isEmpty ? KioState.defaultState().projects : loadedProjects;
    return KioState(
      projects: projects,
      assets: (json['assets'] as List<dynamic>? ?? const [])
          .map((e) => KioAsset.fromJson(e as Map<String, dynamic>))
          .toList(),
      selectedProjectId: json['selectedProjectId'] as String? ?? projects.first.id,
    );
  }

  static KioState defaultState() {
    final now = DateTime.now();
    final project = KioProject(
      id: 'default-project',
      name: 'Project 1',
      createdAt: now,
      updatedAt: now,
      settings: ProjectSettings(),
    );
    return KioState(projects: [project], assets: const [], selectedProjectId: project.id);
  }

  String encode() => jsonEncode(toJson());
  static KioState decode(String raw) => KioState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

const Object _sentinel = Object();
