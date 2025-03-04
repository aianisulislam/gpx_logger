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
import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:xml/xml.dart' as xml;

enum TerrainMode { City, Highway, Other }

enum MapMode { Normal, Satellite, Hybrid }

const cityCutoffSpeed = 40.0;
const highwayCutoffSpeed = 60.0;
const logBufferLength = 50;
const logBufferDuration = 60;
const turningAngleCutoff = 45;
const cityDistanceInterval = 10;
const cityTimeInterval = 3;
const highwayDistanceInterval = 50;
const highwayTimeInterval = 10;

class Stats {
  final IconData icon;
  final String label;

  Stats({required this.icon, required this.label});
}

class FloatingActionButtonItem {
  late final IconData icon;
  late final VoidCallback onPressed;

  FloatingActionButtonItem({required this.icon, required this.onPressed});
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

  @override
  String toString() {
    return 'LoggerData{ latitude: $latitude, longitude: $longitude, speed: $speed, altitude: $altitude, heading: $heading, terrainMode: $terrainMode, timestamp: $timestamp }';
  }

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

class LogActionButtonItem {
  final String name;
  final IconData? icon;
  final Function(File file) onPressed;

  LogActionButtonItem({required this.name, this.icon, required this.onPressed});
}

bool isTurnDetected(double previousHeading, double currentHeading) {
  return Geolocator.bearingBetween(
        0,
        previousHeading,
        0,
        currentHeading,
      ).abs() >=
      turningAngleCutoff;
}

double calculateDistanceInMeters(LatLng point1, LatLng point2) {
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

double getFractionalSizeInHeight(BuildContext context, double pixels) {
  return pixels / MediaQuery.of(context).size.height;
}

Future<void> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String content,
  required VoidCallback onConfirm,
  VoidCallback? onCancel,
}) async {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            Text(content, textAlign: TextAlign.center),
            SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (onCancel != null) onCancel();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                onConfirm();
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.primary,
                ),
                foregroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              child: Text('Confirm'),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showInputDialog({
  required BuildContext context,
  required String title,
  required String label,
  required Function(String) onConfirm,
  String initialValue = '',
  VoidCallback? onCancel,
}) async {
  TextEditingController controller = TextEditingController(text: initialValue);

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          top: 32,
          left: 32,
          right: 32,
          bottom:
              MediaQuery.of(context).viewInsets.bottom +
              32, // Handle keyboard overlap
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: InputDecoration(labelText: label),
              autofocus: true,
            ),
            SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (onCancel != null) onCancel();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                onConfirm(controller.text.trim());
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              style: ButtonStyle(
                backgroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.primary,
                ),
                foregroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              child: Text('OK'),
            ),
          ],
        ),
      );
    },
  );
}

