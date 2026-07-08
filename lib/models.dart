import 'dart:convert';

import 'package:flutter/material.dart';

enum KioAssetType { model, motion, music, camera }

extension KioAssetTypeX on KioAssetType {
  String get label {
    switch (this) {
      case KioAssetType.model:
        return 'Model';
      case KioAssetType.motion:
        return 'Motion';
      case KioAssetType.music:
        return 'Music';
      case KioAssetType.camera:
        return 'Camera';
    }
  }

  String get directoryName {
    switch (this) {
      case KioAssetType.model:
        return 'models';
      case KioAssetType.motion:
        return 'motions';
      case KioAssetType.music:
        return 'music';
      case KioAssetType.camera:
        return 'cameras';
    }
  }

  IconData get icon {
    switch (this) {
      case KioAssetType.model:
        return Icons.view_in_ar_rounded;
      case KioAssetType.motion:
        return Icons.directions_run_rounded;
      case KioAssetType.music:
        return Icons.music_note_rounded;
      case KioAssetType.camera:
        return Icons.videocam_rounded;
    }
  }

  List<String> get extensions {
    switch (this) {
      case KioAssetType.model:
        return const ['pmx', 'pmd', 'zip'];
      case KioAssetType.motion:
        return const ['vmd', 'nmd'];
      case KioAssetType.music:
        return const ['mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'];
      case KioAssetType.camera:
        return const ['vmd', 'nmd'];
    }
  }

  static KioAssetType fromName(String name) {
    return KioAssetType.values.firstWhere(
      (type) => type.name == name,
      orElse: () => KioAssetType.model,
    );
  }
}

class KioAsset {
  KioAsset({
    required this.id,
    required this.type,
    required this.displayName,
    required this.originalName,
    required this.fileName,
    required this.localPath,
    required this.sha256,
    required this.importedAt,
  });

  final String id;
  final KioAssetType type;
  final String displayName;
  final String originalName;
  final String fileName;
  final String localPath;
  final String sha256;
  final DateTime importedAt;

  KioAsset copyWith({
    String? id,
    KioAssetType? type,
    String? displayName,
    String? originalName,
    String? fileName,
    String? localPath,
    String? sha256,
    DateTime? importedAt,
  }) {
    return KioAsset(
      id: id ?? this.id,
      type: type ?? this.type,
      displayName: displayName ?? this.displayName,
      originalName: originalName ?? this.originalName,
      fileName: fileName ?? this.fileName,
      localPath: localPath ?? this.localPath,
      sha256: sha256 ?? this.sha256,
      importedAt: importedAt ?? this.importedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'displayName': displayName,
      'originalName': originalName,
      'fileName': fileName,
      'localPath': localPath,
      'sha256': sha256,
      'importedAt': importedAt.toIso8601String(),
    };
  }

  factory KioAsset.fromJson(Map<String, dynamic> json) {
    return KioAsset(
      id: json['id'] as String,
      type: KioAssetTypeX.fromName(json['type'] as String),
      displayName: json['displayName'] as String,
      originalName: json['originalName'] as String,
      fileName: json['fileName'] as String,
      localPath: json['localPath'] as String,
      sha256: json['sha256'] as String,
      importedAt: DateTime.parse(json['importedAt'] as String),
    );
  }
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

  CameraPreset copyWith({
    String? id,
    String? name,
    double? orbitX,
    double? orbitY,
    double? zoom,
    DateTime? createdAt,
  }) {
    return CameraPreset(
      id: id ?? this.id,
      name: name ?? this.name,
      orbitX: orbitX ?? this.orbitX,
      orbitY: orbitY ?? this.orbitY,
      zoom: zoom ?? this.zoom,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'orbitX': orbitX,
      'orbitY': orbitY,
      'zoom': zoom,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CameraPreset.fromJson(Map<String, dynamic> json) {
    return CameraPreset(
      id: json['id'] as String,
      name: json['name'] as String,
      orbitX: (json['orbitX'] as num).toDouble(),
      orbitY: (json['orbitY'] as num).toDouble(),
      zoom: (json['zoom'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class ProjectSettings {
  ProjectSettings({
    this.modelAssetId,
    this.motionAssetId,
    this.musicAssetId,
    this.cameraAssetId,
    this.playhead = 0,
    this.duration = 204000,
    this.orbitX = 0,
    this.orbitY = 0,
    this.zoom = 1,
    this.cameraPresets = const [],
  });

  final String? modelAssetId;
  final String? motionAssetId;
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

  Map<String, dynamic> toJson() {
    return {
      'modelAssetId': modelAssetId,
      'motionAssetId': motionAssetId,
      'musicAssetId': musicAssetId,
      'cameraAssetId': cameraAssetId,
      'playhead': playhead,
      'duration': duration,
      'orbitX': orbitX,
      'orbitY': orbitY,
      'zoom': zoom,
      'cameraPresets': cameraPresets.map((item) => item.toJson()).toList(),
    };
  }

  factory ProjectSettings.fromJson(Map<String, dynamic> json) {
    return ProjectSettings(
      modelAssetId: json['modelAssetId'] as String?,
      motionAssetId: json['motionAssetId'] as String?,
      musicAssetId: json['musicAssetId'] as String?,
      cameraAssetId: json['cameraAssetId'] as String?,
      playhead: (json['playhead'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 204000,
      orbitX: (json['orbitX'] as num?)?.toDouble() ?? 0,
      orbitY: (json['orbitY'] as num?)?.toDouble() ?? 0,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
      cameraPresets: (json['cameraPresets'] as List<dynamic>? ?? const [])
          .map((item) => CameraPreset.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
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

  KioProject copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    ProjectSettings? settings,
  }) {
    return KioProject(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      settings: settings ?? this.settings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'settings': settings.toJson(),
    };
  }

  factory KioProject.fromJson(Map<String, dynamic> json) {
    return KioProject(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      settings: ProjectSettings.fromJson(json['settings'] as Map<String, dynamic>),
    );
  }
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
    return projects.firstWhere(
      (project) => project.id == selectedProjectId,
      orElse: () => projects.first,
    );
  }

  KioState copyWith({
    List<KioProject>? projects,
    List<KioAsset>? assets,
    String? selectedProjectId,
  }) {
    return KioState(
      projects: projects ?? this.projects,
      assets: assets ?? this.assets,
      selectedProjectId: selectedProjectId ?? this.selectedProjectId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projects': projects.map((item) => item.toJson()).toList(),
      'assets': assets.map((item) => item.toJson()).toList(),
      'selectedProjectId': selectedProjectId,
    };
  }

  factory KioState.fromJson(Map<String, dynamic> json) {
    final projects = (json['projects'] as List<dynamic>? ?? const [])
        .map((item) => KioProject.fromJson(item as Map<String, dynamic>))
        .toList();
    final normalizedProjects = projects.isEmpty ? [KioState.defaultState().selectedProject] : projects;
    return KioState(
      projects: normalizedProjects,
      assets: (json['assets'] as List<dynamic>? ?? const [])
          .map((item) => KioAsset.fromJson(item as Map<String, dynamic>))
          .toList(),
      selectedProjectId: json['selectedProjectId'] as String? ?? normalizedProjects.first.id,
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
    return KioState(
      projects: [project],
      assets: const [],
      selectedProjectId: project.id,
    );
  }

  String encode() => jsonEncode(toJson());

  static KioState decode(String source) {
    return KioState.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }
}

const Object _sentinel = Object();
