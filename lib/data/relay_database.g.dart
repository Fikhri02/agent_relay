// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relay_database.dart';

// ignore_for_file: type=lint
class $PeersTable extends Peers with TableInfo<$PeersTable, Peer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personNameMeta = const VerificationMeta(
    'personName',
  );
  @override
  late final GeneratedColumn<String> personName = GeneratedColumn<String>(
    'person_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signPubMeta = const VerificationMeta(
    'signPub',
  );
  @override
  late final GeneratedColumn<Uint8List> signPub = GeneratedColumn<Uint8List>(
    'sign_pub',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _boxPubMeta = const VerificationMeta('boxPub');
  @override
  late final GeneratedColumn<Uint8List> boxPub = GeneratedColumn<Uint8List>(
    'box_pub',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _certFingerprintMeta = const VerificationMeta(
    'certFingerprint',
  );
  @override
  late final GeneratedColumn<String> certFingerprint = GeneratedColumn<String>(
    'cert_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _trustMeta = const VerificationMeta('trust');
  @override
  late final GeneratedColumn<String> trust = GeneratedColumn<String>(
    'trust',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAddressMeta = const VerificationMeta(
    'lastAddress',
  );
  @override
  late final GeneratedColumn<String> lastAddress = GeneratedColumn<String>(
    'last_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastPortMeta = const VerificationMeta(
    'lastPort',
  );
  @override
  late final GeneratedColumn<int> lastPort = GeneratedColumn<int>(
    'last_port',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<int> lastSeenAt = GeneratedColumn<int>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clockSkewMsMeta = const VerificationMeta(
    'clockSkewMs',
  );
  @override
  late final GeneratedColumn<int> clockSkewMs = GeneratedColumn<int>(
    'clock_skew_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<int> pairedAt = GeneratedColumn<int>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    personName,
    deviceName,
    signPub,
    boxPub,
    certFingerprint,
    trust,
    lastAddress,
    lastPort,
    lastSeenAt,
    clockSkewMs,
    pairedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Peer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('person_name')) {
      context.handle(
        _personNameMeta,
        personName.isAcceptableOrUnknown(data['person_name']!, _personNameMeta),
      );
    } else if (isInserting) {
      context.missing(_personNameMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceNameMeta);
    }
    if (data.containsKey('sign_pub')) {
      context.handle(
        _signPubMeta,
        signPub.isAcceptableOrUnknown(data['sign_pub']!, _signPubMeta),
      );
    } else if (isInserting) {
      context.missing(_signPubMeta);
    }
    if (data.containsKey('box_pub')) {
      context.handle(
        _boxPubMeta,
        boxPub.isAcceptableOrUnknown(data['box_pub']!, _boxPubMeta),
      );
    } else if (isInserting) {
      context.missing(_boxPubMeta);
    }
    if (data.containsKey('cert_fingerprint')) {
      context.handle(
        _certFingerprintMeta,
        certFingerprint.isAcceptableOrUnknown(
          data['cert_fingerprint']!,
          _certFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_certFingerprintMeta);
    }
    if (data.containsKey('trust')) {
      context.handle(
        _trustMeta,
        trust.isAcceptableOrUnknown(data['trust']!, _trustMeta),
      );
    } else if (isInserting) {
      context.missing(_trustMeta);
    }
    if (data.containsKey('last_address')) {
      context.handle(
        _lastAddressMeta,
        lastAddress.isAcceptableOrUnknown(
          data['last_address']!,
          _lastAddressMeta,
        ),
      );
    }
    if (data.containsKey('last_port')) {
      context.handle(
        _lastPortMeta,
        lastPort.isAcceptableOrUnknown(data['last_port']!, _lastPortMeta),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('clock_skew_ms')) {
      context.handle(
        _clockSkewMsMeta,
        clockSkewMs.isAcceptableOrUnknown(
          data['clock_skew_ms']!,
          _clockSkewMsMeta,
        ),
      );
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  Peer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Peer(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      personName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_name'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      signPub: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}sign_pub'],
      )!,
      boxPub: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}box_pub'],
      )!,
      certFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cert_fingerprint'],
      )!,
      trust: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trust'],
      )!,
      lastAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_address'],
      ),
      lastPort: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_port'],
      ),
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_at'],
      ),
      clockSkewMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}clock_skew_ms'],
      ),
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paired_at'],
      )!,
    );
  }

  @override
  $PeersTable createAlias(String alias) {
    return $PeersTable(attachedDatabase, alias);
  }
}

class Peer extends DataClass implements Insertable<Peer> {
  final String deviceId;
  final String personName;
  final String deviceName;
  final Uint8List signPub;
  final Uint8List boxPub;
  final String certFingerprint;
  final String trust;
  final String? lastAddress;
  final int? lastPort;
  final int? lastSeenAt;
  final int? clockSkewMs;
  final int pairedAt;
  const Peer({
    required this.deviceId,
    required this.personName,
    required this.deviceName,
    required this.signPub,
    required this.boxPub,
    required this.certFingerprint,
    required this.trust,
    this.lastAddress,
    this.lastPort,
    this.lastSeenAt,
    this.clockSkewMs,
    required this.pairedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['person_name'] = Variable<String>(personName);
    map['device_name'] = Variable<String>(deviceName);
    map['sign_pub'] = Variable<Uint8List>(signPub);
    map['box_pub'] = Variable<Uint8List>(boxPub);
    map['cert_fingerprint'] = Variable<String>(certFingerprint);
    map['trust'] = Variable<String>(trust);
    if (!nullToAbsent || lastAddress != null) {
      map['last_address'] = Variable<String>(lastAddress);
    }
    if (!nullToAbsent || lastPort != null) {
      map['last_port'] = Variable<int>(lastPort);
    }
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<int>(lastSeenAt);
    }
    if (!nullToAbsent || clockSkewMs != null) {
      map['clock_skew_ms'] = Variable<int>(clockSkewMs);
    }
    map['paired_at'] = Variable<int>(pairedAt);
    return map;
  }