Future<File> convertToGpx(File txtFile) async {
  final lines = await txtFile.readAsLines();
  final builder = xml.XmlBuilder();

  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'gpx',
    nest: () {
      builder.attribute('xmlns', 'http://www.topografix.com/GPX/1/1');
      builder.attribute(
        'xmlns:gpxtpx',
        'http://www.garmin.com/xmlschemas/TrackPointExtension/v1',
      );
      builder.element(
        'trk',
        nest: () {
          builder.element(
            'name',
            nest: txtFile.path.split('/').last.replaceAll('.txt', ''),
          );
          builder.element(
            'trkseg',
            nest: () {
              for (var line in lines) {
                final data = line.split(',');
                if (data.length < 7) continue; // Skip invalid lines

                builder.element(
                  'trkpt',
                  attributes: {'lat': data[0], 'lon': data[1]},
                  nest: () {
                    builder.element('ele', nest: data[2]);
                    builder.element(
                      'time',
                      nest: DateTime.parse(data[6]).toUtc().toIso8601String(),
                    );
                    builder.element(
                      'extensions',
                      nest: () {
                        builder.element(
                          'gpxtpx:TrackPointExtension',
                          nest: () {
                            builder.element('gpxtpx:speed', nest: data[3]);
                            builder.element('gpxtpx:course', nest: data[4]);
                            builder.element(
                              'gpxtpx:terrainMode',
                              nest: data[5],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              }
            },
          );
        },
      );
    },
  );

  final directory = await getApplicationDocumentsDirectory();
  final gpxFile = File(
    '${directory.path}/${txtFile.path.split('/').last.replaceAll(".txt", ".gpx")}',
  );
  await gpxFile.writeAsString(
    builder.buildDocument().toXmlString(pretty: true),
  );

  return gpxFile;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final savedThemeMode =
      await AdaptiveTheme.getThemeMode(); // Load stored theme mode

  runApp(GPXLoggerApp(savedThemeMode: savedThemeMode));
}

class GPXLoggerApp extends StatelessWidget {
  final AdaptiveThemeMode? savedThemeMode;

  const GPXLoggerApp({super.key, this.savedThemeMode});

  @override
  Widget build(BuildContext context) {
    return AdaptiveTheme(
      light: ThemeData.light(useMaterial3: true),
      dark: ThemeData.dark(useMaterial3: true),
      initial:
          savedThemeMode ??
          AdaptiveThemeMode.system, // Use stored mode or system default
      builder:
          (theme, darkTheme) => MaterialApp(
            title: 'GPX Logger',
            theme: theme,
            darkTheme: darkTheme,
            home: GPXLoggerHome(),
          ),
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
  bool _isViewing = false;
  DateTime _timeStamp = DateTime.now();
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _speed = 0.0;
  double _altitude = 0.0;
  double _heading = 0.0;
  LoggerData? _lastLoggedData;
  TerrainMode _terrainMode = TerrainMode.City;
  List<File> _pastLogs = [];
  File _selectedLog = File('');
  String? _currentLogFile;
  final _mapMode = MapMode.Normal;
  final MapController _mapController = MapController();
  final List<LoggerData> _bufferLog = [];
  late Timer _timer;
  late bool serviceEnabled;
  late LocationPermission permission;

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
  String _mapURLTemplate(bool isDarkMode) {
    switch (_mapMode) {
      case MapMode.Normal:
        return isDarkMode
            ? "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png"
            : "https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png";
      case MapMode.Satellite:
        return isDarkMode
            ? "https://tiles.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png"
            : "https://tiles.stadiamaps.com/tiles/alidade_smooth/{z}/{x}/{y}{r}.png";
      case MapMode.Hybrid:
        return isDarkMode
            ? "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}"
            : "https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}";
    }
  }

  @override
  void initState() {
    super.initState();
    loadPastLogs();
    initializeLoggingAccess();
    _timer = Timer.periodic(Duration(seconds: 1), (Timer t) => loop());
  }

  @override
  void dispose() {
    flushBufferToFile();
    _timer.cancel();
    super.dispose();
  }

  void initializeLoggingAccess() async {
    bool isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isServiceEnabled) {
      await Geolocator.openLocationSettings();
      isServiceEnabled = await Geolocator.isLocationServiceEnabled();
    }
    LocationPermission locationPermissions = await Geolocator.checkPermission();
    setState(() {
      serviceEnabled = isServiceEnabled;
      permission = locationPermissions;
    });
  }

  void loadPastLogs() async {
    final directory = await getApplicationDocumentsDirectory();
    final files = directory.listSync();
    List<File> pastLogs = [];

    for (var file in files) {
      if (file is File && file.path.endsWith('.txt')) {
        pastLogs.add(file);
      }
    }

    setState(() {
      _pastLogs = pastLogs;
    });
  }

  void toggleLogging() async {
    setState(() {
      _isLogging = !_isLogging;
    });
    if (_isLogging) {
      startNewLog();
    } else {
      loadPastLogs();
      await flushBufferToFile();
    }
  }

  void updateTerrainMode(TerrainMode mode) {
    setState(() {
      _terrainMode = mode;
    });
  }

  void startNewLog() async {
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
    if(_lastLoggedData?.timestamp == loggerData.timestamp){
      return;
    }
    setState(() {
      _lastLoggedData = loggerData;
      _bufferLog.add(loggerData);
    });
    if (_bufferLog.isNotEmpty &&
        (_bufferLog.length > logBufferLength ||
            _bufferLog.first.timestamp.difference(DateTime.now()).inSeconds >
                logBufferDuration)) {
      flushBufferToFile();
    }
  }

  void loop() async {
    if (!serviceEnabled ||
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }
    try {
      final currentTime = DateTime.now();
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
          _timeStamp = currentTime;
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
            LatLng(lastLoggedData.latitude, lastLoggedData.longitude),
            LatLng(locationData.latitude, locationData.longitude),
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

  Future<Position?> _getLocation() async {
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

  Future<void> flushBufferToFile() async {
    if (_bufferLog.isEmpty || _currentLogFile == null) return;
    final file = File(_currentLogFile!);
    var sink = file.openWrite(mode: FileMode.append);
    for (var log in _bufferLog) {
      sink.writeln(
        '${log.latitude},${log.longitude},${log.altitude},${log.speed},${log.heading},${log.terrainMode},${log.timestamp.toIso8601String()}',
      );
    }
    await sink.flush();
    await sink.close();
    setState(() {
      _bufferLog.clear();
    });
  }

  Widget buildBottomSheetTile(
    LogActionButtonItem action,
    File file,
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => action.onPressed(file),
        splashColor: colorScheme.primary.withAlpha(72), // Custom ripple color
        highlightColor: colorScheme.primary.withAlpha(25),
        child: ListTile(
          leading:
              action.icon != null
                  ? Icon(action.icon, color: Theme.of(context).iconTheme.color)
                  : null,
          title: Text(action.name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = AdaptiveTheme.of(context).mode;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bottomSheetBoxDecoration = BoxDecoration(
      color: Color.lerp(colorScheme.surface, colorScheme.onSurface, 0.025),
      borderRadius: BorderRadius.all(Radius.circular(24.0)),
      boxShadow:
          isDarkMode
              ? []
              : [
                BoxShadow(
                  color: colorScheme.onSurface.withAlpha(40),
                  blurRadius: 2.0,
                  spreadRadius: 0.0,
                ),
              ],
    );
    final List<Stats> currentStats = [
      Stats(icon: Icons.speed,label:  '${(_speed * 3.6).toStringAsFixed(2)} kmph'),
      Stats(icon: Icons.terrain_outlined,label:  '${_altitude.toStringAsFixed(2)} meters'),
      Stats(icon: Icons.signpost_outlined,label:  _terrainModeString),
    ];
    final List<FloatingActionButtonItem> floatingButtonItems = [
      FloatingActionButtonItem(
        icon: Icons.my_location,
        onPressed: () {
          if (_latitude != 0 && _longitude != 0) {
            _mapController.move(LatLng(_latitude, _longitude), 18.0);
          }
        },
      ),
      FloatingActionButtonItem(
        icon: Icons.favorite_outline,
        onPressed: () => logData(),
      ),
      FloatingActionButtonItem(
        icon:
            mode == AdaptiveThemeMode.system
                ? Icons.brightness_6_outlined
                : mode == AdaptiveThemeMode.light
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
        onPressed: () => AdaptiveTheme.of(context).toggleThemeMode(),
      ),
    ];
    final List<LogActionButtonItem> logActionButtonItems = [
      LogActionButtonItem(
        name: 'View',
        icon: Icons.remove_red_eye,
        onPressed:
            (File file) => {
              Navigator.of(context).pop(),
              setState(() {
                _selectedLog = file;
                _isViewing = true;
              }),
            },
      ),
      LogActionButtonItem(
        name: 'Delete',
        icon: Icons.delete,
        onPressed:
            (File file) => showConfirmationDialog(
              context: context,
              title: 'Delete Log',
              content: 'Are you sure you want to delete this log?',
              onConfirm: () async {
                file.delete();
                loadPastLogs();
              },
            ),
      ),
      LogActionButtonItem(
        name: 'Rename',
        icon: Icons.edit,
        onPressed:
            (File file) => showInputDialog(
              context: context,
              title: 'Rename Log',
              label: 'Enter new name',
              initialValue: file.path.split('/').last.replaceAll('.txt', ''),
              onConfirm: (String newName) async {
                if (newName.isEmpty) return;
                final directory = file.parent.path;
                final newPath = '$directory/$newName.txt';
                await file.rename(newPath);
                loadPastLogs();
              },
            ),
      ),
      LogActionButtonItem(
        name: 'Share',
        icon: Icons.share,
        onPressed: (File file) async {
          showDialog(
            context: context,
            barrierDismissible: false, // Prevents user from dismissing it
            builder: (context) {
              return Dialog(
                backgroundColor:
                    Colors.transparent, // Removes dialog background
                child: Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Preparing file...',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
          final gpxFile = await convertToGpx(file);
          // ignore: use_build_context_synchronously
          Navigator.of(context).pop();
          await Share.shareXFiles([XFile(gpxFile.path)]);
        },
      ),
    ];
    return Scaffold(
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
                  urlTemplate: _mapURLTemplate(isDarkMode),
                  subdomains: ['a', 'b', 'c'],
                ),
                ...(_isViewing
                    ? [
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points:
                                _selectedLog.readAsLinesSync().map((line) {
                                  final data = line.split(',');
                                  return LatLng(
                                    double.parse(data[0]),
                                    double.parse(data[1]),
                                  );
                                }).toList(),
                            strokeWidth: 4.0,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                      MarkerLayer(
                        markers:
                            _latitude != 0 && _longitude != 0
                                ? [
                                  Marker(
                                    width: 24.0,
                                    height: 24.0,
                                    point:
                                        _selectedLog
                                            .readAsLinesSync()
                                            .map((line) {
                                              final data = line.split(',');
                                              return LatLng(
                                                double.parse(data[0]),
                                                double.parse(data[1]),
                                              );
                                            })
                                            .toList()
                                            .first,
                                    child: Icon(
                                      Icons.circle,
                                      size: 16.0,
                                      color: Colors.green[700],
                                    ),
                                  ),
                                  Marker(
                                    width: 24.0,
                                    height: 24.0,
                                    point:
                                        _selectedLog
                                            .readAsLinesSync()
                                            .map((line) {
                                              final data = line.split(',');
                                              return LatLng(
                                                double.parse(data[0]),
                                                double.parse(data[1]),
                                              );
                                            })
                                            .toList()
                                            .last,
                                    child: Icon(
                                      Icons.stop_rounded,
                                      size: 22.0,
                                      color: Colors.red,
                                    ),
                                  ),
                                ]
                                : [],
                      ),
                    ]
                    : [
                      MarkerLayer(
                        markers:
                            _latitude != 0 && _longitude != 0
                                ? [
                                  Marker(
                                    width: 24.0,
                                    height: 24.0,
                                    point: LatLng(_latitude, _longitude),
                                    child:
                                        _speed > 1
                                            ? Transform.rotate(
                                              angle: _heading * pi / 180,
                                              child: Icon(
                                                Icons.navigation,
                                                size: 32.0,
                                                color: Colors.blueAccent[700],
                                              ),
                                            )
                                            : Icon(
                                              Icons.radio_button_checked,
                                              size: 32.0,
                                              color: Colors.blueAccent[700],
                                            ),
                                  ),
                                ]
                                : [],
                      ),
                    ]),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16.0,
                0,
                16.0,
                _isViewing ? 16.0 : 100.0,
              ),
              child: Stack(
                children:
                    _isViewing
                        ? [
                          Positioned(
                            right: 0,
                            left: 0,
                            bottom: 0,
                            child: Center(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isViewing = false;
                                    _selectedLog = File('');
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 24.0,
                                    vertical: 12.0,
                                  ),
                                ),
                                icon: Icon(Icons.close),
                                label: Text(
                                  'Close Preview',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ]
                        : [
                          Positioned(
                            left: 0,
                            right: 0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: currentStats.map((stat) {
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Icon(
                                        stat.icon,
                                        color: colorScheme.primary,
                                        size: 24.0,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Text(
                                          stat.label,
                                          style: TextStyle(
                                            fontSize: 16.0,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            left: 0,
                            bottom: 0,
                            child: Center(
                              child: ElevatedButton.icon(
                                onPressed: toggleLogging,
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 24.0,
                                    vertical: 12.0,
                                  ),
                                ),
                                icon:
                                    _isLogging
                                        ? Icon(Icons.stop)
                                        : Icon(Icons.play_arrow),
                                label: Text(
                                  _isLogging ? 'Stop' : 'Start',
                                  style: TextStyle(
                                    fontSize: 16.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Column(
                              children:
                                  floatingButtonItems.reversed
                                      .map(
                                        (item) => Padding(
                                          padding: const EdgeInsets.only(
                                            top: 16.0,
                                          ),
                                          child: ElevatedButton.icon(
                                            onPressed: item.onPressed,
                                            icon: Icon(item.icon, size: 24.0),
                                            label: Text(''),
                                            style: ElevatedButton.styleFrom(
                                              padding: EdgeInsets.fromLTRB(
                                                20,
                                                12,
                                                12,
                                                12,
                                              ),
                                              shape: CircleBorder(),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ),
                        ],
              ),
            ),
          ),
          _isViewing
              ? Container()
              : DraggableScrollableSheet(
                initialChildSize: getFractionalSizeInHeight(context, 80),
                minChildSize: getFractionalSizeInHeight(context, 80),
                maxChildSize: getFractionalSizeInHeight(context, 600),
                builder: (
                  BuildContext context,
                  ScrollController scrollController,
                ) {
                  return Container(
                    decoration: bottomSheetBoxDecoration,
                    child: ListView.builder(
                      padding: EdgeInsets.all(4.0),
                      controller: scrollController,
                      itemCount: _pastLogs.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            title: Column(
                              children: [
                                Container(
                                  width: 40,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary.withAlpha(220),
                                    borderRadius: BorderRadius.circular(50),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'Past Logs',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        final file = _pastLogs[index - 1];
                        final name = file.path
                            .split('/')
                            .last
                            .replaceAll('.txt', '');
                        return buildBottomSheetTile(
                          LogActionButtonItem(
                            name: name,
                            onPressed:
                                (file) => {
                                  showModalBottomSheet(
                                    context: context,
                                    builder:
                                        (context) => ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight:
                                                280, // Set max height in pixels
                                          ),
                                          child: Container(
                                            decoration:
                                                bottomSheetBoxDecoration,
                                            child: ListView.builder(
                                              padding: EdgeInsets.all(4.0),
                                              itemCount:
                                                  logActionButtonItems.length,
                                              itemBuilder: (context, index) {
                                                final item =
                                                    logActionButtonItems[index];
                                                return buildBottomSheetTile(
                                                  LogActionButtonItem(
                                                    name: item.name,
                                                    icon: item.icon,
                                                    onPressed:
                                                        (file) => item
                                                            .onPressed(file),
                                                  ),
                                                  file,
                                                  context,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                  ),
                                },
                          ),
                          file,
                          context,
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
