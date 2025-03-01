import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:path_provider/path_provider.dart';

// Define an enum for terrain modes
enum TerrainMode { City, Highway, Other }

const cityCutoffSpeded = 40.0;
const highwayCutoffSpeed = 60.0;
const logBufferLength = 50;
const logBufferDuration = 60;

class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);
}

class LoggerData {
  final double latitude;
  final double longitude;
  final double speed;
  final double altitude;
  final double heading;
  final String terrainMode;
  final DateTime timestamp;

  LoggerData({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.altitude,
    required this.heading,
    required this.terrainMode,
    required this.timestamp,
  });

  // Factory constructor to create from a Map
  factory LoggerData.fromMap(Map<String, dynamic> map) {
    return LoggerData(
      latitude: (map['latitude'] ?? 0) as double,
      longitude: (map['longitude'] ?? 0) as double,
      speed: (map['speed'] ?? 0) as double,
      altitude: (map['altitude'] ?? 0) as double,
      heading: (map['heading'] ?? 0) as double,
      terrainMode: (map['terrainMode'] ?? 'City') as String,
      timestamp: (map['timestamp'] ?? DateTime.now()) as DateTime,
    );
  }

  // Method to convert to a Map
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'altitude': altitude,
      'heading': heading,
      'terrainMode': terrainMode,
      'timestamp': timestamp,
    };
  }

  // Override toString for easier debugging
  @override
  String toString() {
    return 'LoggerData{ latitude: $latitude, longitude: $longitude, speed: $speed, altitude: $altitude, heading: $heading, terrainMode: $terrainMode, timestamp: $timestamp }';
  }

  //Override == and hashCode for equality checks.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoggerData &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          speed == other.speed &&
          altitude == other.altitude &&
          heading == other.heading &&
          terrainMode == other.terrainMode &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      latitude.hashCode ^
      longitude.hashCode ^
      speed.hashCode ^
      altitude.hashCode ^
      heading.hashCode ^
      terrainMode.hashCode ^
      timestamp.hashCode;
}

bool isTurnDetected(double previousHeading, double currentHeading) {
  double change = (currentHeading - previousHeading).abs();
  // Handle wraparound cases (0 to 360 degrees)
  if (change > 180) {
    change = 360 - change;
  }
  return change >= 45;
}

double calculateDistanceInMeters(GeoPoint point1, GeoPoint point2) {
  const double earthRadiusMeters = 6371000.0; // Earth's radius in meters

  double toRadians(double degree) => degree * (pi / 180.0);

  double dLat = toRadians(point2.latitude - point1.latitude);
  double dLon = toRadians(point2.longitude - point1.longitude);

  double a =
      pow(sin(dLat / 2), 2) +
      cos(toRadians(point1.latitude)) *
          cos(toRadians(point2.latitude)) *
          pow(sin(dLon / 2), 2);

  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadiusMeters * c; // Distance in meters
}

void main() {
  runApp(GPXLoggerApp());
}

class GPXLoggerApp extends StatelessWidget {
  const GPXLoggerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GPX Logger',
      theme: ThemeData.dark(),
      home: GPXLoggerHome(),
    );
  }
}

class GPXLoggerHome extends StatefulWidget {
  const GPXLoggerHome({super.key});

  @override
  GPXLoggerHomeState createState() => GPXLoggerHomeState();
}

