import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class MmdVec3 {
  const MmdVec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  static const zero = MmdVec3(0, 0, 0);

  MmdVec3 operator +(MmdVec3 other) => MmdVec3(x + other.x, y + other.y, z + other.z);
  MmdVec3 operator -(MmdVec3 other) => MmdVec3(x - other.x, y - other.y, z - other.z);
  MmdVec3 operator *(double value) => MmdVec3(x * value, y * value, z * value);

  static MmdVec3 lerp(MmdVec3 a, MmdVec3 b, double t) {
    return MmdVec3(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
  }
}

class MmdQuat {
  const MmdQuat(this.x, this.y, this.z, this.w);

  final double x;
  final double y;
  final double z;
  final double w;

  static const identity = MmdQuat(0, 0, 0, 1);

  MmdQuat normalized() {
    final length = math.sqrt(x * x + y * y + z * z + w * w);
    if (length <= 0.000001) return identity;
    return MmdQuat(x / length, y / length, z / length, w / length);
  }

  static MmdQuat lerp(MmdQuat a, MmdQuat b, double t) {
    var bx = b.x;
    var by = b.y;
    var bz = b.z;
    var bw = b.w;
    final dot = a.x * bx + a.y * by + a.z * bz + a.w * bw;
    if (dot < 0) {
      bx = -bx;
      by = -by;
      bz = -bz;
      bw = -bw;
    }
    return MmdQuat(
      a.x + (bx - a.x) * t,
      a.y + (by - a.y) * t,
      a.z + (bz - a.z) * t,
      a.w + (bw - a.w) * t,
    ).normalized();
  }
}

class MmdMat4 {
  const MmdMat4(this.m);

  final List<double> m;

  static const identity = MmdMat4([
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1,
  ]);

  factory MmdMat4.translationRotation(MmdVec3 t, MmdQuat q) {
    final n = q.normalized();
    final xx = n.x * n.x;
    final yy = n.y * n.y;
    final zz = n.z * n.z;
    final xy = n.x * n.y;
    final xz = n.x * n.z;
    final yz = n.y * n.z;
    final wx = n.w * n.x;
    final wy = n.w * n.y;
    final wz = n.w * n.z;

    return MmdMat4([
      1 - 2 * (yy + zz), 2 * (xy - wz), 2 * (xz + wy), t.x,
      2 * (xy + wz), 1 - 2 * (xx + zz), 2 * (yz - wx), t.y,
      2 * (xz - wy), 2 * (yz + wx), 1 - 2 * (xx + yy), t.z,
      0, 0, 0, 1,
    ]);
  }

  MmdMat4 operator *(MmdMat4 other) {
    final out = List<double>.filled(16, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 4; col++) {
        out[row * 4 + col] =
            m[row * 4] * other.m[col] +
            m[row * 4 + 1] * other.m[4 + col] +
            m[row * 4 + 2] * other.m[8 + col] +
            m[row * 4 + 3] * other.m[12 + col];
      }
    }
    return MmdMat4(out);
  }

  MmdVec3 transform(MmdVec3 v) {
    return MmdVec3(
      m[0] * v.x + m[1] * v.y + m[2] * v.z + m[3],
      m[4] * v.x + m[5] * v.y + m[6] * v.z + m[7],
      m[8] * v.x + m[9] * v.y + m[10] * v.z + m[11],
    );
  }

  MmdMat4 inverseRigid() {
    final r00 = m[0];
    final r01 = m[1];
    final r02 = m[2];
    final r10 = m[4];
    final r11 = m[5];
    final r12 = m[6];
    final r20 = m[8];
    final r21 = m[9];
    final r22 = m[10];
    final tx = m[3];
    final ty = m[7];
    final tz = m[11];

    return MmdMat4([
      r00, r10, r20, -(r00 * tx + r10 * ty + r20 * tz),
      r01, r11, r21, -(r01 * tx + r11 * ty + r21 * tz),
      r02, r12, r22, -(r02 * tx + r12 * ty + r22 * tz),
      0, 0, 0, 1,
    ]);
  }
}