  PeersCompanion toCompanion(bool nullToAbsent) {
    return PeersCompanion(
      deviceId: Value(deviceId),
      personName: Value(personName),
      deviceName: Value(deviceName),
      signPub: Value(signPub),
      boxPub: Value(boxPub),
      certFingerprint: Value(certFingerprint),
      trust: Value(trust),
      lastAddress: lastAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAddress),
      lastPort: lastPort == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPort),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      clockSkewMs: clockSkewMs == null && nullToAbsent
          ? const Value.absent()
          : Value(clockSkewMs),
      pairedAt: Value(pairedAt),
    );
  }

  factory Peer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Peer(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      personName: serializer.fromJson<String>(json['personName']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      signPub: serializer.fromJson<Uint8List>(json['signPub']),
      boxPub: serializer.fromJson<Uint8List>(json['boxPub']),
      certFingerprint: serializer.fromJson<String>(json['certFingerprint']),
      trust: serializer.fromJson<String>(json['trust']),
      lastAddress: serializer.fromJson<String?>(json['lastAddress']),
      lastPort: serializer.fromJson<int?>(json['lastPort']),
      lastSeenAt: serializer.fromJson<int?>(json['lastSeenAt']),
      clockSkewMs: serializer.fromJson<int?>(json['clockSkewMs']),
      pairedAt: serializer.fromJson<int>(json['pairedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'personName': serializer.toJson<String>(personName),
      'deviceName': serializer.toJson<String>(deviceName),
      'signPub': serializer.toJson<Uint8List>(signPub),
      'boxPub': serializer.toJson<Uint8List>(boxPub),
      'certFingerprint': serializer.toJson<String>(certFingerprint),
      'trust': serializer.toJson<String>(trust),
      'lastAddress': serializer.toJson<String?>(lastAddress),
      'lastPort': serializer.toJson<int?>(lastPort),
      'lastSeenAt': serializer.toJson<int?>(lastSeenAt),
      'clockSkewMs': serializer.toJson<int?>(clockSkewMs),
      'pairedAt': serializer.toJson<int>(pairedAt),
    };
  }

  Peer copyWith({
    String? deviceId,
    String? personName,
    String? deviceName,
    Uint8List? signPub,
    Uint8List? boxPub,
    String? certFingerprint,
    String? trust,
    Value<String?> lastAddress = const Value.absent(),
    Value<int?> lastPort = const Value.absent(),
    Value<int?> lastSeenAt = const Value.absent(),
    Value<int?> clockSkewMs = const Value.absent(),
    int? pairedAt,
  }) => Peer(
    deviceId: deviceId ?? this.deviceId,
    personName: personName ?? this.personName,
    deviceName: deviceName ?? this.deviceName,
    signPub: signPub ?? this.signPub,
    boxPub: boxPub ?? this.boxPub,
    certFingerprint: certFingerprint ?? this.certFingerprint,
    trust: trust ?? this.trust,
    lastAddress: lastAddress.present ? lastAddress.value : this.lastAddress,
    lastPort: lastPort.present ? lastPort.value : this.lastPort,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    clockSkewMs: clockSkewMs.present ? clockSkewMs.value : this.clockSkewMs,
    pairedAt: pairedAt ?? this.pairedAt,
  );
  Peer copyWithCompanion(PeersCompanion data) {
    return Peer(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      personName: data.personName.present
          ? data.personName.value
          : this.personName,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      signPub: data.signPub.present ? data.signPub.value : this.signPub,
      boxPub: data.boxPub.present ? data.boxPub.value : this.boxPub,
      certFingerprint: data.certFingerprint.present
          ? data.certFingerprint.value
          : this.certFingerprint,
      trust: data.trust.present ? data.trust.value : this.trust,
      lastAddress: data.lastAddress.present
          ? data.lastAddress.value
          : this.lastAddress,
      lastPort: data.lastPort.present ? data.lastPort.value : this.lastPort,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      clockSkewMs: data.clockSkewMs.present
          ? data.clockSkewMs.value
          : this.clockSkewMs,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Peer(')
          ..write('deviceId: $deviceId, ')
          ..write('personName: $personName, ')
          ..write('deviceName: $deviceName, ')
          ..write('signPub: $signPub, ')
          ..write('boxPub: $boxPub, ')
          ..write('certFingerprint: $certFingerprint, ')
          ..write('trust: $trust, ')
          ..write('lastAddress: $lastAddress, ')
          ..write('lastPort: $lastPort, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('clockSkewMs: $clockSkewMs, ')
          ..write('pairedAt: $pairedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    personName,
    deviceName,
    $driftBlobEquality.hash(signPub),
    $driftBlobEquality.hash(boxPub),
    certFingerprint,
    trust,
    lastAddress,
    lastPort,
    lastSeenAt,
    clockSkewMs,
    pairedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Peer &&
          other.deviceId == this.deviceId &&
          other.personName == this.personName &&
          other.deviceName == this.deviceName &&
          $driftBlobEquality.equals(other.signPub, this.signPub) &&
          $driftBlobEquality.equals(other.boxPub, this.boxPub) &&
          other.certFingerprint == this.certFingerprint &&
          other.trust == this.trust &&
          other.lastAddress == this.lastAddress &&
          other.lastPort == this.lastPort &&
          other.lastSeenAt == this.lastSeenAt &&
          other.clockSkewMs == this.clockSkewMs &&
          other.pairedAt == this.pairedAt);
}

class PeersCompanion extends UpdateCompanion<Peer> {
  final Value<String> deviceId;
  final Value<String> personName;
  final Value<String> deviceName;
  final Value<Uint8List> signPub;
  final Value<Uint8List> boxPub;
  final Value<String> certFingerprint;
  final Value<String> trust;
  final Value<String?> lastAddress;
  final Value<int?> lastPort;
  final Value<int?> lastSeenAt;
  final Value<int?> clockSkewMs;
  final Value<int> pairedAt;
  final Value<int> rowid;
  const PeersCompanion({
    this.deviceId = const Value.absent(),
    this.personName = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.signPub = const Value.absent(),
    this.boxPub = const Value.absent(),
    this.certFingerprint = const Value.absent(),
    this.trust = const Value.absent(),
    this.lastAddress = const Value.absent(),
    this.lastPort = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.clockSkewMs = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeersCompanion.insert({
    required String deviceId,
    required String personName,
    required String deviceName,
    required Uint8List signPub,
    required Uint8List boxPub,
    required String certFingerprint,
    required String trust,
    this.lastAddress = const Value.absent(),
    this.lastPort = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.clockSkewMs = const Value.absent(),
    required int pairedAt,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       personName = Value(personName),
       deviceName = Value(deviceName),
       signPub = Value(signPub),
       boxPub = Value(boxPub),
       certFingerprint = Value(certFingerprint),
       trust = Value(trust),
       pairedAt = Value(pairedAt);
  static Insertable<Peer> custom({
    Expression<String>? deviceId,
    Expression<String>? personName,
    Expression<String>? deviceName,
    Expression<Uint8List>? signPub,
    Expression<Uint8List>? boxPub,
    Expression<String>? certFingerprint,
    Expression<String>? trust,
    Expression<String>? lastAddress,
    Expression<int>? lastPort,
    Expression<int>? lastSeenAt,
    Expression<int>? clockSkewMs,
    Expression<int>? pairedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (personName != null) 'person_name': personName,
      if (deviceName != null) 'device_name': deviceName,
      if (signPub != null) 'sign_pub': signPub,
      if (boxPub != null) 'box_pub': boxPub,
      if (certFingerprint != null) 'cert_fingerprint': certFingerprint,
      if (trust != null) 'trust': trust,
      if (lastAddress != null) 'last_address': lastAddress,
      if (lastPort != null) 'last_port': lastPort,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (clockSkewMs != null) 'clock_skew_ms': clockSkewMs,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeersCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? personName,
    Value<String>? deviceName,
    Value<Uint8List>? signPub,
    Value<Uint8List>? boxPub,
    Value<String>? certFingerprint,
    Value<String>? trust,
    Value<String?>? lastAddress,
    Value<int?>? lastPort,
    Value<int?>? lastSeenAt,
    Value<int?>? clockSkewMs,
    Value<int>? pairedAt,
    Value<int>? rowid,
  }) {
    return PeersCompanion(
      deviceId: deviceId ?? this.deviceId,
      personName: personName ?? this.personName,
      deviceName: deviceName ?? this.deviceName,
      signPub: signPub ?? this.signPub,
      boxPub: boxPub ?? this.boxPub,
      certFingerprint: certFingerprint ?? this.certFingerprint,
      trust: trust ?? this.trust,
      lastAddress: lastAddress ?? this.lastAddress,
      lastPort: lastPort ?? this.lastPort,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      clockSkewMs: clockSkewMs ?? this.clockSkewMs,
      pairedAt: pairedAt ?? this.pairedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (personName.present) {
      map['person_name'] = Variable<String>(personName.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (signPub.present) {
      map['sign_pub'] = Variable<Uint8List>(signPub.value);
    }
    if (boxPub.present) {
      map['box_pub'] = Variable<Uint8List>(boxPub.value);
    }
    if (certFingerprint.present) {
      map['cert_fingerprint'] = Variable<String>(certFingerprint.value);
    }
    if (trust.present) {
      map['trust'] = Variable<String>(trust.value);
    }
    if (lastAddress.present) {
      map['last_address'] = Variable<String>(lastAddress.value);
    }
    if (lastPort.present) {
      map['last_port'] = Variable<int>(lastPort.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<int>(lastSeenAt.value);
    }
    if (clockSkewMs.present) {
      map['clock_skew_ms'] = Variable<int>(clockSkewMs.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<int>(pairedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeersCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('personName: $personName, ')
          ..write('deviceName: $deviceName, ')
          ..write('signPub: $signPub, ')
          ..write('boxPub: $boxPub, ')
          ..write('certFingerprint: $certFingerprint, ')
          ..write('trust: $trust, ')
          ..write('lastAddress: $lastAddress, ')
          ..write('lastPort: $lastPort, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('clockSkewMs: $clockSkewMs, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelsTable extends Channels with TableInfo<$ChannelsTable, Channel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _closedAtMeta = const VerificationMeta(
    'closedAt',
  );
  @override
  late final GeneratedColumn<int> closedAt = GeneratedColumn<int>(
    'closed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _creatorDeviceIdMeta = const VerificationMeta(
    'creatorDeviceId',
  );
  @override
  late final GeneratedColumn<String> creatorDeviceId = GeneratedColumn<String>(
    'creator_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    name,
    createdAt,
    closedAt,
    creatorDeviceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<Channel> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('closed_at')) {
      context.handle(
        _closedAtMeta,
        closedAt.isAcceptableOrUnknown(data['closed_at']!, _closedAtMeta),
      );
    }
    if (data.containsKey('creator_device_id')) {
      context.handle(
        _creatorDeviceIdMeta,
        creatorDeviceId.isAcceptableOrUnknown(
          data['creator_device_id']!,
          _creatorDeviceIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Channel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Channel(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      closedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}closed_at'],
      ),
      creatorDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creator_device_id'],
      ),
    );
  }

  @override
  $ChannelsTable createAlias(String alias) {
    return $ChannelsTable(attachedDatabase, alias);
  }
}

class Channel extends DataClass implements Insertable<Channel> {
  final String id;
  final String kind;
  final String? name;
  final int createdAt;
  final int? closedAt;
  final String? creatorDeviceId;
  const Channel({
    required this.id,
    required this.kind,
    this.name,
    required this.createdAt,
    this.closedAt,
    this.creatorDeviceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || closedAt != null) {
      map['closed_at'] = Variable<int>(closedAt);
    }
    if (!nullToAbsent || creatorDeviceId != null) {
      map['creator_device_id'] = Variable<String>(creatorDeviceId);
    }
    return map;
  }

  ChannelsCompanion toCompanion(bool nullToAbsent) {
    return ChannelsCompanion(
      id: Value(id),
      kind: Value(kind),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      createdAt: Value(createdAt),
      closedAt: closedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(closedAt),
      creatorDeviceId: creatorDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(creatorDeviceId),
    );
  }

  factory Channel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Channel(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String?>(json['name']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      closedAt: serializer.fromJson<int?>(json['closedAt']),
      creatorDeviceId: serializer.fromJson<String?>(json['creatorDeviceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String?>(name),
      'createdAt': serializer.toJson<int>(createdAt),
      'closedAt': serializer.toJson<int?>(closedAt),
      'creatorDeviceId': serializer.toJson<String?>(creatorDeviceId),
    };
  }

  Channel copyWith({
    String? id,
    String? kind,
    Value<String?> name = const Value.absent(),
    int? createdAt,
    Value<int?> closedAt = const Value.absent(),
    Value<String?> creatorDeviceId = const Value.absent(),
  }) => Channel(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name.present ? name.value : this.name,
    createdAt: createdAt ?? this.createdAt,
    closedAt: closedAt.present ? closedAt.value : this.closedAt,
    creatorDeviceId: creatorDeviceId.present
        ? creatorDeviceId.value
        : this.creatorDeviceId,
  );
  Channel copyWithCompanion(ChannelsCompanion data) {
    return Channel(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      closedAt: data.closedAt.present ? data.closedAt.value : this.closedAt,
      creatorDeviceId: data.creatorDeviceId.present
          ? data.creatorDeviceId.value
          : this.creatorDeviceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Channel(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('closedAt: $closedAt, ')
          ..write('creatorDeviceId: $creatorDeviceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, name, createdAt, closedAt, creatorDeviceId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Channel &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.closedAt == this.closedAt &&
          other.creatorDeviceId == this.creatorDeviceId);
}

class ChannelsCompanion extends UpdateCompanion<Channel> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String?> name;
  final Value<int> createdAt;
  final Value<int?> closedAt;
  final Value<String?> creatorDeviceId;
  final Value<int> rowid;
  const ChannelsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.closedAt = const Value.absent(),
    this.creatorDeviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelsCompanion.insert({
    required String id,
    required String kind,
    this.name = const Value.absent(),
    required int createdAt,
    this.closedAt = const Value.absent(),
    this.creatorDeviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<Channel> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<int>? createdAt,
    Expression<int>? closedAt,
    Expression<String>? creatorDeviceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (closedAt != null) 'closed_at': closedAt,
      if (creatorDeviceId != null) 'creator_device_id': creatorDeviceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelsCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String?>? name,
    Value<int>? createdAt,
    Value<int?>? closedAt,
    Value<String?>? creatorDeviceId,
    Value<int>? rowid,
  }) {
    return ChannelsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      closedAt: closedAt ?? this.closedAt,
      creatorDeviceId: creatorDeviceId ?? this.creatorDeviceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (closedAt.present) {
      map['closed_at'] = Variable<int>(closedAt.value);
    }
    if (creatorDeviceId.present) {
      map['creator_device_id'] = Variable<String>(creatorDeviceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('closedAt: $closedAt, ')
          ..write('creatorDeviceId: $creatorDeviceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChannelMembersTable extends ChannelMembers
    with TableInfo<$ChannelMembersTable, ChannelMember> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChannelMembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _channelIdMeta = const VerificationMeta(
    'channelId',
  );
  @override
  late final GeneratedColumn<String> channelId = GeneratedColumn<String>(
    'channel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _joinedHlcMeta = const VerificationMeta(
    'joinedHlc',
  );
  @override
  late final GeneratedColumn<String> joinedHlc = GeneratedColumn<String>(
    'joined_hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _leftHlcMeta = const VerificationMeta(
    'leftHlc',
  );
  @override
  late final GeneratedColumn<String> leftHlc = GeneratedColumn<String>(
    'left_hlc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('member'),
  );
  static const VerificationMeta _inviterDeviceIdMeta = const VerificationMeta(
    'inviterDeviceId',
  );
  @override
  late final GeneratedColumn<String> inviterDeviceId = GeneratedColumn<String>(
    'inviter_device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _myApprovalMeta = const VerificationMeta(
    'myApproval',
  );
  @override
  late final GeneratedColumn<String> myApproval = GeneratedColumn<String>(
    'my_approval',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _theirApprovalMeta = const VerificationMeta(
    'theirApproval',
  );
  @override
  late final GeneratedColumn<String> theirApproval = GeneratedColumn<String>(
    'their_approval',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _personNameMeta = const VerificationMeta(
    'personName',
  );
  @override
  late final GeneratedColumn<String> personName = GeneratedColumn<String>(
    'person_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    channelId,
    deviceId,
    joinedHlc,
    leftHlc,
    state,
    inviterDeviceId,
    myApproval,
    theirApproval,
    personName,
    deviceName,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'channel_members';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChannelMember> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('channel_id')) {
      context.handle(
        _channelIdMeta,
        channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('joined_hlc')) {
      context.handle(
        _joinedHlcMeta,
        joinedHlc.isAcceptableOrUnknown(data['joined_hlc']!, _joinedHlcMeta),
      );
    } else if (isInserting) {
      context.missing(_joinedHlcMeta);
    }
    if (data.containsKey('left_hlc')) {
      context.handle(
        _leftHlcMeta,
        leftHlc.isAcceptableOrUnknown(data['left_hlc']!, _leftHlcMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    }
    if (data.containsKey('inviter_device_id')) {
      context.handle(
        _inviterDeviceIdMeta,
        inviterDeviceId.isAcceptableOrUnknown(
          data['inviter_device_id']!,
          _inviterDeviceIdMeta,
        ),
      );
    }
    if (data.containsKey('my_approval')) {
      context.handle(
        _myApprovalMeta,
        myApproval.isAcceptableOrUnknown(data['my_approval']!, _myApprovalMeta),
      );
    }
    if (data.containsKey('their_approval')) {
      context.handle(
        _theirApprovalMeta,
        theirApproval.isAcceptableOrUnknown(
          data['their_approval']!,
          _theirApprovalMeta,
        ),
      );
    }
    if (data.containsKey('person_name')) {
      context.handle(
        _personNameMeta,
        personName.isAcceptableOrUnknown(data['person_name']!, _personNameMeta),
      );
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {channelId, deviceId};
  @override
  ChannelMember map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChannelMember(
      channelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      joinedHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}joined_hlc'],
      )!,
      leftHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}left_hlc'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      inviterDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}inviter_device_id'],
      ),
      myApproval: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}my_approval'],
      ),
      theirApproval: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}their_approval'],
      ),
      personName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_name'],
      ),
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      ),
    );
  }

  @override
  $ChannelMembersTable createAlias(String alias) {
    return $ChannelMembersTable(attachedDatabase, alias);
  }
}

class ChannelMember extends DataClass implements Insertable<ChannelMember> {
  final String channelId;
  final String deviceId;
  final String joinedHlc;
  final String? leftHlc;

  /// `invited` | `member` | `left` | `declined`.
  final String state;
  final String? inviterDeviceId;

  /// `approved` | `declined`; null = undecided. [myApproval] is my decision
  /// about this member, [theirApproval] is theirs about me.
  final String? myApproval;
  final String? theirApproval;

  /// Display names for members who are not peers yet.
  final String? personName;
  final String? deviceName;
  const ChannelMember({
    required this.channelId,
    required this.deviceId,
    required this.joinedHlc,
    this.leftHlc,
    required this.state,
    this.inviterDeviceId,
    this.myApproval,
    this.theirApproval,
    this.personName,
    this.deviceName,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['channel_id'] = Variable<String>(channelId);
    map['device_id'] = Variable<String>(deviceId);
    map['joined_hlc'] = Variable<String>(joinedHlc);
    if (!nullToAbsent || leftHlc != null) {
      map['left_hlc'] = Variable<String>(leftHlc);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || inviterDeviceId != null) {
      map['inviter_device_id'] = Variable<String>(inviterDeviceId);
    }
    if (!nullToAbsent || myApproval != null) {
      map['my_approval'] = Variable<String>(myApproval);
    }
    if (!nullToAbsent || theirApproval != null) {
      map['their_approval'] = Variable<String>(theirApproval);
    }
    if (!nullToAbsent || personName != null) {
      map['person_name'] = Variable<String>(personName);
    }
    if (!nullToAbsent || deviceName != null) {
      map['device_name'] = Variable<String>(deviceName);
    }
    return map;
  }

  ChannelMembersCompanion toCompanion(bool nullToAbsent) {
    return ChannelMembersCompanion(
      channelId: Value(channelId),
      deviceId: Value(deviceId),
      joinedHlc: Value(joinedHlc),
      leftHlc: leftHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(leftHlc),
      state: Value(state),
      inviterDeviceId: inviterDeviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(inviterDeviceId),
      myApproval: myApproval == null && nullToAbsent
          ? const Value.absent()
          : Value(myApproval),
      theirApproval: theirApproval == null && nullToAbsent
          ? const Value.absent()
          : Value(theirApproval),
      personName: personName == null && nullToAbsent
          ? const Value.absent()
          : Value(personName),
      deviceName: deviceName == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceName),
    );
  }

  factory ChannelMember.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChannelMember(
      channelId: serializer.fromJson<String>(json['channelId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      joinedHlc: serializer.fromJson<String>(json['joinedHlc']),
      leftHlc: serializer.fromJson<String?>(json['leftHlc']),
      state: serializer.fromJson<String>(json['state']),
      inviterDeviceId: serializer.fromJson<String?>(json['inviterDeviceId']),
      myApproval: serializer.fromJson<String?>(json['myApproval']),
      theirApproval: serializer.fromJson<String?>(json['theirApproval']),
      personName: serializer.fromJson<String?>(json['personName']),
      deviceName: serializer.fromJson<String?>(json['deviceName']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'channelId': serializer.toJson<String>(channelId),
      'deviceId': serializer.toJson<String>(deviceId),
      'joinedHlc': serializer.toJson<String>(joinedHlc),
      'leftHlc': serializer.toJson<String?>(leftHlc),
      'state': serializer.toJson<String>(state),
      'inviterDeviceId': serializer.toJson<String?>(inviterDeviceId),
      'myApproval': serializer.toJson<String?>(myApproval),
      'theirApproval': serializer.toJson<String?>(theirApproval),
      'personName': serializer.toJson<String?>(personName),
      'deviceName': serializer.toJson<String?>(deviceName),
    };
  }

  ChannelMember copyWith({
    String? channelId,
    String? deviceId,
    String? joinedHlc,
    Value<String?> leftHlc = const Value.absent(),
    String? state,
    Value<String?> inviterDeviceId = const Value.absent(),
    Value<String?> myApproval = const Value.absent(),
    Value<String?> theirApproval = const Value.absent(),
    Value<String?> personName = const Value.absent(),
    Value<String?> deviceName = const Value.absent(),
  }) => ChannelMember(
    channelId: channelId ?? this.channelId,
    deviceId: deviceId ?? this.deviceId,
    joinedHlc: joinedHlc ?? this.joinedHlc,
    leftHlc: leftHlc.present ? leftHlc.value : this.leftHlc,
    state: state ?? this.state,
    inviterDeviceId: inviterDeviceId.present
        ? inviterDeviceId.value
        : this.inviterDeviceId,
    myApproval: myApproval.present ? myApproval.value : this.myApproval,
    theirApproval: theirApproval.present
        ? theirApproval.value
        : this.theirApproval,
    personName: personName.present ? personName.value : this.personName,
    deviceName: deviceName.present ? deviceName.value : this.deviceName,
  );
  ChannelMember copyWithCompanion(ChannelMembersCompanion data) {
    return ChannelMember(
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      joinedHlc: data.joinedHlc.present ? data.joinedHlc.value : this.joinedHlc,
      leftHlc: data.leftHlc.present ? data.leftHlc.value : this.leftHlc,
      state: data.state.present ? data.state.value : this.state,
      inviterDeviceId: data.inviterDeviceId.present
          ? data.inviterDeviceId.value
          : this.inviterDeviceId,
      myApproval: data.myApproval.present
          ? data.myApproval.value
          : this.myApproval,
      theirApproval: data.theirApproval.present
          ? data.theirApproval.value
          : this.theirApproval,
      personName: data.personName.present
          ? data.personName.value
          : this.personName,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChannelMember(')
          ..write('channelId: $channelId, ')
          ..write('deviceId: $deviceId, ')
          ..write('joinedHlc: $joinedHlc, ')
          ..write('leftHlc: $leftHlc, ')
          ..write('state: $state, ')
          ..write('inviterDeviceId: $inviterDeviceId, ')
          ..write('myApproval: $myApproval, ')
          ..write('theirApproval: $theirApproval, ')
          ..write('personName: $personName, ')
          ..write('deviceName: $deviceName')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    channelId,
    deviceId,
    joinedHlc,
    leftHlc,
    state,
    inviterDeviceId,
    myApproval,
    theirApproval,
    personName,
    deviceName,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChannelMember &&
          other.channelId == this.channelId &&
          other.deviceId == this.deviceId &&
          other.joinedHlc == this.joinedHlc &&
          other.leftHlc == this.leftHlc &&
          other.state == this.state &&
          other.inviterDeviceId == this.inviterDeviceId &&
          other.myApproval == this.myApproval &&
          other.theirApproval == this.theirApproval &&
          other.personName == this.personName &&
          other.deviceName == this.deviceName);
}

class ChannelMembersCompanion extends UpdateCompanion<ChannelMember> {
  final Value<String> channelId;
  final Value<String> deviceId;
  final Value<String> joinedHlc;
  final Value<String?> leftHlc;
  final Value<String> state;
  final Value<String?> inviterDeviceId;
  final Value<String?> myApproval;
  final Value<String?> theirApproval;
  final Value<String?> personName;
  final Value<String?> deviceName;
  final Value<int> rowid;
  const ChannelMembersCompanion({
    this.channelId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.joinedHlc = const Value.absent(),
    this.leftHlc = const Value.absent(),
    this.state = const Value.absent(),
    this.inviterDeviceId = const Value.absent(),
    this.myApproval = const Value.absent(),
    this.theirApproval = const Value.absent(),
    this.personName = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChannelMembersCompanion.insert({
    required String channelId,
    required String deviceId,
    required String joinedHlc,
    this.leftHlc = const Value.absent(),
    this.state = const Value.absent(),
    this.inviterDeviceId = const Value.absent(),
    this.myApproval = const Value.absent(),
    this.theirApproval = const Value.absent(),
    this.personName = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : channelId = Value(channelId),
       deviceId = Value(deviceId),
       joinedHlc = Value(joinedHlc);
  static Insertable<ChannelMember> custom({
    Expression<String>? channelId,
    Expression<String>? deviceId,
    Expression<String>? joinedHlc,
    Expression<String>? leftHlc,
    Expression<String>? state,
    Expression<String>? inviterDeviceId,
    Expression<String>? myApproval,
    Expression<String>? theirApproval,
    Expression<String>? personName,
    Expression<String>? deviceName,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (channelId != null) 'channel_id': channelId,
      if (deviceId != null) 'device_id': deviceId,
      if (joinedHlc != null) 'joined_hlc': joinedHlc,
      if (leftHlc != null) 'left_hlc': leftHlc,
      if (state != null) 'state': state,
      if (inviterDeviceId != null) 'inviter_device_id': inviterDeviceId,
      if (myApproval != null) 'my_approval': myApproval,
      if (theirApproval != null) 'their_approval': theirApproval,
      if (personName != null) 'person_name': personName,
      if (deviceName != null) 'device_name': deviceName,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChannelMembersCompanion copyWith({
    Value<String>? channelId,
    Value<String>? deviceId,
    Value<String>? joinedHlc,
    Value<String?>? leftHlc,
    Value<String>? state,
    Value<String?>? inviterDeviceId,
    Value<String?>? myApproval,
    Value<String?>? theirApproval,
    Value<String?>? personName,
    Value<String?>? deviceName,
    Value<int>? rowid,
  }) {
    return ChannelMembersCompanion(
      channelId: channelId ?? this.channelId,
      deviceId: deviceId ?? this.deviceId,
      joinedHlc: joinedHlc ?? this.joinedHlc,
      leftHlc: leftHlc ?? this.leftHlc,
      state: state ?? this.state,
      inviterDeviceId: inviterDeviceId ?? this.inviterDeviceId,
      myApproval: myApproval ?? this.myApproval,
      theirApproval: theirApproval ?? this.theirApproval,
      personName: personName ?? this.personName,
      deviceName: deviceName ?? this.deviceName,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (channelId.present) {
      map['channel_id'] = Variable<String>(channelId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (joinedHlc.present) {
      map['joined_hlc'] = Variable<String>(joinedHlc.value);
    }
    if (leftHlc.present) {
      map['left_hlc'] = Variable<String>(leftHlc.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (inviterDeviceId.present) {
      map['inviter_device_id'] = Variable<String>(inviterDeviceId.value);
    }
    if (myApproval.present) {
      map['my_approval'] = Variable<String>(myApproval.value);
    }
    if (theirApproval.present) {
      map['their_approval'] = Variable<String>(theirApproval.value);
    }
    if (personName.present) {
      map['person_name'] = Variable<String>(personName.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChannelMembersCompanion(')
          ..write('channelId: $channelId, ')
          ..write('deviceId: $deviceId, ')
          ..write('joinedHlc: $joinedHlc, ')
          ..write('leftHlc: $leftHlc, ')
          ..write('state: $state, ')
          ..write('inviterDeviceId: $inviterDeviceId, ')
          ..write('myApproval: $myApproval, ')
          ..write('theirApproval: $theirApproval, ')
          ..write('personName: $personName, ')
          ..write('deviceName: $deviceName, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelIdMeta = const VerificationMeta(
    'channelId',
  );
  @override
  late final GeneratedColumn<String> channelId = GeneratedColumn<String>(
    'channel_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromDeviceIdMeta = const VerificationMeta(
    'fromDeviceId',
  );
  @override
  late final GeneratedColumn<String> fromDeviceId = GeneratedColumn<String>(
    'from_device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<int> sentAt = GeneratedColumn<int>(
    'sent_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contextJsonMeta = const VerificationMeta(
    'contextJson',
  );
  @override
  late final GeneratedColumn<String> contextJson = GeneratedColumn<String>(
    'context_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToMeta = const VerificationMeta(
    'replyTo',
  );
  @override
  late final GeneratedColumn<String> replyTo = GeneratedColumn<String>(
    'reply_to',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _arrivedLateMeta = const VerificationMeta(
    'arrivedLate',
  );
  @override
  late final GeneratedColumn<bool> arrivedLate = GeneratedColumn<bool>(
    'arrived_late',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("arrived_late" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<int> receivedAt = GeneratedColumn<int>(
    'received_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seenAtMeta = const VerificationMeta('seenAt');
  @override
  late final GeneratedColumn<int> seenAt = GeneratedColumn<int>(
    'seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _agentReadAtMeta = const VerificationMeta(
    'agentReadAt',
  );
  @override
  late final GeneratedColumn<int> agentReadAt = GeneratedColumn<int>(
    'agent_read_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    channelId,
    kind,
    fromDeviceId,
    sentAt,
    hlc,
    seq,
    body,
    contextJson,
    replyTo,
    direction,
    status,
    arrivedLate,
    createdAt,
    receivedAt,
    seenAt,
    agentReadAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('channel_id')) {
      context.handle(
        _channelIdMeta,
        channelId.isAcceptableOrUnknown(data['channel_id']!, _channelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_channelIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('from_device_id')) {
      context.handle(
        _fromDeviceIdMeta,
        fromDeviceId.isAcceptableOrUnknown(
          data['from_device_id']!,
          _fromDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fromDeviceIdMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    } else if (isInserting) {
      context.missing(_sentAtMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    }
    if (data.containsKey('context_json')) {
      context.handle(
        _contextJsonMeta,
        contextJson.isAcceptableOrUnknown(
          data['context_json']!,
          _contextJsonMeta,
        ),
      );
    }
    if (data.containsKey('reply_to')) {
      context.handle(
        _replyToMeta,
        replyTo.isAcceptableOrUnknown(data['reply_to']!, _replyToMeta),
      );
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('arrived_late')) {
      context.handle(
        _arrivedLateMeta,
        arrivedLate.isAcceptableOrUnknown(
          data['arrived_late']!,
          _arrivedLateMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    }
    if (data.containsKey('seen_at')) {
      context.handle(
        _seenAtMeta,
        seenAt.isAcceptableOrUnknown(data['seen_at']!, _seenAtMeta),
      );
    }
    if (data.containsKey('agent_read_at')) {
      context.handle(
        _agentReadAtMeta,
        agentReadAt.isAcceptableOrUnknown(
          data['agent_read_at']!,
          _agentReadAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      channelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      fromDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_device_id'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sent_at'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      ),
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      ),
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      ),
      contextJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}context_json'],
      ),
      replyTo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to'],
      ),
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      arrivedLate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}arrived_late'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_at'],
      ),
      seenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seen_at'],
      ),
      agentReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}agent_read_at'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String channelId;
  final String kind;
  final String fromDeviceId;
  final int sentAt;
  final String? hlc;
  final int? seq;
  final String? body;
  final String? contextJson;
  final String? replyTo;
  final String direction;
  final String status;
  final bool arrivedLate;
  final int createdAt;
  final int? receivedAt;

  /// Receiver side: when this person saw it in the app / their agent read it
  /// through the local API. Each sends one receipt back.
  final int? seenAt;
  final int? agentReadAt;
  const Message({
    required this.id,
    required this.channelId,
    required this.kind,
    required this.fromDeviceId,
    required this.sentAt,
    this.hlc,
    this.seq,
    this.body,
    this.contextJson,
    this.replyTo,
    required this.direction,
    required this.status,
    required this.arrivedLate,
    required this.createdAt,
    this.receivedAt,
    this.seenAt,
    this.agentReadAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['channel_id'] = Variable<String>(channelId);
    map['kind'] = Variable<String>(kind);
    map['from_device_id'] = Variable<String>(fromDeviceId);
    map['sent_at'] = Variable<int>(sentAt);
    if (!nullToAbsent || hlc != null) {
      map['hlc'] = Variable<String>(hlc);
    }
    if (!nullToAbsent || seq != null) {
      map['seq'] = Variable<int>(seq);
    }
    if (!nullToAbsent || body != null) {
      map['body'] = Variable<String>(body);
    }
    if (!nullToAbsent || contextJson != null) {
      map['context_json'] = Variable<String>(contextJson);
    }
    if (!nullToAbsent || replyTo != null) {
      map['reply_to'] = Variable<String>(replyTo);
    }
    map['direction'] = Variable<String>(direction);
    map['status'] = Variable<String>(status);
    map['arrived_late'] = Variable<bool>(arrivedLate);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || receivedAt != null) {
      map['received_at'] = Variable<int>(receivedAt);
    }
    if (!nullToAbsent || seenAt != null) {
      map['seen_at'] = Variable<int>(seenAt);
    }
    if (!nullToAbsent || agentReadAt != null) {
      map['agent_read_at'] = Variable<int>(agentReadAt);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      channelId: Value(channelId),
      kind: Value(kind),
      fromDeviceId: Value(fromDeviceId),
      sentAt: Value(sentAt),
      hlc: hlc == null && nullToAbsent ? const Value.absent() : Value(hlc),
      seq: seq == null && nullToAbsent ? const Value.absent() : Value(seq),
      body: body == null && nullToAbsent ? const Value.absent() : Value(body),
      contextJson: contextJson == null && nullToAbsent
          ? const Value.absent()
          : Value(contextJson),
      replyTo: replyTo == null && nullToAbsent
          ? const Value.absent()
          : Value(replyTo),
      direction: Value(direction),
      status: Value(status),
      arrivedLate: Value(arrivedLate),
      createdAt: Value(createdAt),
      receivedAt: receivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(receivedAt),
      seenAt: seenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(seenAt),
      agentReadAt: agentReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(agentReadAt),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      channelId: serializer.fromJson<String>(json['channelId']),
      kind: serializer.fromJson<String>(json['kind']),
      fromDeviceId: serializer.fromJson<String>(json['fromDeviceId']),
      sentAt: serializer.fromJson<int>(json['sentAt']),
      hlc: serializer.fromJson<String?>(json['hlc']),
      seq: serializer.fromJson<int?>(json['seq']),
      body: serializer.fromJson<String?>(json['body']),
      contextJson: serializer.fromJson<String?>(json['contextJson']),
      replyTo: serializer.fromJson<String?>(json['replyTo']),
      direction: serializer.fromJson<String>(json['direction']),
      status: serializer.fromJson<String>(json['status']),
      arrivedLate: serializer.fromJson<bool>(json['arrivedLate']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      receivedAt: serializer.fromJson<int?>(json['receivedAt']),
      seenAt: serializer.fromJson<int?>(json['seenAt']),
      agentReadAt: serializer.fromJson<int?>(json['agentReadAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'channelId': serializer.toJson<String>(channelId),
      'kind': serializer.toJson<String>(kind),
      'fromDeviceId': serializer.toJson<String>(fromDeviceId),
      'sentAt': serializer.toJson<int>(sentAt),
      'hlc': serializer.toJson<String?>(hlc),
      'seq': serializer.toJson<int?>(seq),
      'body': serializer.toJson<String?>(body),
      'contextJson': serializer.toJson<String?>(contextJson),
      'replyTo': serializer.toJson<String?>(replyTo),
      'direction': serializer.toJson<String>(direction),
      'status': serializer.toJson<String>(status),
      'arrivedLate': serializer.toJson<bool>(arrivedLate),
      'createdAt': serializer.toJson<int>(createdAt),
      'receivedAt': serializer.toJson<int?>(receivedAt),
      'seenAt': serializer.toJson<int?>(seenAt),
      'agentReadAt': serializer.toJson<int?>(agentReadAt),
    };
  }

  Message copyWith({
    String? id,
    String? channelId,
    String? kind,
    String? fromDeviceId,
    int? sentAt,
    Value<String?> hlc = const Value.absent(),
    Value<int?> seq = const Value.absent(),
    Value<String?> body = const Value.absent(),
    Value<String?> contextJson = const Value.absent(),
    Value<String?> replyTo = const Value.absent(),
    String? direction,
    String? status,
    bool? arrivedLate,
    int? createdAt,
    Value<int?> receivedAt = const Value.absent(),
    Value<int?> seenAt = const Value.absent(),
    Value<int?> agentReadAt = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    channelId: channelId ?? this.channelId,
    kind: kind ?? this.kind,
    fromDeviceId: fromDeviceId ?? this.fromDeviceId,
    sentAt: sentAt ?? this.sentAt,
    hlc: hlc.present ? hlc.value : this.hlc,
    seq: seq.present ? seq.value : this.seq,
    body: body.present ? body.value : this.body,
    contextJson: contextJson.present ? contextJson.value : this.contextJson,
    replyTo: replyTo.present ? replyTo.value : this.replyTo,
    direction: direction ?? this.direction,
    status: status ?? this.status,
    arrivedLate: arrivedLate ?? this.arrivedLate,
    createdAt: createdAt ?? this.createdAt,
    receivedAt: receivedAt.present ? receivedAt.value : this.receivedAt,
    seenAt: seenAt.present ? seenAt.value : this.seenAt,
    agentReadAt: agentReadAt.present ? agentReadAt.value : this.agentReadAt,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      channelId: data.channelId.present ? data.channelId.value : this.channelId,
      kind: data.kind.present ? data.kind.value : this.kind,
      fromDeviceId: data.fromDeviceId.present
          ? data.fromDeviceId.value
          : this.fromDeviceId,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      seq: data.seq.present ? data.seq.value : this.seq,
      body: data.body.present ? data.body.value : this.body,
      contextJson: data.contextJson.present
          ? data.contextJson.value
          : this.contextJson,
      replyTo: data.replyTo.present ? data.replyTo.value : this.replyTo,
      direction: data.direction.present ? data.direction.value : this.direction,
      status: data.status.present ? data.status.value : this.status,
      arrivedLate: data.arrivedLate.present
          ? data.arrivedLate.value
          : this.arrivedLate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
      seenAt: data.seenAt.present ? data.seenAt.value : this.seenAt,
      agentReadAt: data.agentReadAt.present
          ? data.agentReadAt.value
          : this.agentReadAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('channelId: $channelId, ')
          ..write('kind: $kind, ')
          ..write('fromDeviceId: $fromDeviceId, ')
          ..write('sentAt: $sentAt, ')
          ..write('hlc: $hlc, ')
          ..write('seq: $seq, ')
          ..write('body: $body, ')
          ..write('contextJson: $contextJson, ')
          ..write('replyTo: $replyTo, ')
          ..write('direction: $direction, ')
          ..write('status: $status, ')
          ..write('arrivedLate: $arrivedLate, ')
          ..write('createdAt: $createdAt, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('seenAt: $seenAt, ')
          ..write('agentReadAt: $agentReadAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    channelId,
    kind,
    fromDeviceId,
    sentAt,
    hlc,
    seq,
    body,
    contextJson,
    replyTo,
    direction,
    status,
    arrivedLate,
    createdAt,
    receivedAt,
    seenAt,
    agentReadAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.channelId == this.channelId &&
          other.kind == this.kind &&
          other.fromDeviceId == this.fromDeviceId &&
          other.sentAt == this.sentAt &&
          other.hlc == this.hlc &&
          other.seq == this.seq &&
          other.body == this.body &&
          other.contextJson == this.contextJson &&
          other.replyTo == this.replyTo &&
          other.direction == this.direction &&
          other.status == this.status &&
          other.arrivedLate == this.arrivedLate &&
          other.createdAt == this.createdAt &&
          other.receivedAt == this.receivedAt &&
          other.seenAt == this.seenAt &&
          other.agentReadAt == this.agentReadAt);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> channelId;
  final Value<String> kind;
  final Value<String> fromDeviceId;
  final Value<int> sentAt;
  final Value<String?> hlc;
  final Value<int?> seq;
  final Value<String?> body;
  final Value<String?> contextJson;
  final Value<String?> replyTo;
  final Value<String> direction;
  final Value<String> status;
  final Value<bool> arrivedLate;
  final Value<int> createdAt;
  final Value<int?> receivedAt;
  final Value<int?> seenAt;
  final Value<int?> agentReadAt;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.channelId = const Value.absent(),
    this.kind = const Value.absent(),
    this.fromDeviceId = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.hlc = const Value.absent(),
    this.seq = const Value.absent(),
    this.body = const Value.absent(),
    this.contextJson = const Value.absent(),
    this.replyTo = const Value.absent(),
    this.direction = const Value.absent(),
    this.status = const Value.absent(),
    this.arrivedLate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.receivedAt = const Value.absent(),
    this.seenAt = const Value.absent(),
    this.agentReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String channelId,
    required String kind,
    required String fromDeviceId,
    required int sentAt,
    this.hlc = const Value.absent(),
    this.seq = const Value.absent(),
    this.body = const Value.absent(),
    this.contextJson = const Value.absent(),
    this.replyTo = const Value.absent(),
    required String direction,
    required String status,
    this.arrivedLate = const Value.absent(),
    required int createdAt,
    this.receivedAt = const Value.absent(),
    this.seenAt = const Value.absent(),
    this.agentReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       channelId = Value(channelId),
       kind = Value(kind),
       fromDeviceId = Value(fromDeviceId),
       sentAt = Value(sentAt),
       direction = Value(direction),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? channelId,
    Expression<String>? kind,
    Expression<String>? fromDeviceId,
    Expression<int>? sentAt,
    Expression<String>? hlc,
    Expression<int>? seq,
    Expression<String>? body,
    Expression<String>? contextJson,
    Expression<String>? replyTo,
    Expression<String>? direction,
    Expression<String>? status,
    Expression<bool>? arrivedLate,
    Expression<int>? createdAt,
    Expression<int>? receivedAt,
    Expression<int>? seenAt,
    Expression<int>? agentReadAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (channelId != null) 'channel_id': channelId,
      if (kind != null) 'kind': kind,
      if (fromDeviceId != null) 'from_device_id': fromDeviceId,
      if (sentAt != null) 'sent_at': sentAt,
      if (hlc != null) 'hlc': hlc,
      if (seq != null) 'seq': seq,
      if (body != null) 'body': body,
      if (contextJson != null) 'context_json': contextJson,
      if (replyTo != null) 'reply_to': replyTo,
      if (direction != null) 'direction': direction,
      if (status != null) 'status': status,
      if (arrivedLate != null) 'arrived_late': arrivedLate,
      if (createdAt != null) 'created_at': createdAt,
      if (receivedAt != null) 'received_at': receivedAt,
      if (seenAt != null) 'seen_at': seenAt,
      if (agentReadAt != null) 'agent_read_at': agentReadAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? channelId,
    Value<String>? kind,
    Value<String>? fromDeviceId,
    Value<int>? sentAt,
    Value<String?>? hlc,
    Value<int?>? seq,
    Value<String?>? body,
    Value<String?>? contextJson,
    Value<String?>? replyTo,
    Value<String>? direction,
    Value<String>? status,
    Value<bool>? arrivedLate,
    Value<int>? createdAt,
    Value<int?>? receivedAt,
    Value<int?>? seenAt,
    Value<int?>? agentReadAt,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      kind: kind ?? this.kind,
      fromDeviceId: fromDeviceId ?? this.fromDeviceId,
      sentAt: sentAt ?? this.sentAt,
      hlc: hlc ?? this.hlc,
      seq: seq ?? this.seq,
      body: body ?? this.body,
      contextJson: contextJson ?? this.contextJson,
      replyTo: replyTo ?? this.replyTo,
      direction: direction ?? this.direction,
      status: status ?? this.status,
      arrivedLate: arrivedLate ?? this.arrivedLate,
      createdAt: createdAt ?? this.createdAt,
      receivedAt: receivedAt ?? this.receivedAt,
      seenAt: seenAt ?? this.seenAt,
      agentReadAt: agentReadAt ?? this.agentReadAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (channelId.present) {
      map['channel_id'] = Variable<String>(channelId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (fromDeviceId.present) {
      map['from_device_id'] = Variable<String>(fromDeviceId.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<int>(sentAt.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (contextJson.present) {
      map['context_json'] = Variable<String>(contextJson.value);
    }
    if (replyTo.present) {
      map['reply_to'] = Variable<String>(replyTo.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (arrivedLate.present) {
      map['arrived_late'] = Variable<bool>(arrivedLate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<int>(receivedAt.value);
    }
    if (seenAt.present) {
      map['seen_at'] = Variable<int>(seenAt.value);
    }
    if (agentReadAt.present) {
      map['agent_read_at'] = Variable<int>(agentReadAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('channelId: $channelId, ')
          ..write('kind: $kind, ')
          ..write('fromDeviceId: $fromDeviceId, ')
          ..write('sentAt: $sentAt, ')
          ..write('hlc: $hlc, ')
          ..write('seq: $seq, ')
          ..write('body: $body, ')
          ..write('contextJson: $contextJson, ')
          ..write('replyTo: $replyTo, ')
          ..write('direction: $direction, ')
          ..write('status: $status, ')
          ..write('arrivedLate: $arrivedLate, ')
          ..write('createdAt: $createdAt, ')
          ..write('receivedAt: $receivedAt, ')
          ..write('seenAt: $seenAt, ')
          ..write('agentReadAt: $agentReadAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeliveriesTable extends Deliveries
    with TableInfo<$DeliveriesTable, Delivery> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeliveriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recipientDeviceIdMeta = const VerificationMeta(
    'recipientDeviceId',
  );
  @override
  late final GeneratedColumn<String> recipientDeviceId =
      GeneratedColumn<String>(
        'recipient_device_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _envelopeJsonMeta = const VerificationMeta(
    'envelopeJson',
  );
  @override
  late final GeneratedColumn<String> envelopeJson = GeneratedColumn<String>(
    'envelope_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<int> nextAttemptAt = GeneratedColumn<int>(
    'next_attempt_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deliveredAtMeta = const VerificationMeta(
    'deliveredAt',
  );
  @override
  late final GeneratedColumn<int> deliveredAt = GeneratedColumn<int>(
    'delivered_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seenAtMeta = const VerificationMeta('seenAt');
  @override
  late final GeneratedColumn<int> seenAt = GeneratedColumn<int>(
    'seen_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _agentReadAtMeta = const VerificationMeta(
    'agentReadAt',
  );
  @override
  late final GeneratedColumn<int> agentReadAt = GeneratedColumn<int>(
    'agent_read_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    messageId,
    recipientDeviceId,
    envelopeJson,
    status,
    attempts,
    nextAttemptAt,
    createdAt,
    lastError,
    deliveredAt,
    seenAt,
    agentReadAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'deliveries';
  @override
  VerificationContext validateIntegrity(
    Insertable<Delivery> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('recipient_device_id')) {
      context.handle(
        _recipientDeviceIdMeta,
        recipientDeviceId.isAcceptableOrUnknown(
          data['recipient_device_id']!,
          _recipientDeviceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recipientDeviceIdMeta);
    }
    if (data.containsKey('envelope_json')) {
      context.handle(
        _envelopeJsonMeta,
        envelopeJson.isAcceptableOrUnknown(
          data['envelope_json']!,
          _envelopeJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_envelopeJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextAttemptAtMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('delivered_at')) {
      context.handle(
        _deliveredAtMeta,
        deliveredAt.isAcceptableOrUnknown(
          data['delivered_at']!,
          _deliveredAtMeta,
        ),
      );
    }
    if (data.containsKey('seen_at')) {
      context.handle(
        _seenAtMeta,
        seenAt.isAcceptableOrUnknown(data['seen_at']!, _seenAtMeta),
      );
    }
    if (data.containsKey('agent_read_at')) {
      context.handle(
        _agentReadAtMeta,
        agentReadAt.isAcceptableOrUnknown(
          data['agent_read_at']!,
          _agentReadAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {messageId, recipientDeviceId};
  @override
  Delivery map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Delivery(
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      recipientDeviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recipient_device_id'],
      )!,
      envelopeJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}next_attempt_at'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      deliveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}delivered_at'],
      ),
      seenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seen_at'],
      ),
      agentReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}agent_read_at'],
      ),
    );
  }

  @override
  $DeliveriesTable createAlias(String alias) {
    return $DeliveriesTable(attachedDatabase, alias);
  }
}

class Delivery extends DataClass implements Insertable<Delivery> {
  final String messageId;
  final String recipientDeviceId;
  final String envelopeJson;
  final String status;
  final int attempts;
  final int nextAttemptAt;
  final int createdAt;
  final String? lastError;

  /// Sender side: when the recipient's Mac took it, and the receipts it sent.
  final int? deliveredAt;
  final int? seenAt;
  final int? agentReadAt;
  const Delivery({
    required this.messageId,
    required this.recipientDeviceId,
    required this.envelopeJson,
    required this.status,
    required this.attempts,
    required this.nextAttemptAt,
    required this.createdAt,
    this.lastError,
    this.deliveredAt,
    this.seenAt,
    this.agentReadAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['message_id'] = Variable<String>(messageId);
    map['recipient_device_id'] = Variable<String>(recipientDeviceId);
    map['envelope_json'] = Variable<String>(envelopeJson);
    map['status'] = Variable<String>(status);
    map['attempts'] = Variable<int>(attempts);
    map['next_attempt_at'] = Variable<int>(nextAttemptAt);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || deliveredAt != null) {
      map['delivered_at'] = Variable<int>(deliveredAt);
    }
    if (!nullToAbsent || seenAt != null) {
      map['seen_at'] = Variable<int>(seenAt);
    }
    if (!nullToAbsent || agentReadAt != null) {
      map['agent_read_at'] = Variable<int>(agentReadAt);
    }
    return map;
  }

  DeliveriesCompanion toCompanion(bool nullToAbsent) {
    return DeliveriesCompanion(
      messageId: Value(messageId),
      recipientDeviceId: Value(recipientDeviceId),
      envelopeJson: Value(envelopeJson),
      status: Value(status),
      attempts: Value(attempts),
      nextAttemptAt: Value(nextAttemptAt),
      createdAt: Value(createdAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      deliveredAt: deliveredAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deliveredAt),
      seenAt: seenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(seenAt),
      agentReadAt: agentReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(agentReadAt),
    );
  }

  factory Delivery.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Delivery(
      messageId: serializer.fromJson<String>(json['messageId']),
      recipientDeviceId: serializer.fromJson<String>(json['recipientDeviceId']),
      envelopeJson: serializer.fromJson<String>(json['envelopeJson']),
      status: serializer.fromJson<String>(json['status']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<int>(json['nextAttemptAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      deliveredAt: serializer.fromJson<int?>(json['deliveredAt']),
      seenAt: serializer.fromJson<int?>(json['seenAt']),
      agentReadAt: serializer.fromJson<int?>(json['agentReadAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'messageId': serializer.toJson<String>(messageId),
      'recipientDeviceId': serializer.toJson<String>(recipientDeviceId),
      'envelopeJson': serializer.toJson<String>(envelopeJson),
      'status': serializer.toJson<String>(status),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<int>(nextAttemptAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastError': serializer.toJson<String?>(lastError),
      'deliveredAt': serializer.toJson<int?>(deliveredAt),
      'seenAt': serializer.toJson<int?>(seenAt),
      'agentReadAt': serializer.toJson<int?>(agentReadAt),
    };
  }

  Delivery copyWith({
    String? messageId,
    String? recipientDeviceId,
    String? envelopeJson,
    String? status,
    int? attempts,
    int? nextAttemptAt,
    int? createdAt,
    Value<String?> lastError = const Value.absent(),
    Value<int?> deliveredAt = const Value.absent(),
    Value<int?> seenAt = const Value.absent(),
    Value<int?> agentReadAt = const Value.absent(),
  }) => Delivery(
    messageId: messageId ?? this.messageId,
    recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
    envelopeJson: envelopeJson ?? this.envelopeJson,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    createdAt: createdAt ?? this.createdAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    deliveredAt: deliveredAt.present ? deliveredAt.value : this.deliveredAt,
    seenAt: seenAt.present ? seenAt.value : this.seenAt,
    agentReadAt: agentReadAt.present ? agentReadAt.value : this.agentReadAt,
  );
  Delivery copyWithCompanion(DeliveriesCompanion data) {
    return Delivery(
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      recipientDeviceId: data.recipientDeviceId.present
          ? data.recipientDeviceId.value
          : this.recipientDeviceId,
      envelopeJson: data.envelopeJson.present
          ? data.envelopeJson.value
          : this.envelopeJson,
      status: data.status.present ? data.status.value : this.status,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      deliveredAt: data.deliveredAt.present
          ? data.deliveredAt.value
          : this.deliveredAt,
      seenAt: data.seenAt.present ? data.seenAt.value : this.seenAt,
      agentReadAt: data.agentReadAt.present
          ? data.agentReadAt.value
          : this.agentReadAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Delivery(')
          ..write('messageId: $messageId, ')
          ..write('recipientDeviceId: $recipientDeviceId, ')
          ..write('envelopeJson: $envelopeJson, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastError: $lastError, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('seenAt: $seenAt, ')
          ..write('agentReadAt: $agentReadAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    messageId,
    recipientDeviceId,
    envelopeJson,
    status,
    attempts,
    nextAttemptAt,
    createdAt,
    lastError,
    deliveredAt,
    seenAt,
    agentReadAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Delivery &&
          other.messageId == this.messageId &&
          other.recipientDeviceId == this.recipientDeviceId &&
          other.envelopeJson == this.envelopeJson &&
          other.status == this.status &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.createdAt == this.createdAt &&
          other.lastError == this.lastError &&
          other.deliveredAt == this.deliveredAt &&
          other.seenAt == this.seenAt &&
          other.agentReadAt == this.agentReadAt);
}

class DeliveriesCompanion extends UpdateCompanion<Delivery> {
  final Value<String> messageId;
  final Value<String> recipientDeviceId;
  final Value<String> envelopeJson;
  final Value<String> status;
  final Value<int> attempts;
  final Value<int> nextAttemptAt;
  final Value<int> createdAt;
  final Value<String?> lastError;
  final Value<int?> deliveredAt;
  final Value<int?> seenAt;
  final Value<int?> agentReadAt;
  final Value<int> rowid;
  const DeliveriesCompanion({
    this.messageId = const Value.absent(),
    this.recipientDeviceId = const Value.absent(),
    this.envelopeJson = const Value.absent(),
    this.status = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.seenAt = const Value.absent(),
    this.agentReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeliveriesCompanion.insert({
    required String messageId,
    required String recipientDeviceId,
    required String envelopeJson,
    required String status,
    this.attempts = const Value.absent(),
    required int nextAttemptAt,
    required int createdAt,
    this.lastError = const Value.absent(),
    this.deliveredAt = const Value.absent(),
    this.seenAt = const Value.absent(),
    this.agentReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : messageId = Value(messageId),
       recipientDeviceId = Value(recipientDeviceId),
       envelopeJson = Value(envelopeJson),
       status = Value(status),
       nextAttemptAt = Value(nextAttemptAt),
       createdAt = Value(createdAt);
  static Insertable<Delivery> custom({
    Expression<String>? messageId,
    Expression<String>? recipientDeviceId,
    Expression<String>? envelopeJson,
    Expression<String>? status,
    Expression<int>? attempts,
    Expression<int>? nextAttemptAt,
    Expression<int>? createdAt,
    Expression<String>? lastError,
    Expression<int>? deliveredAt,
    Expression<int>? seenAt,
    Expression<int>? agentReadAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (messageId != null) 'message_id': messageId,
      if (recipientDeviceId != null) 'recipient_device_id': recipientDeviceId,
      if (envelopeJson != null) 'envelope_json': envelopeJson,
      if (status != null) 'status': status,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (createdAt != null) 'created_at': createdAt,
      if (lastError != null) 'last_error': lastError,
      if (deliveredAt != null) 'delivered_at': deliveredAt,
      if (seenAt != null) 'seen_at': seenAt,
      if (agentReadAt != null) 'agent_read_at': agentReadAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeliveriesCompanion copyWith({
    Value<String>? messageId,
    Value<String>? recipientDeviceId,
    Value<String>? envelopeJson,
    Value<String>? status,
    Value<int>? attempts,
    Value<int>? nextAttemptAt,
    Value<int>? createdAt,
    Value<String?>? lastError,
    Value<int?>? deliveredAt,
    Value<int?>? seenAt,
    Value<int?>? agentReadAt,
    Value<int>? rowid,
  }) {
    return DeliveriesCompanion(
      messageId: messageId ?? this.messageId,
      recipientDeviceId: recipientDeviceId ?? this.recipientDeviceId,
      envelopeJson: envelopeJson ?? this.envelopeJson,
      status: status ?? this.status,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      createdAt: createdAt ?? this.createdAt,
      lastError: lastError ?? this.lastError,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      seenAt: seenAt ?? this.seenAt,
      agentReadAt: agentReadAt ?? this.agentReadAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (recipientDeviceId.present) {
      map['recipient_device_id'] = Variable<String>(recipientDeviceId.value);
    }
    if (envelopeJson.present) {
      map['envelope_json'] = Variable<String>(envelopeJson.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<int>(nextAttemptAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (deliveredAt.present) {
      map['delivered_at'] = Variable<int>(deliveredAt.value);
    }
    if (seenAt.present) {
      map['seen_at'] = Variable<int>(seenAt.value);
    }
    if (agentReadAt.present) {
      map['agent_read_at'] = Variable<int>(agentReadAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeliveriesCompanion(')
          ..write('messageId: $messageId, ')
          ..write('recipientDeviceId: $recipientDeviceId, ')
          ..write('envelopeJson: $envelopeJson, ')
          ..write('status: $status, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastError: $lastError, ')
          ..write('deliveredAt: $deliveredAt, ')
          ..write('seenAt: $seenAt, ')
          ..write('agentReadAt: $agentReadAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$RelayDatabase extends GeneratedDatabase {
  _$RelayDatabase(QueryExecutor e) : super(e);
  $RelayDatabaseManager get managers => $RelayDatabaseManager(this);
  late final $PeersTable peers = $PeersTable(this);
  late final $ChannelsTable channels = $ChannelsTable(this);
  late final $ChannelMembersTable channelMembers = $ChannelMembersTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $DeliveriesTable deliveries = $DeliveriesTable(this);
  late final Index messagesChannelHlc = Index(
    'messages_channel_hlc',
    'CREATE INDEX messages_channel_hlc ON messages (channel_id, hlc)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    peers,
    channels,
    channelMembers,
    messages,
    deliveries,
    messagesChannelHlc,
  ];
}

typedef $$PeersTableCreateCompanionBuilder = PeersCompanion Function({
  required String deviceId,
  required String personName,
  required String deviceName,
  required Uint8List signPub,
  required Uint8List boxPub,
  required String certFingerprint,
  required String trust,
  Value<String?> lastAddress,
  Value<int?> lastPort,
  Value<int?> lastSeenAt,
  Value<int?> clockSkewMs,
  required int pairedAt,
  Value<int> rowid,
});
typedef $$PeersTableUpdateCompanionBuilder = PeersCompanion Function({
  Value<String> deviceId,
  Value<String> personName,
  Value<String> deviceName,
  Value<Uint8List> signPub,
  Value<Uint8List> boxPub,
  Value<String> certFingerprint,
  Value<String> trust,
  Value<String?> lastAddress,
  Value<int?> lastPort,
  Value<int?> lastSeenAt,
  Value<int?> clockSkewMs,
  Value<int> pairedAt,
  Value<int> rowid,
});

class $$PeersTableFilterComposer
    extends Composer<_$RelayDatabase, $PeersTable> {
  $$PeersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get signPub => $composableBuilder(
    column: $table.signPub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get boxPub => $composableBuilder(
    column: $table.boxPub,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get certFingerprint => $composableBuilder(
    column: $table.certFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get trust => $composableBuilder(
    column: $table.trust,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastAddress => $composableBuilder(
    column: $table.lastAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPort => $composableBuilder(
    column: $table.lastPort,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get clockSkewMs => $composableBuilder(
    column: $table.clockSkewMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeersTableOrderingComposer
    extends Composer<_$RelayDatabase, $PeersTable> {
  $$PeersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get signPub => $composableBuilder(
    column: $table.signPub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get boxPub => $composableBuilder(
    column: $table.boxPub,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get certFingerprint => $composableBuilder(
    column: $table.certFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get trust => $composableBuilder(
    column: $table.trust,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastAddress => $composableBuilder(
    column: $table.lastAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPort => $composableBuilder(
    column: $table.lastPort,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get clockSkewMs => $composableBuilder(
    column: $table.clockSkewMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeersTableAnnotationComposer
    extends Composer<_$RelayDatabase, $PeersTable> {
  $$PeersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get signPub =>
      $composableBuilder(column: $table.signPub, builder: (column) => column);

  GeneratedColumn<Uint8List> get boxPub =>
      $composableBuilder(column: $table.boxPub, builder: (column) => column);

  GeneratedColumn<String> get certFingerprint => $composableBuilder(
    column: $table.certFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get trust =>
      $composableBuilder(column: $table.trust, builder: (column) => column);

  GeneratedColumn<String> get lastAddress => $composableBuilder(
    column: $table.lastAddress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastPort =>
      $composableBuilder(column: $table.lastPort, builder: (column) => column);

  GeneratedColumn<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get clockSkewMs => $composableBuilder(
    column: $table.clockSkewMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);
}

class $$PeersTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $PeersTable,
          Peer,
          $$PeersTableFilterComposer,
          $$PeersTableOrderingComposer,
          $$PeersTableAnnotationComposer,
          $$PeersTableCreateCompanionBuilder,
          $$PeersTableUpdateCompanionBuilder,
          (Peer, BaseReferences<_$RelayDatabase, $PeersTable, Peer>),
          Peer,
          PrefetchHooks Function()
        > {
  $$PeersTableTableManager(_$RelayDatabase db, $PeersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String> personName = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<Uint8List> signPub = const Value.absent(),
                Value<Uint8List> boxPub = const Value.absent(),
                Value<String> certFingerprint = const Value.absent(),
                Value<String> trust = const Value.absent(),
                Value<String?> lastAddress = const Value.absent(),
                Value<int?> lastPort = const Value.absent(),
                Value<int?> lastSeenAt = const Value.absent(),
                Value<int?> clockSkewMs = const Value.absent(),
                Value<int> pairedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeersCompanion(
                deviceId: deviceId,
                personName: personName,
                deviceName: deviceName,
                signPub: signPub,
                boxPub: boxPub,
                certFingerprint: certFingerprint,
                trust: trust,
                lastAddress: lastAddress,
                lastPort: lastPort,
                lastSeenAt: lastSeenAt,
                clockSkewMs: clockSkewMs,
                pairedAt: pairedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String personName,
                required String deviceName,
                required Uint8List signPub,
                required Uint8List boxPub,
                required String certFingerprint,
                required String trust,
                Value<String?> lastAddress = const Value.absent(),
                Value<int?> lastPort = const Value.absent(),
                Value<int?> lastSeenAt = const Value.absent(),
                Value<int?> clockSkewMs = const Value.absent(),
                required int pairedAt,
                Value<int> rowid = const Value.absent(),
              }) => PeersCompanion.insert(
                deviceId: deviceId,
                personName: personName,
                deviceName: deviceName,
                signPub: signPub,
                boxPub: boxPub,
                certFingerprint: certFingerprint,
                trust: trust,
                lastAddress: lastAddress,
                lastPort: lastPort,
                lastSeenAt: lastSeenAt,
                clockSkewMs: clockSkewMs,
                pairedAt: pairedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeersTable, Peer>(table),
                  BaseReferences<_$RelayDatabase, $PeersTable, Peer>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeersTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $PeersTable,
      Peer,
      $$PeersTableFilterComposer,
      $$PeersTableOrderingComposer,
      $$PeersTableAnnotationComposer,
      $$PeersTableCreateCompanionBuilder,
      $$PeersTableUpdateCompanionBuilder,
      (Peer, BaseReferences<_$RelayDatabase, $PeersTable, Peer>),
      Peer,
      PrefetchHooks Function()
    >;
typedef $$ChannelsTableCreateCompanionBuilder = ChannelsCompanion Function({
  required String id,
  required String kind,
  Value<String?> name,
  required int createdAt,
  Value<int?> closedAt,
  Value<String?> creatorDeviceId,
  Value<int> rowid,
});
typedef $$ChannelsTableUpdateCompanionBuilder = ChannelsCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<String?> name,
  Value<int> createdAt,
  Value<int?> closedAt,
  Value<String?> creatorDeviceId,
  Value<int> rowid,
});

class $$ChannelsTableFilterComposer
    extends Composer<_$RelayDatabase, $ChannelsTable> {
  $$ChannelsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creatorDeviceId => $composableBuilder(
    column: $table.creatorDeviceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChannelsTableOrderingComposer
    extends Composer<_$RelayDatabase, $ChannelsTable> {
  $$ChannelsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get closedAt => $composableBuilder(
    column: $table.closedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creatorDeviceId => $composableBuilder(
    column: $table.creatorDeviceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChannelsTableAnnotationComposer
    extends Composer<_$RelayDatabase, $ChannelsTable> {
  $$ChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get closedAt =>
      $composableBuilder(column: $table.closedAt, builder: (column) => column);

  GeneratedColumn<String> get creatorDeviceId => $composableBuilder(
    column: $table.creatorDeviceId,
    builder: (column) => column,
  );
}

class $$ChannelsTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $ChannelsTable,
          Channel,
          $$ChannelsTableFilterComposer,
          $$ChannelsTableOrderingComposer,
          $$ChannelsTableAnnotationComposer,
          $$ChannelsTableCreateCompanionBuilder,
          $$ChannelsTableUpdateCompanionBuilder,
          (Channel, BaseReferences<_$RelayDatabase, $ChannelsTable, Channel>),
          Channel,
          PrefetchHooks Function()
        > {
  $$ChannelsTableTableManager(_$RelayDatabase db, $ChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> closedAt = const Value.absent(),
                Value<String?> creatorDeviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion(
                id: id,
                kind: kind,
                name: name,
                createdAt: createdAt,
                closedAt: closedAt,
                creatorDeviceId: creatorDeviceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                Value<String?> name = const Value.absent(),
                required int createdAt,
                Value<int?> closedAt = const Value.absent(),
                Value<String?> creatorDeviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelsCompanion.insert(
                id: id,
                kind: kind,
                name: name,
                createdAt: createdAt,
                closedAt: closedAt,
                creatorDeviceId: creatorDeviceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChannelsTable, Channel>(table),
                  BaseReferences<_$RelayDatabase, $ChannelsTable, Channel>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $ChannelsTable,
      Channel,
      $$ChannelsTableFilterComposer,
      $$ChannelsTableOrderingComposer,
      $$ChannelsTableAnnotationComposer,
      $$ChannelsTableCreateCompanionBuilder,
      $$ChannelsTableUpdateCompanionBuilder,
      (Channel, BaseReferences<_$RelayDatabase, $ChannelsTable, Channel>),
      Channel,
      PrefetchHooks Function()
    >;
typedef $$ChannelMembersTableCreateCompanionBuilder =
    ChannelMembersCompanion Function({
      required String channelId,
      required String deviceId,
      required String joinedHlc,
      Value<String?> leftHlc,
      Value<String> state,
      Value<String?> inviterDeviceId,
      Value<String?> myApproval,
      Value<String?> theirApproval,
      Value<String?> personName,
      Value<String?> deviceName,
      Value<int> rowid,
    });
typedef $$ChannelMembersTableUpdateCompanionBuilder =
    ChannelMembersCompanion Function({
      Value<String> channelId,
      Value<String> deviceId,
      Value<String> joinedHlc,
      Value<String?> leftHlc,
      Value<String> state,
      Value<String?> inviterDeviceId,
      Value<String?> myApproval,
      Value<String?> theirApproval,
      Value<String?> personName,
      Value<String?> deviceName,
      Value<int> rowid,
    });

class $$ChannelMembersTableFilterComposer
    extends Composer<_$RelayDatabase, $ChannelMembersTable> {
  $$ChannelMembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get joinedHlc => $composableBuilder(
    column: $table.joinedHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get leftHlc => $composableBuilder(
    column: $table.leftHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inviterDeviceId => $composableBuilder(
    column: $table.inviterDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get myApproval => $composableBuilder(
    column: $table.myApproval,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get theirApproval => $composableBuilder(
    column: $table.theirApproval,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChannelMembersTableOrderingComposer
    extends Composer<_$RelayDatabase, $ChannelMembersTable> {
  $$ChannelMembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get joinedHlc => $composableBuilder(
    column: $table.joinedHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get leftHlc => $composableBuilder(
    column: $table.leftHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inviterDeviceId => $composableBuilder(
    column: $table.inviterDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get myApproval => $composableBuilder(
    column: $table.myApproval,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get theirApproval => $composableBuilder(
    column: $table.theirApproval,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChannelMembersTableAnnotationComposer
    extends Composer<_$RelayDatabase, $ChannelMembersTable> {
  $$ChannelMembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get channelId =>
      $composableBuilder(column: $table.channelId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get joinedHlc =>
      $composableBuilder(column: $table.joinedHlc, builder: (column) => column);

  GeneratedColumn<String> get leftHlc =>
      $composableBuilder(column: $table.leftHlc, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get inviterDeviceId => $composableBuilder(
    column: $table.inviterDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get myApproval => $composableBuilder(
    column: $table.myApproval,
    builder: (column) => column,
  );

  GeneratedColumn<String> get theirApproval => $composableBuilder(
    column: $table.theirApproval,
    builder: (column) => column,
  );

  GeneratedColumn<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );
}

class $$ChannelMembersTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $ChannelMembersTable,
          ChannelMember,
          $$ChannelMembersTableFilterComposer,
          $$ChannelMembersTableOrderingComposer,
          $$ChannelMembersTableAnnotationComposer,
          $$ChannelMembersTableCreateCompanionBuilder,
          $$ChannelMembersTableUpdateCompanionBuilder,
          (
            ChannelMember,
            BaseReferences<
              _$RelayDatabase,
              $ChannelMembersTable,
              ChannelMember
            >,
          ),
          ChannelMember,
          PrefetchHooks Function()
        > {
  $$ChannelMembersTableTableManager(
    _$RelayDatabase db,
    $ChannelMembersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChannelMembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChannelMembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChannelMembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> channelId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> joinedHlc = const Value.absent(),
                Value<String?> leftHlc = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> inviterDeviceId = const Value.absent(),
                Value<String?> myApproval = const Value.absent(),
                Value<String?> theirApproval = const Value.absent(),
                Value<String?> personName = const Value.absent(),
                Value<String?> deviceName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelMembersCompanion(
                channelId: channelId,
                deviceId: deviceId,
                joinedHlc: joinedHlc,
                leftHlc: leftHlc,
                state: state,
                inviterDeviceId: inviterDeviceId,
                myApproval: myApproval,
                theirApproval: theirApproval,
                personName: personName,
                deviceName: deviceName,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String channelId,
                required String deviceId,
                required String joinedHlc,
                Value<String?> leftHlc = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> inviterDeviceId = const Value.absent(),
                Value<String?> myApproval = const Value.absent(),
                Value<String?> theirApproval = const Value.absent(),
                Value<String?> personName = const Value.absent(),
                Value<String?> deviceName = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChannelMembersCompanion.insert(
                channelId: channelId,
                deviceId: deviceId,
                joinedHlc: joinedHlc,
                leftHlc: leftHlc,
                state: state,
                inviterDeviceId: inviterDeviceId,
                myApproval: myApproval,
                theirApproval: theirApproval,
                personName: personName,
                deviceName: deviceName,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ChannelMembersTable, ChannelMember>(table),
                  BaseReferences<
                    _$RelayDatabase,
                    $ChannelMembersTable,
                    ChannelMember
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChannelMembersTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $ChannelMembersTable,
      ChannelMember,
      $$ChannelMembersTableFilterComposer,
      $$ChannelMembersTableOrderingComposer,
      $$ChannelMembersTableAnnotationComposer,
      $$ChannelMembersTableCreateCompanionBuilder,
      $$ChannelMembersTableUpdateCompanionBuilder,
      (
        ChannelMember,
        BaseReferences<_$RelayDatabase, $ChannelMembersTable, ChannelMember>,
      ),
      ChannelMember,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String channelId,
  required String kind,
  required String fromDeviceId,
  required int sentAt,
  Value<String?> hlc,
  Value<int?> seq,
  Value<String?> body,
  Value<String?> contextJson,
  Value<String?> replyTo,
  required String direction,
  required String status,
  Value<bool> arrivedLate,
  required int createdAt,
  Value<int?> receivedAt,
  Value<int?> seenAt,
  Value<int?> agentReadAt,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> channelId,
  Value<String> kind,
  Value<String> fromDeviceId,
  Value<int> sentAt,
  Value<String?> hlc,
  Value<int?> seq,
  Value<String?> body,
  Value<String?> contextJson,
  Value<String?> replyTo,
  Value<String> direction,
  Value<String> status,
  Value<bool> arrivedLate,
  Value<int> createdAt,
  Value<int?> receivedAt,
  Value<int?> seenAt,
  Value<int?> agentReadAt,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer
    extends Composer<_$RelayDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromDeviceId => $composableBuilder(
    column: $table.fromDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contextJson => $composableBuilder(
    column: $table.contextJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get replyTo => $composableBuilder(
    column: $table.replyTo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get arrivedLate => $composableBuilder(
    column: $table.arrivedLate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get agentReadAt => $composableBuilder(
    column: $table.agentReadAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$RelayDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channelId => $composableBuilder(
    column: $table.channelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromDeviceId => $composableBuilder(
    column: $table.fromDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contextJson => $composableBuilder(
    column: $table.contextJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get replyTo => $composableBuilder(
    column: $table.replyTo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get arrivedLate => $composableBuilder(
    column: $table.arrivedLate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get agentReadAt => $composableBuilder(
    column: $table.agentReadAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$RelayDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get channelId =>
      $composableBuilder(column: $table.channelId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get fromDeviceId => $composableBuilder(
    column: $table.fromDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get contextJson => $composableBuilder(
    column: $table.contextJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get replyTo =>
      $composableBuilder(column: $table.replyTo, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get arrivedLate => $composableBuilder(
    column: $table.arrivedLate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seenAt =>
      $composableBuilder(column: $table.seenAt, builder: (column) => column);

  GeneratedColumn<int> get agentReadAt => $composableBuilder(
    column: $table.agentReadAt,
    builder: (column) => column,
  );
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, BaseReferences<_$RelayDatabase, $MessagesTable, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$RelayDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> channelId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> fromDeviceId = const Value.absent(),
                Value<int> sentAt = const Value.absent(),
                Value<String?> hlc = const Value.absent(),
                Value<int?> seq = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<String?> contextJson = const Value.absent(),
                Value<String?> replyTo = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> arrivedLate = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> receivedAt = const Value.absent(),
                Value<int?> seenAt = const Value.absent(),
                Value<int?> agentReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                channelId: channelId,
                kind: kind,
                fromDeviceId: fromDeviceId,
                sentAt: sentAt,
                hlc: hlc,
                seq: seq,
                body: body,
                contextJson: contextJson,
                replyTo: replyTo,
                direction: direction,
                status: status,
                arrivedLate: arrivedLate,
                createdAt: createdAt,
                receivedAt: receivedAt,
                seenAt: seenAt,
                agentReadAt: agentReadAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String channelId,
                required String kind,
                required String fromDeviceId,
                required int sentAt,
                Value<String?> hlc = const Value.absent(),
                Value<int?> seq = const Value.absent(),
                Value<String?> body = const Value.absent(),
                Value<String?> contextJson = const Value.absent(),
                Value<String?> replyTo = const Value.absent(),
                required String direction,
                required String status,
                Value<bool> arrivedLate = const Value.absent(),
                required int createdAt,
                Value<int?> receivedAt = const Value.absent(),
                Value<int?> seenAt = const Value.absent(),
                Value<int?> agentReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                channelId: channelId,
                kind: kind,
                fromDeviceId: fromDeviceId,
                sentAt: sentAt,
                hlc: hlc,
                seq: seq,
                body: body,
                contextJson: contextJson,
                replyTo: replyTo,
                direction: direction,
                status: status,
                arrivedLate: arrivedLate,
                createdAt: createdAt,
                receivedAt: receivedAt,
                seenAt: seenAt,
                agentReadAt: agentReadAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, Message>(table),
                  BaseReferences<_$RelayDatabase, $MessagesTable, Message>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, BaseReferences<_$RelayDatabase, $MessagesTable, Message>),
      Message,
      PrefetchHooks Function()
    >;
typedef $$DeliveriesTableCreateCompanionBuilder = DeliveriesCompanion Function({
  required String messageId,
  required String recipientDeviceId,
  required String envelopeJson,
  required String status,
  Value<int> attempts,
  required int nextAttemptAt,
  required int createdAt,
  Value<String?> lastError,
  Value<int?> deliveredAt,
  Value<int?> seenAt,
  Value<int?> agentReadAt,
  Value<int> rowid,
});
typedef $$DeliveriesTableUpdateCompanionBuilder = DeliveriesCompanion Function({
  Value<String> messageId,
  Value<String> recipientDeviceId,
  Value<String> envelopeJson,
  Value<String> status,
  Value<int> attempts,
  Value<int> nextAttemptAt,
  Value<int> createdAt,
  Value<String?> lastError,
  Value<int?> deliveredAt,
  Value<int?> seenAt,
  Value<int?> agentReadAt,
  Value<int> rowid,
});

class $$DeliveriesTableFilterComposer
    extends Composer<_$RelayDatabase, $DeliveriesTable> {
  $$DeliveriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get envelopeJson => $composableBuilder(
    column: $table.envelopeJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get agentReadAt => $composableBuilder(
    column: $table.agentReadAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DeliveriesTableOrderingComposer
    extends Composer<_$RelayDatabase, $DeliveriesTable> {
  $$DeliveriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get envelopeJson => $composableBuilder(
    column: $table.envelopeJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get agentReadAt => $composableBuilder(
    column: $table.agentReadAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DeliveriesTableAnnotationComposer
    extends Composer<_$RelayDatabase, $DeliveriesTable> {
  $$DeliveriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get recipientDeviceId => $composableBuilder(
    column: $table.recipientDeviceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get envelopeJson => $composableBuilder(
    column: $table.envelopeJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<int> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<int> get deliveredAt => $composableBuilder(
    column: $table.deliveredAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seenAt =>
      $composableBuilder(column: $table.seenAt, builder: (column) => column);

  GeneratedColumn<int> get agentReadAt => $composableBuilder(
    column: $table.agentReadAt,
    builder: (column) => column,
  );
}

class $$DeliveriesTableTableManager
    extends
        RootTableManager<
          _$RelayDatabase,
          $DeliveriesTable,
          Delivery,
          $$DeliveriesTableFilterComposer,
          $$DeliveriesTableOrderingComposer,
          $$DeliveriesTableAnnotationComposer,
          $$DeliveriesTableCreateCompanionBuilder,
          $$DeliveriesTableUpdateCompanionBuilder,
          (
            Delivery,
            BaseReferences<_$RelayDatabase, $DeliveriesTable, Delivery>,
          ),
          Delivery,
          PrefetchHooks Function()
        > {
  $$DeliveriesTableTableManager(_$RelayDatabase db, $DeliveriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeliveriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeliveriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeliveriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> messageId = const Value.absent(),
                Value<String> recipientDeviceId = const Value.absent(),
                Value<String> envelopeJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<int> nextAttemptAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int?> deliveredAt = const Value.absent(),
                Value<int?> seenAt = const Value.absent(),
                Value<int?> agentReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeliveriesCompanion(
                messageId: messageId,
                recipientDeviceId: recipientDeviceId,
                envelopeJson: envelopeJson,
                status: status,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                createdAt: createdAt,
                lastError: lastError,
                deliveredAt: deliveredAt,
                seenAt: seenAt,
                agentReadAt: agentReadAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String messageId,
                required String recipientDeviceId,
                required String envelopeJson,
                required String status,
                Value<int> attempts = const Value.absent(),
                required int nextAttemptAt,
                required int createdAt,
                Value<String?> lastError = const Value.absent(),
                Value<int?> deliveredAt = const Value.absent(),
                Value<int?> seenAt = const Value.absent(),
                Value<int?> agentReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeliveriesCompanion.insert(
                messageId: messageId,
                recipientDeviceId: recipientDeviceId,
                envelopeJson: envelopeJson,
                status: status,
                attempts: attempts,
                nextAttemptAt: nextAttemptAt,
                createdAt: createdAt,
                lastError: lastError,
                deliveredAt: deliveredAt,
                seenAt: seenAt,
                agentReadAt: agentReadAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DeliveriesTable, Delivery>(table),
                  BaseReferences<_$RelayDatabase, $DeliveriesTable, Delivery>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DeliveriesTableProcessedTableManager =
    ProcessedTableManager<
      _$RelayDatabase,
      $DeliveriesTable,
      Delivery,
      $$DeliveriesTableFilterComposer,
      $$DeliveriesTableOrderingComposer,
      $$DeliveriesTableAnnotationComposer,
      $$DeliveriesTableCreateCompanionBuilder,
      $$DeliveriesTableUpdateCompanionBuilder,
      (Delivery, BaseReferences<_$RelayDatabase, $DeliveriesTable, Delivery>),
      Delivery,
      PrefetchHooks Function()
    >;

class $RelayDatabaseManager {
  final _$RelayDatabase _db;
  $RelayDatabaseManager(this._db);
  $$PeersTableTableManager get peers =>
      $$PeersTableTableManager(_db, _db.peers);
  $$ChannelsTableTableManager get channels =>
      $$ChannelsTableTableManager(_db, _db.channels);
  $$ChannelMembersTableTableManager get channelMembers =>
      $$ChannelMembersTableTableManager(_db, _db.channelMembers);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$DeliveriesTableTableManager get deliveries =>
      $$DeliveriesTableTableManager(_db, _db.deliveries);
}