class GPXLoggerHomeState extends State<GPXLoggerHome> {
  bool isLogging = false;
  DateTime _timeStamp = DateTime.now();
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _speed = 0.0;
  double _altitude = 0.0;
  double _heading = 0.0;
  LoggerData? _lastLoggedData;
  TerrainMode _terrainMode = TerrainMode.City;
  final List<LoggerData> _bufferLog = [];
  String get terrainModeString {
    switch (_terrainMode) {
      case TerrainMode.City:
        return 'City';
      case TerrainMode.Highway:
        return 'Highway';
      case TerrainMode.Other:
        return 'Other';
    }
  }
  String get _timeString {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(_timeStamp).toString();
  }
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(Duration(seconds: 1), (Timer t) => _loop());
  }

  @override
  void dispose() {
    _flushBufferToFile();
    _timer.cancel();
    super.dispose();
  }

  void toggleLogging() {
    setState(() {
      isLogging = !isLogging;
    });
  }

  void updateTerrainMode(TerrainMode mode) {
    setState(() {
      _terrainMode = mode;
    });
  }

  Future<Position?> _getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      return position;
    } catch (e) {
      return null;
    }
  }

  void logData() {
    final loggerData = LoggerData(
      latitude: _latitude,
      longitude: _longitude,
      speed: _speed,
      altitude: _altitude,
      heading: _heading,
      terrainMode: terrainModeString,
      timestamp: _timeStamp,
    );
    setState(() {
      _lastLoggedData = loggerData;
      _bufferLog.add(loggerData);
    });
    if(_bufferLog.isNotEmpty && (_bufferLog.length > logBufferLength || _bufferLog.first.timestamp.difference(DateTime.now()).inSeconds > logBufferDuration)) {
      _flushBufferToFile();
    }
  }

  Future<void> _flushBufferToFile() async {
    if (_bufferLog.isEmpty) return;
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/gpx_log.txt');
    await file.writeAsString('${_bufferLog.join('\n')}\n', mode: FileMode.append);
    setState(() {
      _bufferLog.clear();
    });
  }

  void _loop() async {
    final currentTime = DateTime.now();
    setState(() {
      _timeStamp = currentTime;
    });
    if (isLogging) {
      try {
        final locationData = await _getLocation();
        if (locationData != null) {
          setState(() {
            _latitude = locationData.latitude;
            _longitude = locationData.longitude;
            _speed = locationData.speed;
            _altitude = locationData.altitude;
            _heading = locationData.heading;
          });
          final speedInKmh = 3.6 * _speed;
          if (speedInKmh >= highwayCutoffSpeed) {
            updateTerrainMode(TerrainMode.Highway);
          } else if (speedInKmh <= cityCutoffSpeded) {
            updateTerrainMode(TerrainMode.City);
          } else {
            // Let it be same as previous value
          }

          final lastLoggedData = _lastLoggedData;
          if (lastLoggedData == null) {
            logData();
            return;
          }

          bool turnDetected = isTurnDetected(
            lastLoggedData.heading,
            locationData.heading,
          );
          if (turnDetected) {
            logData();
            return;
          }
          final distance = calculateDistanceInMeters(
            GeoPoint(lastLoggedData.latitude, lastLoggedData.longitude),
            GeoPoint(locationData.latitude, locationData.longitude),
          );
          final interval = currentTime.difference(lastLoggedData.timestamp).inMilliseconds;
          if (_terrainMode == TerrainMode.City) {
            if (distance >= 10) {
              logData();
              return;
            }
            if (interval >= 3000) {
              logData();
              return;
            }
          } else if (_terrainMode == TerrainMode.Highway) {
            if (distance >= 50) {
              logData();
              return;
            }
            if (interval >= 10000) {
              logData();
              return;
            }
          }
        }
      } catch (e) {
        toggleLogging();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('GPX Logger')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('Current Time:', style: TextStyle(fontSize: 20)),
            Text(_timeString, style: TextStyle(fontSize: 18)),
            SizedBox(height: 20),
            Text('Latitude: $_latitude', style: TextStyle(fontSize: 18)),
            Text('Longitude: $_longitude', style: TextStyle(fontSize: 18)),
            Text('Speed: $_speed', style: TextStyle(fontSize: 18)),
            Text('Altitude: $_altitude', style: TextStyle(fontSize: 18)),
            Text('Heading: $_heading', style: TextStyle(fontSize: 18)),
            Text(
              'Terrain Mode: $terrainModeString',
              style: TextStyle(fontSize: 18),
            ),
            ElevatedButton(
              onPressed: toggleLogging,
              child: Text(isLogging ? 'Stop Logging' : 'Start Logging'),
            ),
          ],
        ),
      ),
    );
  }
}