class VmdBonePose {
  const VmdBonePose({required this.translation, required this.rotation});

  final MmdVec3 translation;
  final MmdQuat rotation;
}

class VmdBoneFrame {
  VmdBoneFrame({
    required this.boneName,
    required this.frame,
    required this.translation,
    required this.rotation,
  });

  final String boneName;
  final int frame;
  final MmdVec3 translation;
  final MmdQuat rotation;
}

class VmdCameraFrame {
  VmdCameraFrame({
    required this.frame,
    required this.distance,
    required this.position,
    required this.rotation,
    required this.fov,
  });

  final int frame;
  final double distance;
  final MmdVec3 position;
  final MmdVec3 rotation;
  final int fov;
}

class VmdData {
  VmdData({
    required this.boneFrames,
    required this.cameraFrames,
    required this.morphFrameCount,
    required this.maxFrame,
  });

  final Map<String, List<VmdBoneFrame>> boneFrames;
  final List<VmdCameraFrame> cameraFrames;
  final int morphFrameCount;
  final int maxFrame;

  int get durationMs => (maxFrame * 1000 / 30).ceil();
  bool get hasBoneMotion => boneFrames.values.any((frames) => frames.isNotEmpty);
  bool get hasMorphMotion => morphFrameCount > 0;
  bool get hasCameraMotion => cameraFrames.isNotEmpty;

  VmdBonePose? sampleBone(String canonicalName, double frame) {
    final frames = boneFrames[canonicalName];
    if (frames == null || frames.isEmpty) return null;
    if (frame <= frames.first.frame) {
      return VmdBonePose(translation: frames.first.translation, rotation: frames.first.rotation);
    }
    if (frame >= frames.last.frame) {
      return VmdBonePose(translation: frames.last.translation, rotation: frames.last.rotation);
    }

    var low = 0;
    var high = frames.length - 1;
    while (high - low > 1) {
      final mid = (low + high) >> 1;
      if (frames[mid].frame <= frame) {
        low = mid;
      } else {
        high = mid;
      }
    }

    final a = frames[low];
    final b = frames[high];
    final span = (b.frame - a.frame).toDouble();
    final t = span <= 0 ? 0.0 : ((frame - a.frame) / span).clamp(0.0, 1.0).toDouble();
    return VmdBonePose(
      translation: MmdVec3.lerp(a.translation, b.translation, t),
      rotation: MmdQuat.lerp(a.rotation, b.rotation, t),
    );
  }

  VmdCameraFrame? sampleCamera(double frame) {
    if (cameraFrames.isEmpty) return null;
    if (frame <= cameraFrames.first.frame) return cameraFrames.first;
    if (frame >= cameraFrames.last.frame) return cameraFrames.last;

    var low = 0;
    var high = cameraFrames.length - 1;
    while (high - low > 1) {
      final mid = (low + high) >> 1;
      if (cameraFrames[mid].frame <= frame) {
        low = mid;
      } else {
        high = mid;
      }
    }

    final a = cameraFrames[low];
    final b = cameraFrames[high];
    final span = (b.frame - a.frame).toDouble();
    final t = span <= 0 ? 0.0 : ((frame - a.frame) / span).clamp(0.0, 1.0).toDouble();
    return VmdCameraFrame(
      frame: frame.round(),
      distance: a.distance + (b.distance - a.distance) * t,
      position: MmdVec3.lerp(a.position, b.position, t),
      rotation: MmdVec3.lerp(a.rotation, b.rotation, t),
      fov: (a.fov + (b.fov - a.fov) * t).round(),
    );
  }
}

class VmdParser {
  static Future<VmdData?> parseAssetFile(String path) async {
    if (!path.toLowerCase().endsWith('.vmd')) return null;
    return parseBytes(await File(path).readAsBytes());
  }

