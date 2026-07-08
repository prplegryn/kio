import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'vmd_parser.dart';

class PmxPreview extends StatefulWidget {
  const PmxPreview({
    super.key,
    required this.asset,
    required this.motionAsset,
    required this.cameraAsset,
    required this.orbitX,
    required this.orbitY,
    required this.zoom,
    required this.playheadMs,
    this.showStatus = true,
  });

  final KioAsset? asset;
  final KioAsset? motionAsset;
  final KioAsset? cameraAsset;
  final double orbitX;
  final double orbitY;
  final double zoom;
  final int playheadMs;
  final bool showStatus;

  @override
  State<PmxPreview> createState() => _PmxPreviewState();
}

class _PmxPreviewState extends State<PmxPreview> {
  PmxMesh? mesh;
  VmdData? motion;
  VmdData? camera;
  String? loadingKey;
  String? status;
  bool statusIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PmxPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset?.id != widget.asset?.id ||
        oldWidget.motionAsset?.id != widget.motionAsset?.id ||
        oldWidget.cameraAsset?.id != widget.cameraAsset?.id) {
      _load();
    }
  }

  Future<void> _load() async {
    final asset = widget.asset;
    final key = '${asset?.id ?? '-'}:${widget.motionAsset?.id ?? '-'}:${widget.cameraAsset?.id ?? '-'}';
    if (asset == null) {
      setState(() {
        mesh = null;
        motion = null;
        camera = null;
        loadingKey = null;
        status = 'No model selected';
        statusIsError = false;
      });
      return;
    }

    setState(() {
      mesh = null;
      motion = null;
      camera = null;
      loadingKey = key;
      status = 'Loading ${asset.displayName}...';
      statusIsError = false;
    });

    try {
      final payload = await _resolveModelPayload(asset);
      if (payload == null) {
        throw Exception('No PMX or PMD file found. Re-import model as a ZIP that contains a supported model.');
      }

      final parsedMesh = MmdMeshParser.parseBytes(payload.bytes);
      final parsedMotion = await _loadVmd(widget.motionAsset);
      final parsedCamera = await _loadVmd(widget.cameraAsset);
      if (!mounted || loadingKey != key) return;

      setState(() {
        mesh = parsedMesh;
        motion = parsedMotion;
        camera = parsedCamera;
        status = _statusFor(parsedMesh, parsedMotion, parsedCamera);
        statusIsError = false;
      });
    } catch (error) {
      if (!mounted || loadingKey != key) return;
      setState(() {
        mesh = null;
        motion = null;
        camera = null;
        status = error.toString().replaceFirst('Exception: ', '');
        statusIsError = true;
      });
    }
  }

  Future<VmdData?> _loadVmd(KioAsset? asset) async {
    if (asset == null) return null;
    return VmdParser.parseAssetFile(asset.localPath);
  }

  String _statusFor(PmxMesh mesh, VmdData? motion, VmdData? camera) {
    final parts = [
      '${mesh.format}: ${mesh.vertices.length} vertices / ${mesh.indices.length ~/ 3} triangles',
    ];
    if (motion != null && motion.hasBoneMotion) {
      parts.add('motion ${motion.maxFrame}f');
    } else if (widget.motionAsset != null) {
      parts.add('${p.extension(widget.motionAsset!.originalName).toUpperCase().replaceFirst('.', '')} motion not playable');
    }
    if (camera != null && camera.hasCameraMotion) {
      parts.add('camera ${camera.maxFrame}f');
    } else if (widget.cameraAsset != null) {
      parts.add('${p.extension(widget.cameraAsset!.originalName).toUpperCase().replaceFirst('.', '')} camera not playable');
    }
    return parts.join(' · ');
  }

  Future<_PmxPayload?> _resolveModelPayload(KioAsset asset) async {
    final asDir = Directory(asset.localPath);
    final asFile = File(asset.localPath);

    if (asDir.existsSync()) {
      final entry = asset.entryFile;
      if (entry != null && entry.trim().isNotEmpty) {
        final direct = File(p.join(asDir.path, entry));
        if (direct.existsSync() && _isSupportedModelPath(direct.path)) {
          return _PmxPayload(direct.path, await direct.readAsBytes());
        }
      }

      final files = asDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => _isSupportedModelPath(file.path))
          .toList();

      if (files.isEmpty) return null;
      files.sort(_compareModelFiles);
      return _PmxPayload(files.first.path, await files.first.readAsBytes());
    }

    if (asFile.existsSync()) {
      final lower = asFile.path.toLowerCase();
      if (_isSupportedModelPath(lower)) {
        return _PmxPayload(asFile.path, await asFile.readAsBytes());
      }

      if (lower.endsWith('.zip')) {
        return _readModelFromZip(await asFile.readAsBytes(), asFile.path);
      }
    }

    return null;
  }

  _PmxPayload? _readModelFromZip(Uint8List bytes, String sourceName) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw Exception('Invalid model ZIP.');
    }

    final modelEntries = archive.files
        .where((entry) => entry.isFile && _isSupportedModelPath(entry.name))
        .toList();

    if (modelEntries.isEmpty) return null;
    modelEntries.sort(_compareModelEntries);

    final content = modelEntries.first.content;
    if (content is! List<int>) {
      throw Exception('Cannot read model data from ZIP.');
    }

    return _PmxPayload('$sourceName/${modelEntries.first.name}', Uint8List.fromList(content));
  }

  bool _isSupportedModelPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.pmx') || lower.endsWith('.pmd');
  }

  int _compareModelFiles(File a, File b) {
    final priority = _modelPriority(a.path).compareTo(_modelPriority(b.path));
    if (priority != 0) return priority;
    return a.path.length.compareTo(b.path.length);
  }

  int _compareModelEntries(ArchiveFile a, ArchiveFile b) {
    final priority = _modelPriority(a.name).compareTo(_modelPriority(b.name));
    if (priority != 0) return priority;
    return a.name.length.compareTo(b.name.length);
  }

  int _modelPriority(String path) {
    return path.toLowerCase().endsWith('.pmx') ? 0 : 1;
  }

  @override
  Widget build(BuildContext context) {
    final current = mesh;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (current != null)
          CustomPaint(
            painter: PmxMeshPainter(
              mesh: current,
              motion: motion,
              camera: camera,
              playheadMs: widget.playheadMs,
              orbitX: widget.orbitX,
              orbitY: widget.orbitY,
              zoom: widget.zoom,
            ),
          ),
        if (widget.showStatus && status != null)
          Positioned(
            left: 12,
            right: 88,
            top: MediaQuery.of(context).padding.top + 62,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF11141D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: statusIsError ? const Color(0xFFFF6680) : const Color(0xFF2A3040),
                  ),
                ),
                child: Text(
                  status!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: statusIsError ? const Color(0xFFFFA0AF) : const Color(0xFF8A91A3),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PmxPayload {
  _PmxPayload(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class PmxMesh {
  PmxMesh({
    required this.format,
    required this.vertices,
    required this.indices,
    required this.bones,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.minZ,
    required this.maxZ,
  });

  final String format;
  final List<MmdVertex> vertices;
  final List<int> indices;
  final List<MmdBone> bones;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double minZ;
  final double maxZ;
}

class MmdVertex {
  MmdVertex({required this.bindPosition, required this.weights});

  final MmdVec3 bindPosition;
  final List<MmdBoneWeight> weights;
}

class MmdBoneWeight {
  const MmdBoneWeight(this.boneIndex, this.weight);

  final int boneIndex;
  final double weight;
}

class MmdBone {
  MmdBone({
    required this.canonicalName,
    required this.parentIndex,
    required this.position,
    required this.inverseBind,
  });

  final String canonicalName;
  final int parentIndex;
  final MmdVec3 position;
  final MmdMat4 inverseBind;
}

class _RawBone {
  _RawBone({required this.name, required this.parentIndex, required this.position});

  final String name;
  final int parentIndex;
  final MmdVec3 position;
}

class MmdMeshParser {
  static PmxMesh parseBytes(Uint8List bytes) {
    if (_hasMagic(bytes, 'PMX ')) {
      return PmxParser.parseBytes(bytes);
    }
    if (_hasMagic(bytes, 'Pmd')) {
      return PmdParser.parseBytes(bytes);
    }
    throw Exception('Unsupported model format. Expected PMX or PMD.');
  }

  static bool _hasMagic(Uint8List bytes, String magic) {
    if (bytes.length < magic.length) return false;
    return String.fromCharCodes(bytes.sublist(0, magic.length)) == magic;
  }
}

class PmxParser {
  static PmxMesh parseBytes(Uint8List bytes) {
    final r = _Reader(bytes);

    final magic = String.fromCharCodes(r.readBytes(4));
    if (magic != 'PMX ') {
      throw Exception('Invalid PMX header: $magic');
    }

    r.readFloat32();
    final globalsCount = r.readUint8();
    if (globalsCount < 8) {
      throw Exception('Unsupported PMX globals.');
    }

    final textEncoding = r.readUint8();
    final additionalUv = r.readUint8();
    final vertexIndexSize = r.readUint8();
    final textureIndexSize = r.readUint8();
    r.readUint8();
    final boneIndexSize = r.readUint8();
    r.readUint8();
    r.readUint8();

    for (var i = 8; i < globalsCount; i++) {
      r.readUint8();
    }

    for (var i = 0; i < 4; i++) {
      r.readText(textEncoding);
    }

    final vertexCount = r.readInt32();
    if (vertexCount <= 0 || vertexCount > 1000000) {
      throw Exception('Invalid PMX vertex count: $vertexCount');
    }

    final vertices = <MmdVertex>[];
    double minX = double.infinity;
    double minY = double.infinity;
    double minZ = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    double maxZ = -double.infinity;

    for (var i = 0; i < vertexCount; i++) {
      final position = MmdVec3(r.readFloat32(), r.readFloat32(), r.readFloat32());
      minX = math.min(minX, position.x);
      minY = math.min(minY, position.y);
      minZ = math.min(minZ, position.z);
      maxX = math.max(maxX, position.x);
      maxY = math.max(maxY, position.y);
      maxZ = math.max(maxZ, position.z);

      r.skipFloat32(3);
      r.skipFloat32(2);
      r.skipFloat32(additionalUv * 4);

      final weights = _readPmxWeights(r, boneIndexSize);
      r.skipFloat32(1);
      vertices.add(MmdVertex(bindPosition: position, weights: weights));
    }

    final indexCount = r.readInt32();
    if (indexCount <= 0 || indexCount > 5000000) {
      throw Exception('Invalid PMX index count: $indexCount');
    }

    final indices = <int>[];
    for (var i = 0; i < indexCount; i++) {
      final index = r.readVertexIndex(vertexIndexSize);
      if (index >= 0 && index < vertices.length) {
        indices.add(index);
      }
    }

    if (indices.length < 3) {
      throw Exception('PMX has no drawable indices.');
    }

    final textureCount = r.readInt32();
    for (var i = 0; i < textureCount; i++) {
      r.readText(textEncoding);
    }

    final materialCount = r.readInt32();
    for (var i = 0; i < materialCount; i++) {
      _skipPmxMaterial(r, textEncoding, textureIndexSize);
    }

    final boneCount = r.readInt32();
    final rawBones = <_RawBone>[];
    for (var i = 0; i < boneCount; i++) {
      rawBones.add(_readPmxBone(r, textEncoding, boneIndexSize));
    }

    return PmxMesh(
      format: 'PMX',
      vertices: vertices,
      indices: indices,
      bones: _buildBones(rawBones),
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      minZ: minZ,
      maxZ: maxZ,
    );
  }

  static List<MmdBoneWeight> _readPmxWeights(_Reader r, int boneIndexSize) {
    final weightType = r.readUint8();
    switch (weightType) {
      case 0:
        return _cleanWeights([MmdBoneWeight(r.readIndex(boneIndexSize, signed: true), 1)]);
      case 1:
        final b1 = r.readIndex(boneIndexSize, signed: true);
        final b2 = r.readIndex(boneIndexSize, signed: true);
        final w = r.readFloat32();
        return _cleanWeights([MmdBoneWeight(b1, w), MmdBoneWeight(b2, 1 - w)]);
      case 2:
      case 4:
        final bones = [
          r.readIndex(boneIndexSize, signed: true),
          r.readIndex(boneIndexSize, signed: true),
          r.readIndex(boneIndexSize, signed: true),
          r.readIndex(boneIndexSize, signed: true),
        ];
        final weights = [r.readFloat32(), r.readFloat32(), r.readFloat32(), r.readFloat32()];
        return _cleanWeights([
          for (var i = 0; i < bones.length; i++) MmdBoneWeight(bones[i], weights[i]),
        ]);
      case 3:
        final b1 = r.readIndex(boneIndexSize, signed: true);
        final b2 = r.readIndex(boneIndexSize, signed: true);
        final w = r.readFloat32();
        r.skipFloat32(9);
        return _cleanWeights([MmdBoneWeight(b1, w), MmdBoneWeight(b2, 1 - w)]);
      default:
        throw Exception('Unsupported PMX weight type $weightType.');
    }
  }

  static void _skipPmxMaterial(_Reader r, int textEncoding, int textureIndexSize) {
    r.readText(textEncoding);
    r.readText(textEncoding);
    r.skipFloat32(4);
    r.skipFloat32(3);
    r.skipFloat32(1);
    r.skipFloat32(3);
    r.readUint8();
    r.skipFloat32(4);
    r.skipFloat32(1);
    r.skipIndex(textureIndexSize);
    r.skipIndex(textureIndexSize);
    r.readUint8();
    final toonFlag = r.readUint8();
    if (toonFlag == 0) {
      r.skipIndex(textureIndexSize);
    } else {
      r.skip(1);
    }
    r.readText(textEncoding);
    r.readInt32();
  }

  static _RawBone _readPmxBone(_Reader r, int textEncoding, int boneIndexSize) {
    final localName = r.readText(textEncoding);
    final englishName = r.readText(textEncoding);
    final position = MmdVec3(r.readFloat32(), r.readFloat32(), r.readFloat32());
    final parentIndex = r.readIndex(boneIndexSize, signed: true);
    r.readInt32();
    final flags = r.readUint16();

    if ((flags & 0x0001) != 0) {
      r.skipIndex(boneIndexSize);
    } else {
      r.skipFloat32(3);
    }
    if ((flags & 0x0300) != 0) {
      r.skipIndex(boneIndexSize);
      r.skipFloat32(1);
    }
    if ((flags & 0x0400) != 0) {
      r.skipFloat32(3);
    }
    if ((flags & 0x0800) != 0) {
      r.skipFloat32(6);
    }
    if ((flags & 0x2000) != 0) {
      r.skip(4);
    }
    if ((flags & 0x0020) != 0) {
      r.skipIndex(boneIndexSize);
      r.readInt32();
      r.skipFloat32(1);
      final linkCount = r.readInt32();
      for (var i = 0; i < linkCount; i++) {
        r.skipIndex(boneIndexSize);
        final hasLimit = r.readUint8();
        if (hasLimit != 0) {
          r.skipFloat32(6);
        }
      }
    }

    var canonical = canonicalBoneNameFromText(localName);
    if (canonical.isEmpty) canonical = canonicalBoneNameFromText(englishName);
    return _RawBone(name: canonical, parentIndex: parentIndex, position: position);
  }
}

class PmdParser {
  static PmxMesh parseBytes(Uint8List bytes) {
    final r = _Reader(bytes);

    final magic = String.fromCharCodes(r.readBytes(3));
    if (magic != 'Pmd') {
      throw Exception('Invalid PMD header: $magic');
    }

    r.readFloat32();
    r.skip(20);
    r.skip(256);

    final vertexCount = r.readInt32();
    if (vertexCount <= 0 || vertexCount > 1000000) {
      throw Exception('Invalid PMD vertex count: $vertexCount');
    }

    final vertices = <MmdVertex>[];
    double minX = double.infinity;
    double minY = double.infinity;
    double minZ = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    double maxZ = -double.infinity;

    for (var i = 0; i < vertexCount; i++) {
      final position = MmdVec3(r.readFloat32(), r.readFloat32(), r.readFloat32());
      minX = math.min(minX, position.x);
      minY = math.min(minY, position.y);
      minZ = math.min(minZ, position.z);
      maxX = math.max(maxX, position.x);
      maxY = math.max(maxY, position.y);
      maxZ = math.max(maxZ, position.z);

      r.skipFloat32(3);
      r.skipFloat32(2);
      final b1 = r.readUint16();
      final b2 = r.readUint16();
      final weight = r.readUint8() / 100.0;
      r.skip(1);
      vertices.add(
        MmdVertex(
          bindPosition: position,
          weights: _cleanWeights([MmdBoneWeight(b1, weight), MmdBoneWeight(b2, 1 - weight)]),
        ),
      );
    }

    final indexCount = r.readInt32();
    if (indexCount <= 0 || indexCount > 5000000) {
      throw Exception('Invalid PMD index count: $indexCount');
    }

    final indices = <int>[];
    for (var i = 0; i < indexCount; i++) {
      final index = r.readUint16();
      if (index < vertices.length) {
        indices.add(index);
      }
    }

    if (indices.length < 3) {
      throw Exception('PMD has no drawable indices.');
    }

    final materialCount = r.readInt32();
    r.skip(materialCount * 70);

    final boneCount = r.readUint16();
    final rawBones = <_RawBone>[];
    for (var i = 0; i < boneCount; i++) {
      final name = decodePmdName(r.readBytes(20));
      final parent = r.readUint16();
      r.skip(2);
      r.skip(1);
      r.skip(2);
      final position = MmdVec3(r.readFloat32(), r.readFloat32(), r.readFloat32());
      rawBones.add(
        _RawBone(
          name: name,
          parentIndex: parent == 0xffff ? -1 : parent,
          position: position,
        ),
      );
    }

    return PmxMesh(
      format: 'PMD',
      vertices: vertices,
      indices: indices,
      bones: _buildBones(rawBones),
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      minZ: minZ,
      maxZ: maxZ,
    );
  }
}

List<MmdBoneWeight> _cleanWeights(List<MmdBoneWeight> weights) {
  final cleaned = weights.where((w) => w.boneIndex >= 0 && w.weight > 0.0001).toList();
  final total = cleaned.fold<double>(0, (sum, w) => sum + w.weight);
  if (total <= 0.0001) return const [];
  return [for (final w in cleaned) MmdBoneWeight(w.boneIndex, w.weight / total)];
}

List<MmdBone> _buildBones(List<_RawBone> rawBones) {
  final globals = List<MmdMat4>.filled(rawBones.length, MmdMat4.identity);
  final bones = <MmdBone>[];
  for (var i = 0; i < rawBones.length; i++) {
    final raw = rawBones[i];
    final parent = raw.parentIndex >= 0 && raw.parentIndex < i ? raw.parentIndex : -1;
    final localOffset = parent >= 0 ? raw.position - rawBones[parent].position : raw.position;
    final local = MmdMat4.translationRotation(localOffset, MmdQuat.identity);
    globals[i] = parent >= 0 ? globals[parent] * local : local;
    bones.add(
      MmdBone(
        canonicalName: raw.name.isEmpty ? 'bone$i' : raw.name,
        parentIndex: parent,
        position: raw.position,
        inverseBind: globals[i].inverseRigid(),
      ),
    );
  }
  return bones;
}

class _Reader {
  _Reader(Uint8List bytes) : data = ByteData.sublistView(bytes);

  final ByteData data;
  int offset = 0;

  int readUint8() {
    _check(1);
    final v = data.getUint8(offset);
    offset += 1;
    return v;
  }

  int readInt8() {
    _check(1);
    final v = data.getInt8(offset);
    offset += 1;
    return v;
  }

  int readUint16() {
    _check(2);
    final v = data.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int readInt16() {
    _check(2);
    final v = data.getInt16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int readInt32() {
    _check(4);
    final v = data.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  double readFloat32() {
    _check(4);
    final v = data.getFloat32(offset, Endian.little);
    offset += 4;
    return v;
  }

  Uint8List readBytes(int length) {
    _check(length);
    final out = data.buffer.asUint8List(data.offsetInBytes + offset, length);
    offset += length;
    return out;
  }

  String readText(int encoding) {
    final length = readInt32();
    if (length < 0) throw Exception('Invalid PMX text length.');
    final bytes = readBytes(length);
    if (encoding == 0) return _decodeUtf16Le(bytes);
    return utf8.decode(bytes, allowMalformed: true);
  }

  int readIndex(int size, {required bool signed}) {
    switch (size) {
      case 1:
        return signed ? readInt8() : readUint8();
      case 2:
        return signed ? readInt16() : readUint16();
      case 4:
        return readInt32();
      default:
        throw Exception('Unsupported PMX index size $size.');
    }
  }

  int readVertexIndex(int size) {
    switch (size) {
      case 1:
        return readUint8();
      case 2:
        return readUint16();
      case 4:
        return readInt32();
      default:
        throw Exception('Unsupported vertex index size $size.');
    }
  }

  void skip(int length) {
    _check(length);
    offset += length;
  }

  void skipFloat32(int count) => skip(count * 4);
  void skipIndex(int size) => skip(size);

  void _check(int length) {
    if (offset + length > data.lengthInBytes) {
      throw Exception('Unexpected end of model data at $offset.');
    }
  }
}

String _decodeUtf16Le(Uint8List bytes) {
  final codes = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    codes.add(bytes[i] | (bytes[i + 1] << 8));
  }
  return String.fromCharCodes(codes);
}

class PmxMeshPainter extends CustomPainter {
  PmxMeshPainter({
    required this.mesh,
    required this.motion,
    required this.camera,
    required this.playheadMs,
    required this.orbitX,
    required this.orbitY,
    required this.zoom,
  });

  final PmxMesh mesh;
  final VmdData? motion;
  final VmdData? camera;
  final int playheadMs;
  final double orbitX;
  final double orbitY;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.vertices.isEmpty || mesh.indices.length < 3) return;

    final frame = playheadMs * 30.0 / 1000.0;
    final cameraFrame = camera?.sampleCamera(frame);
    final animated = _animatedVertices(frame);

    final centerX = (mesh.minX + mesh.maxX) * .5;
    final centerY = (mesh.minY + mesh.maxY) * .5;
    final centerZ = (mesh.minZ + mesh.maxZ) * .5;

    final width = math.max(.001, mesh.maxX - mesh.minX);
    final height = math.max(.001, mesh.maxY - mesh.minY);
    final depth = math.max(.001, mesh.maxZ - mesh.minZ);
    final maxDim = math.max(width, math.max(height, depth));

    var viewOrbitX = orbitX;
    var viewOrbitY = orbitY;
    var viewZoom = zoom;
    if (cameraFrame != null) {
      viewOrbitX += -cameraFrame.rotation.y * 180 / math.pi;
      viewOrbitY += cameraFrame.rotation.x * 180 / math.pi;
      final distanceZoom = (45 / math.max(10, cameraFrame.distance.abs())).clamp(.35, 3.2).toDouble();
      final fovZoom = (45 / math.max(15, cameraFrame.fov)).clamp(.5, 2.4).toDouble();
      viewZoom *= distanceZoom * fovZoom;
    }

    final scale = math.min(size.width, size.height) * .70 / maxDim * viewZoom;
    final yaw = viewOrbitX * math.pi / 180.0;
    final pitch = viewOrbitY * math.pi / 180.0;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final cx = math.cos(pitch);
    final sx = math.sin(pitch);

    final projected = List<Offset>.filled(animated.length, Offset.zero);
    for (var i = 0; i < animated.length; i++) {
      final v = animated[i];
      final x = v.x - centerX;
      final y = v.y - centerY;
      final z = v.z - centerZ;

      final rx = x * cy + z * sy;
      final rz = -x * sy + z * cy;
      final ry = y * cx - rz * sx;

      projected[i] = Offset(
        size.width * .5 + rx * scale,
        size.height * .56 - ry * scale,
      );
    }

    final fill = Paint()
      ..color = const Color(0x336D83FF)
      ..style = PaintingStyle.fill;

    final line = Paint()
      ..color = const Color(0xFFE9ECFF)
      ..strokeWidth = .62
      ..style = PaintingStyle.stroke;

    final triangleCount = mesh.indices.length ~/ 3;
    final step = math.max(1, triangleCount ~/ 9000);

    for (var tri = 0; tri < triangleCount; tri += step) {
      final i = tri * 3;
      final a = mesh.indices[i];
      final b = mesh.indices[i + 1];
      final c = mesh.indices[i + 2];

      if (a >= projected.length || b >= projected.length || c >= projected.length) continue;

      final path = Path()
        ..moveTo(projected[a].dx, projected[a].dy)
        ..lineTo(projected[b].dx, projected[b].dy)
        ..lineTo(projected[c].dx, projected[c].dy)
        ..close();

      canvas.drawPath(path, fill);
      canvas.drawPath(path, line);
    }
  }

  List<MmdVec3> _animatedVertices(double frame) {
    final currentMotion = motion;
    if (currentMotion == null || !currentMotion.hasBoneMotion || mesh.bones.isEmpty) {
      return [for (final vertex in mesh.vertices) vertex.bindPosition];
    }

    final globals = List<MmdMat4>.filled(mesh.bones.length, MmdMat4.identity);
    for (var i = 0; i < mesh.bones.length; i++) {
      final bone = mesh.bones[i];
      final parent = bone.parentIndex;
      final parentPosition = parent >= 0 ? mesh.bones[parent].position : MmdVec3.zero;
      final baseOffset = parent >= 0 ? bone.position - parentPosition : bone.position;
      final pose = currentMotion.sampleBone(bone.canonicalName, frame);
      final local = MmdMat4.translationRotation(
        baseOffset + (pose?.translation ?? MmdVec3.zero),
        pose?.rotation ?? MmdQuat.identity,
      );
      globals[i] = parent >= 0 ? globals[parent] * local : local;
    }

    return [
      for (final vertex in mesh.vertices)
        _skinVertex(vertex, globals),
    ];
  }

  MmdVec3 _skinVertex(MmdVertex vertex, List<MmdMat4> globals) {
    if (vertex.weights.isEmpty) return vertex.bindPosition;
    var out = MmdVec3.zero;
    var total = 0.0;
    for (final weight in vertex.weights) {
      if (weight.boneIndex < 0 || weight.boneIndex >= mesh.bones.length) continue;
      final skin = globals[weight.boneIndex] * mesh.bones[weight.boneIndex].inverseBind;
      out = out + skin.transform(vertex.bindPosition) * weight.weight;
      total += weight.weight;
    }
    if (total <= 0.0001) return vertex.bindPosition;
    return out * (1 / total);
  }

  @override
  bool shouldRepaint(covariant PmxMeshPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.motion != motion ||
        oldDelegate.camera != camera ||
        oldDelegate.playheadMs != playheadMs ||
        oldDelegate.orbitX != orbitX ||
        oldDelegate.orbitY != orbitY ||
        oldDelegate.zoom != zoom;
  }
}
