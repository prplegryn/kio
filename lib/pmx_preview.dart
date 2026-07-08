import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'models.dart';

class PmxPreview extends StatefulWidget {
  const PmxPreview({
    super.key,
    required this.asset,
    required this.orbitX,
    required this.orbitY,
    required this.zoom,
  });

  final KioAsset? asset;
  final double orbitX;
  final double orbitY;
  final double zoom;

  @override
  State<PmxPreview> createState() => _PmxPreviewState();
}

class _PmxPreviewState extends State<PmxPreview> {
  PmxMesh? mesh;
  String? loadingAssetId;
  String? message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PmxPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset?.id != widget.asset?.id) {
      _load();
    }
  }

  Future<void> _load() async {
    final asset = widget.asset;
    if (asset == null) {
      setState(() {
        mesh = null;
        loadingAssetId = null;
        message = null;
      });
      return;
    }

    setState(() {
      mesh = null;
      loadingAssetId = asset.id;
      message = 'Loading model...';
    });

    try {
      final file = await _resolveModelFile(asset);
      if (file == null) {
        throw Exception('No PMX file found in model package.');
      }
      if (!file.path.toLowerCase().endsWith('.pmx')) {
        throw Exception('PMD preview is not implemented yet. Please use PMX.');
      }
      final parsed = await PmxParser.parse(file);
      if (!mounted || loadingAssetId != asset.id) return;
      setState(() {
        mesh = parsed;
        message = null;
      });
    } catch (error) {
      if (!mounted || loadingAssetId != asset.id) return;
      setState(() {
        mesh = null;
        message = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<File?> _resolveModelFile(KioAsset asset) async {
    final root = Directory(asset.localPath);
    if (!root.existsSync()) return null;

    final entry = asset.entryFile;
    if (entry != null && entry.trim().isNotEmpty) {
      final direct = File(p.join(root.path, entry));
      if (direct.existsSync()) return direct;
    }

    final files = root
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) {
      final lower = file.path.toLowerCase();
      return lower.endsWith('.pmx') || lower.endsWith('.pmd');
    }).toList();

    if (files.isEmpty) return null;
    files.sort((a, b) => a.path.length.compareTo(b.path.length));
    return files.first;
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
              orbitX: widget.orbitX,
              orbitY: widget.orbitY,
              zoom: widget.zoom,
            ),
          ),
        if (message != null)
          Positioned(
            left: 12,
            right: 90,
            top: MediaQuery.of(context).padding.top + 64,
            child: IgnorePointer(
              child: Text(
                message!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8A91A3),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PmxMesh {
  PmxMesh({
    required this.vertices,
    required this.indices,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.minZ,
    required this.maxZ,
  });

  final List<_Vec3> vertices;
  final List<int> indices;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
  final double minZ;
  final double maxZ;
}

class _Vec3 {
  const _Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

class PmxParser {
  static Future<PmxMesh> parse(File file) async {
    final bytes = await file.readAsBytes();
    final r = _Reader(bytes);

    final magic = String.fromCharCodes(r.readBytes(4));
    if (magic != 'PMX ') {
      throw Exception('Invalid PMX header.');
    }

    r.readFloat32();
    final globalsCount = r.readUint8();
    if (globalsCount < 8) {
      throw Exception('Unsupported PMX globals.');
    }

    final textEncoding = r.readUint8();
    final additionalUv = r.readUint8();
    final vertexIndexSize = r.readUint8();
    r.readUint8();
    r.readUint8();
    final boneIndexSize = r.readUint8();
    r.readUint8();
    r.readUint8();

    for (var i = 0; i < 4; i++) {
      r.skipText(textEncoding);
    }

    final vertexCount = r.readInt32();
    if (vertexCount <= 0 || vertexCount > 1000000) {
      throw Exception('Invalid PMX vertex count.');
    }

    final vertices = <_Vec3>[];
    double minX = double.infinity;
    double minY = double.infinity;
    double minZ = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    double maxZ = -double.infinity;

    for (var i = 0; i < vertexCount; i++) {
      final x = r.readFloat32();
      final y = r.readFloat32();
      final z = r.readFloat32();

      vertices.add(_Vec3(x, y, z));
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      minZ = math.min(minZ, z);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
      maxZ = math.max(maxZ, z);

      r.skipFloat32(3);
      r.skipFloat32(2);
      r.skipFloat32(additionalUv * 4);

      final weightType = r.readUint8();
      switch (weightType) {
        case 0:
          r.skipIndex(boneIndexSize);
          break;
        case 1:
          r.skipIndex(boneIndexSize);
          r.skipIndex(boneIndexSize);
          r.skipFloat32(1);
          break;
        case 2:
        case 4:
          for (var j = 0; j < 4; j++) {
            r.skipIndex(boneIndexSize);
          }
          r.skipFloat32(4);
          break;
        case 3:
          r.skipIndex(boneIndexSize);
          r.skipIndex(boneIndexSize);
          r.skipFloat32(1);
          r.skipFloat32(9);
          break;
        default:
          throw Exception('Unsupported PMX weight type $weightType.');
      }

      r.skipFloat32(1);
    }

    final indexCount = r.readInt32();
    if (indexCount <= 0 || indexCount > 5000000) {
      throw Exception('Invalid PMX index count.');
    }

    final indices = <int>[];
    for (var i = 0; i < indexCount; i++) {
      final index = r.readVertexIndex(vertexIndexSize);
      if (index >= 0 && index < vertices.length) {
        indices.add(index);
      }
    }

    return PmxMesh(
      vertices: vertices,
      indices: indices,
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      minZ: minZ,
      maxZ: maxZ,
    );
  }

}

class _Reader {
  _Reader(Uint8List bytes) : data = ByteData.sublistView(bytes);

  final ByteData data;
  int offset = 0;

  int readUint8() {
    final v = data.getUint8(offset);
    offset += 1;
    return v;
  }

  int readInt32() {
    final v = data.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  double readFloat32() {
    final v = data.getFloat32(offset, Endian.little);
    offset += 4;
    return v;
  }

  Uint8List readBytes(int length) {
    final out = data.buffer.asUint8List(data.offsetInBytes + offset, length);
    offset += length;
    return out;
  }

  void skip(int length) {
    offset += length;
  }

  void skipFloat32(int count) {
    offset += count * 4;
  }

  void skipIndex(int size) {
    offset += size;
  }

  void skipText(int encoding) {
    final length = readInt32();
    if (length < 0 || offset + length > data.lengthInBytes) {
      throw Exception('Invalid PMX text block.');
    }
    skip(length);
  }

  int readVertexIndex(int size) {
    switch (size) {
      case 1:
        final v = data.getUint8(offset);
        offset += 1;
        return v;
      case 2:
        final v = data.getUint16(offset, Endian.little);
        offset += 2;
        return v;
      case 4:
        final v = data.getInt32(offset, Endian.little);
        offset += 4;
        return v;
      default:
        throw Exception('Unsupported vertex index size $size.');
    }
  }
}

class PmxMeshPainter extends CustomPainter {
  PmxMeshPainter({
    required this.mesh,
    required this.orbitX,
    required this.orbitY,
    required this.zoom,
  });

  final PmxMesh mesh;
  final double orbitX;
  final double orbitY;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.vertices.isEmpty || mesh.indices.length < 3) return;

    final centerX = (mesh.minX + mesh.maxX) * .5;
    final centerY = (mesh.minY + mesh.maxY) * .5;
    final centerZ = (mesh.minZ + mesh.maxZ) * .5;

    final width = math.max(.001, mesh.maxX - mesh.minX);
    final height = math.max(.001, mesh.maxY - mesh.minY);
    final depth = math.max(.001, mesh.maxZ - mesh.minZ);
    final maxDim = math.max(width, math.max(height, depth));
    final scale = math.min(size.width, size.height) * .62 / maxDim * zoom;

    final yaw = orbitX * math.pi / 180.0;
    final pitch = orbitY * math.pi / 180.0;
    final cy = math.cos(yaw);
    final sy = math.sin(yaw);
    final cx = math.cos(pitch);
    final sx = math.sin(pitch);

    final projected = List<Offset>.filled(mesh.vertices.length, Offset.zero);
    for (var i = 0; i < mesh.vertices.length; i++) {
      final v = mesh.vertices[i];
      final x = v.x - centerX;
      final y = v.y - centerY;
      final z = v.z - centerZ;

      final rx = x * cy + z * sy;
      final rz = -x * sy + z * cy;
      final ry = y * cx - rz * sx;

      projected[i] = Offset(
        size.width * .5 + rx * scale,
        size.height * .53 - ry * scale,
      );
    }

    final line = Paint()
      ..color = const Color(0xFFE5E8FF)
      ..strokeWidth = .7
      ..style = PaintingStyle.stroke;

    final soft = Paint()
      ..color = const Color(0x556D83FF)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final triangleCount = mesh.indices.length ~/ 3;
    final step = math.max(1, triangleCount ~/ 8500);

    for (var tri = 0; tri < triangleCount; tri += step) {
      final i = tri * 3;
      final a = mesh.indices[i];
      final b = mesh.indices[i + 1];
      final c = mesh.indices[i + 2];
      if (a >= projected.length || b >= projected.length || c >= projected.length) continue;

      final pa = projected[a];
      final pb = projected[b];
      final pc = projected[c];

      canvas.drawLine(pa, pb, line);
      canvas.drawLine(pb, pc, line);
      canvas.drawLine(pc, pa, line);
    }

    final rect = Rect.fromCenter(
      center: Offset(size.width * .5, size.height * .53),
      width: math.max(20, width * scale),
      height: math.max(20, height * scale),
    );
    canvas.drawOval(rect.inflate(8), soft);
  }

  @override
  bool shouldRepaint(covariant PmxMeshPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.orbitX != orbitX ||
        oldDelegate.orbitY != orbitY ||
        oldDelegate.zoom != zoom;
  }
}
