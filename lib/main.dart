import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_map/flutter_map.dart';

// Define an enum for terrain modes
enum TerrainMode { City, Highway, Other }

const cityCutoffSpeed = 40.0;
const highwayCutoffSpeed = 60.0;
const logBufferLength = 50;
const logBufferDuration = 60;
const turningAngleCutoff = 45;
const cityDistanceInterval = 10;
const cityTimeInterval = 3;
const highwayDistanceInterval = 50;
const highwayTimeInterval = 10;

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
  return change >= turningAngleCutoff;
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
  bool _isLogging = false;
  DateTime _timeStamp = DateTime.now();
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _speed = 0.0;
  double _altitude = 0.0;
  double _heading = 0.0;
  LoggerData? _lastLoggedData;
  TerrainMode _terrainMode = TerrainMode.City;
  String? _currentLogFile;
  final MapController _mapController = MapController();
  final List<File> _pastTrips = [];
  final List<LoggerData> _bufferLog = [];
  late Timer _timer;
  String get _terrainModeString {
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

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      Duration(seconds: 1),
      (Timer t) => _loop(),
    ); // Repeats the animation forward and backward.
    loadPastTrips();
  }

  @override
  void dispose() {
    _flushBufferToFile();
    _timer.cancel();
    super.dispose();
  }

  void loadPastTrips() async {
    setState(() {
      _pastTrips.clear();
    });
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync();
    for (var file in files) {
      if (file is File && file.path.endsWith('.txt')) {
        setState(() {
          _pastTrips.add(file);
        });
      }
    }
  }

  void toggleLogging() async {
    setState(() {
      _isLogging = !_isLogging;
    });
    if (_isLogging) {
      _startNewTrip();
    } else {
      loadPastTrips();
      await _flushBufferToFile();
    }
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

  void _startNewTrip() async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    _currentLogFile = '${directory.path}/$timestamp.txt';
  }

  void logData() {
    if (_currentLogFile == null || !_isLogging) return;
    final loggerData = LoggerData(
      latitude: _latitude,
      longitude: _longitude,
      speed: _speed,
      altitude: _altitude,
      heading: _heading,
      terrainMode: _terrainModeString,
      timestamp: _timeStamp,
    );
    setState(() {
      _lastLoggedData = loggerData;
      _bufferLog.add(loggerData);
    });
    if (_bufferLog.isNotEmpty &&
        (_bufferLog.length > logBufferLength ||
            _bufferLog.first.timestamp.difference(DateTime.now()).inSeconds >
                logBufferDuration)) {
      _flushBufferToFile();
    }
  }

  Future<void> _flushBufferToFile() async {
    if (_bufferLog.isEmpty || _currentLogFile == null) return;
    final file = File(_currentLogFile!);
    var sink = file.openWrite(mode: FileMode.append);
    for (var log in _bufferLog) {
      sink.writeln(log.toString());
    }
    await sink.flush();
    await sink.close();
    setState(() {
      _bufferLog.clear();
    });
  }

  void _loop() async {
    final currentTime = DateTime.now();
    setState(() {
      _timeStamp = currentTime;
    });

    try {
      final locationData = await _getLocation();
      if (locationData != null) {
        if (_latitude == 0 && _longitude == 0) {
          _mapController.move(
            LatLng(locationData.latitude, locationData.longitude),
            18.0,
          );
        }
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
        } else if (speedInKmh <= cityCutoffSpeed) {
          updateTerrainMode(TerrainMode.City);
        } else {
          // Let it be same as previous value
        }
        if (_isLogging) {
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
          final timeInterval =
              currentTime.difference(lastLoggedData.timestamp).inMilliseconds;
          if (_terrainMode == TerrainMode.City) {
            if (distance >= cityDistanceInterval) {
              logData();
              return;
            }
            if (timeInterval >= cityTimeInterval * 1000) {
              logData();
              return;
            }
          } else if (_terrainMode == TerrainMode.Highway) {
            if (distance >= highwayDistanceInterval) {
              logData();
              return;
            }
            if (timeInterval >= highwayTimeInterval) {
              logData();
              return;
            }
          }
        }
      }
    } catch (e) {
      toggleLogging();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: Text('GPX Logger')),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    _latitude != 0 && _longitude != 0
                        ? LatLng(_latitude, _longitude)
                        : LatLng(0.0, 0.0),
                initialZoom: 18.0,
                interactionOptions: InteractionOptions(
                  flags:
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom |
                      InteractiveFlag.doubleTapDragZoom |
                      InteractiveFlag.scrollWheelZoom |
                      InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      // "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                      // "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png",
                      "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png",

                  subdomains: ['a', 'b', 'c'],
                ),
                MarkerLayer(
                  markers:
                      _latitude != 0 && _longitude != 0
                          ? [
                            Marker(
                              width: 24.0,
                              height: 24.0,
                              point: LatLng(_latitude, _longitude),
                              child: Icon(
                                _speed > 1
                                    ? Icons.navigation
                                    : Icons.radio_button_checked,
                                size: 32.0,
                                color: Colors.blueAccent[700],
                              ),
                            ),
                          ]
                          : [],
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 72.0),
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    left: 0,
                    bottom: 0,
                    child: Center(
                      child: ElevatedButton.icon(
                        onPressed: toggleLogging,
                        icon:
                            _isLogging
                                ? Icon(Icons.stop)
                                : Icon(Icons.play_arrow),
                        label: Text(_isLogging ? 'Stop' : 'Start'),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 60,
                    child: IconButton(
                      onPressed:
                          () => _mapController.move(
                            LatLng(_latitude, _longitude),
                            18.0,
                          ),
                      icon: Icon(
                        Icons.my_location,
                        size: 36.0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 120,
                    child: IconButton(
                      onPressed: () => logData(),
                      icon: Icon(
                        Icons.favorite_border,
                        size: 36.0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        _timeString,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.1, // Initial size (from bottom of the screen)
            minChildSize: 0.1, // Minimum size (when fully collapsed)
            maxChildSize: 0.6, // Maximum size (when fully expanded)
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.indigoAccent[100],
                  borderRadius: BorderRadius.all(Radius.circular(16.0)),
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  controller: scrollController,
                  itemCount: _pastTrips.length + 1,
                  itemBuilder: (context, index) {
                    if(index == 0) {
                      return ListTile(
                        title: Text('Past Trips'),
                      );
                    }
                    final file = _pastTrips[index -1];
                    final name = file.path.split('/').last;
                    return ListTile(
                      title: Text(name),
                      trailing: PopupMenuButton(
                        itemBuilder:
                            (context) => [
                              PopupMenuItem(
                                onTap:
                                    () => {
                                      // TODO: Ask for confirmation
                                      file.delete(),
                                      loadPastTrips(),
                                    },
                                child: Text('Delete'),
                              ),
                              PopupMenuItem(
                                onTap:
                                    () => {
                                      // TODO: Implement rename
                                    },
                                child: Text('Rename'),
                              ),
                              PopupMenuItem(
                                onTap:
                                    () => {
                                      // Open share dialog
                                      Share.shareXFiles([
                                        XFile(file.path),
                                      ], text: 'Sharing my text file'),
                                    },
                                child: Text('Export'),
                              ),
                            ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