  static VmdData parseBytes(Uint8List bytes) {
    final r = _VmdReader(bytes);
    final header = _trimAscii(r.readBytes(30));
    if (!header.startsWith('Vocaloid Motion Data')) {
      throw Exception('Unsupported VMD header.');
    }

    r.skip(20);
    final boneCount = r.readUint32();
    final boneFrames = <String, List<VmdBoneFrame>>{};
    var maxFrame = 0;
    for (var i = 0; i < boneCount; i++) {
      final rawName = r.readBytes(15);
      final frame = r.readUint32();
      final translation = MmdVec3(r.readFloat32(), r.readFloat32(), r.readFloat32());
      final rotation = MmdQuat(r.readFloat32(), r.readFloat32(), r.readFloat32(), r.readFloat32()).normalized();
      r.skip(64);

      final boneName = canonicalBoneNameFromBytes(rawName);
      if (boneName != null) {
        boneFrames.putIfAbsent(boneName, () => []).add(
              VmdBoneFrame(
                boneName: boneName,
                frame: frame,
                translation: translation,
                rotation: rotation,
              ),
            );
      }
      maxFrame = math.max(maxFrame, frame);
    }

    final morphCount = r.readUint32();
    for (var i = 0; i < morphCount; i++) {
      r.skip(15);
      final frame = r.readUint32();
      r.skip(4);
      maxFrame = math.max(maxFrame, frame);
    }

    final cameraFrames = <VmdCameraFrame>[];
    final cameraCount = r.readUint32();
    for (var i = 0; i < cameraCount; i++) {
      final frame = r.readUint32();
      final distance = r.readFloat32();
      final position = MmdVec3(r.readFloat32(), r.readFloat32(), r.readFloat32());
      final rotation = MmdVec3(r.readFloat32(), r.readFloat32(), r.readFloat32());
      r.skip(24);
      final fov = r.readUint32();
      r.skip(1);

      cameraFrames.add(
        VmdCameraFrame(
          frame: frame,
          distance: distance,
          position: position,
          rotation: rotation,
          fov: fov,
        ),
      );
      maxFrame = math.max(maxFrame, frame);
    }

    for (final frames in boneFrames.values) {
      frames.sort((a, b) => a.frame.compareTo(b.frame));
    }
    cameraFrames.sort((a, b) => a.frame.compareTo(b.frame));
    return VmdData(
      boneFrames: boneFrames,
      cameraFrames: cameraFrames,
      morphFrameCount: morphCount,
      maxFrame: maxFrame,
    );
  }
}

