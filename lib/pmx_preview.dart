import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
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
        status = 'No model selected';
        statusIsError = false;
      });
      return;
    }

    setState(() {
      mesh = null;
      loadingAssetId = asset.id;
      status = 'Loading ${asset.displayName}...';
      statusIsError = false;
    });

    try {
      final payload = await _resolvePmxPayload(asset);
      if (payload == null) {
        throw Exception('No PMX file found. Re-import model as a ZIP that contains .pmx.');
      }

      final parsed = PmxParser.parseBytes(payload.bytes);
      if (!mounted || loadingAssetId != asset.id) return;

      setState(() {
        mesh = parsed;
        status = 'PMX loaded: ${parsed.vertices.length} vertices / ${parsed.indices.length ~/ 3} triangles';
        statusIsError = false;
      });
    } catch (error) {
      if (!mounted || loadingAssetId != asset.id) return;
      setState(() {
        mesh = null;
        status = error.toString().replaceFirst('Exception: ', '');
        statusIsError = true;
      });
    }
  }

  Future<_PmxPayload?> _resolvePmxPayload(KioAsset asset) async {
    final asDir = Directory(asset.localPath);
    final asFile = File(asset.localPath);

    if (asDir.existsSync()) {
      final entry = asset.entryFile;
      if (entry != null && entry.trim().isNotEmpty) {
        final direct = File(p.join(asDir.path, entry));
        if (direct.existsSync() && direct.path.toLowerCase().endsWith('.pmx')) {
          return _PmxPayload(direct.path, await direct.readAsBytes());
        }
      }

      final files = asDir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.pmx'))
          .toList();

      if (files.isEmpty) return null;
      files.sort((a, b) => a.path.length.compareTo(b.path.length));
      return _PmxPayload(files.first.path, await files.first.readAsBytes());
    }

    if (asFile.existsSync()) {
      final lower = asFile.path.toLowerCase();
      if (lower.endsWith('.pmx')) {
        return _PmxPayload(asFile.path, await asFile.readAsBytes());
      }

      if (lower.endsWith('.zip')) {
        return _readPmxFromZip(await asFile.readAsBytes(), asFile.path);
      }
    }

    return null;
  }

  _PmxPayload? _readPmxFromZip(Uint8List bytes, String sourceName) {
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw Exception('Invalid model ZIP.');
    }

    final pmxEntries = archive.files
        .where((entry) => entry.isFile && entry.name.toLowerCase().endsWith('.pmx'))
        .toList();

    if (pmxEntries.isEmpty) return null;
    pmxEntries.sort((a, b) => a.name.length.compareTo(b.name.length));

    final content = pmxEntries.first.content;
    if (content is! List<int>) {
      throw Exception('Cannot read PMX data from ZIP.');
    }

    return _PmxPayload('$sourceName/${pmxEntries.first.name}', Uint8List.fromList(content));
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
        if (status != null)
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
      throw Exception('Invalid PMX vertex count: $vertexCount');
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
          throw Exception('Unsupported PMX weight type $weightType at vertex $i.');
      }

      r.skipFloat32(1);
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
    _check(1);
    final v = data.getUint8(offset);
    offset += 1;
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

  void skip(int length) {
    _check(length);
    offset += length;
  }

  void skipFloat32(int count) => skip(count * 4);
  void skipIndex(int size) => skip(size);

  void skipText(int encoding) {
    final length = readInt32();
    if (length < 0) throw Exception('Invalid PMX text length.');
    skip(length);
  }

  int readVertexIndex(int size) {
    switch (size) {
      case 1:
        _check(1);
        final v = data.getUint8(offset);
        offset += 1;
        return v;
      case 2:
        _check(2);
        final v = data.getUint16(offset, Endian.little);
        offset += 2;
        return v;
      case 4:
        _check(4);
        final v = data.getInt32(offset, Endian.little);
        offset += 4;
        return v;
      default:
        throw Exception('Unsupported vertex index size $size.');
    }
  }

  void _check(int length) {
    if (offset + length > data.lengthInBytes) {
      throw Exception('Unexpected end of PMX data at $offset.');
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
    final scale = math.min(size.width, size.height) * .70 / maxDim * zoom;

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

  @override
  bool shouldRepaint(covariant PmxMeshPainter oldDelegate) {
    return oldDelegate.mesh != mesh ||
        oldDelegate.orbitX != orbitX ||
        oldDelegate.orbitY != orbitY ||
        oldDelegate.zoom != zoom;
  }
}