String canonicalBoneNameFromText(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  final mapped = _unicodeBoneNames[trimmed];
  if (mapped != null) return mapped;
  return trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

String? canonicalBoneNameFromBytes(Uint8List bytes) {
  final useful = bytes.takeWhile((value) => value != 0).toList();
  if (useful.isEmpty) return null;
  final key = useful.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final mapped = _shiftJisBoneNames[key];
  if (mapped != null) return mapped;
  if (useful.every((byte) => byte >= 0x20 && byte <= 0x7e)) {
    return String.fromCharCodes(useful).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
  return null;
}

String decodePmdName(Uint8List bytes) {
  return canonicalBoneNameFromBytes(bytes) ?? _trimAscii(bytes);
}

String _trimAscii(Uint8List bytes) {
  final useful = bytes.takeWhile((value) => value != 0).where((value) => value >= 0x20 && value <= 0x7e).toList();
  return String.fromCharCodes(useful).trim();
}

const _unicodeBoneNames = {
  '\u5168\u3066\u306e\u89aa': 'root',
  '\u30bb\u30f3\u30bf\u30fc': 'center',
  '\u4e0b\u534a\u8eab': 'lowerbody',
  '\u4e0a\u534a\u8eab': 'upperbody',
  '\u4e0a\u534a\u8eab2': 'upperbody2',
  '\u9996': 'neck',
  '\u982d': 'head',
  '\u5de6\u80a9': 'leftshoulder',
  '\u5de6\u8155': 'leftarm',
  '\u5de6\u3072\u3058': 'leftelbow',
  '\u5de6\u624b\u9996': 'leftwrist',
  '\u53f3\u80a9': 'rightshoulder',
  '\u53f3\u8155': 'rightarm',
  '\u53f3\u3072\u3058': 'rightelbow',
  '\u53f3\u624b\u9996': 'rightwrist',
  '\u5de6\u8db3': 'leftleg',
  '\u5de6\u3072\u3056': 'leftknee',
  '\u5de6\u8db3\u9996': 'leftankle',
  '\u53f3\u8db3': 'rightleg',
  '\u53f3\u3072\u3056': 'rightknee',
  '\u53f3\u8db3\u9996': 'rightankle',
  '\u5de6\u3064\u307e\u5148': 'lefttoe',
  '\u53f3\u3064\u307e\u5148': 'righttoe',
  '\u5de6\u8db3\uff29\uff2b': 'leftlegik',
  '\u53f3\u8db3\uff29\uff2b': 'rightlegik',
  '\u5de6\u3064\u307e\u5148\uff29\uff2b': 'lefttoeik',
  '\u53f3\u3064\u307e\u5148\uff29\uff2b': 'righttoeik',
  '\u5de6\u8db3IK': 'leftlegik',
  '\u53f3\u8db3IK': 'rightlegik',
  '\u5de6\u3064\u307e\u5148IK': 'lefttoeik',
  '\u53f3\u3064\u307e\u5148IK': 'righttoeik',
};

const _shiftJisBoneNames = {
  '915382c482cc9065': 'root',
  '835a8393835e815b': 'center',
  '89ba94bc9067': 'lowerbody',
  '8fe394bc9067': 'upperbody',
  '8fe394bc906732': 'upperbody2',
  '8ef1': 'neck',
  '93aa': 'head',
  '8db68ca8': 'leftshoulder',
  '8db69872': 'leftarm',
  '8db682d082b6': 'leftelbow',
  '8db68ee88ef1': 'leftwrist',
  '89458ca8': 'rightshoulder',
  '89459872': 'rightarm',
  '894582d082b6': 'rightelbow',
  '89458ee88ef1': 'rightwrist',
  '8db691ab': 'leftleg',
  '8db682d082b4': 'leftknee',
  '8db691ab8ef1': 'leftankle',
  '894591ab': 'rightleg',
  '894582d082b4': 'rightknee',
  '894591ab8ef1': 'rightankle',
  '8db682c282dc90e6': 'lefttoe',
  '894582c282dc90e6': 'righttoe',
  '8db691ab8268826a': 'leftlegik',
  '894591ab8268826a': 'rightlegik',
  '8db682c282dc90e68268826a': 'lefttoeik',
  '894582c282dc90e68268826a': 'righttoeik',
  '8db691ab494b': 'leftlegik',
  '894591ab494b': 'rightlegik',
  '8db682c282dc90e6494b': 'lefttoeik',
  '894582c282dc90e6494b': 'righttoeik',
};

class _VmdReader {
  _VmdReader(Uint8List bytes) : data = ByteData.sublistView(bytes);

  final ByteData data;
  int offset = 0;

  Uint8List readBytes(int length) {
    _check(length);
    final out = data.buffer.asUint8List(data.offsetInBytes + offset, length);
    offset += length;
    return out;
  }

  int readUint32() {
    _check(4);
    final v = data.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  double readFloat32() {
    _check(4);
    final v = data.getFloat32(offset, Endian.little);
    offset += 4;
    return v;
  }

  void skip(int length) {
    _check(length);
    offset += length;
  }

  void _check(int length) {
    if (offset + length > data.lengthInBytes) {
      throw Exception('Unexpected end of VMD data at $offset.');
    }
  }
}
