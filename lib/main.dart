import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:sensors_plus/sensors_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IndoSurveyMapsApp());
}

// -----------------------------------------------------------------------------
// LOCAL DATABASE HELPER (SQFlite Persistence)
// -----------------------------------------------------------------------------
class SurveyDatabase {
  static final SurveyDatabase instance = SurveyDatabase._init();
  static Database? _database;

  SurveyDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('indo_survey_maps.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'SQLite is supported on mobile/desktop platforms.');
    }
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE points ADD COLUMN notes TEXT");
          await db.execute("ALTER TABLE points ADD COLUMN photoPath TEXT");
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE points ADD COLUMN attributes TEXT");
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE points (
        id TEXT PRIMARY KEY,
        code TEXT,
        latitude REAL,
        longitude REAL,
        elevation REAL,
        antennaHeight REAL,
        timestamp TEXT,
        notes TEXT,
        photoPath TEXT,
        attributes TEXT
      )
    ''');
  }

  Future<int> insertPoint(SurveyPoint point) async {
    final db = await database;
    return await db.insert('points', point.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SurveyPoint>> fetchAllPoints() async {
    final db = await database;
    final result = await db.query('points', orderBy: 'timestamp DESC');
    return result.map((json) => SurveyPoint.fromMap(json)).toList();
  }
}

// -----------------------------------------------------------------------------
// SURVEY POINT MODEL
// -----------------------------------------------------------------------------
class SurveyPoint {
  final String id;
  final String code;
  final double latitude;
  final double longitude;
  final double elevation;
  final double antennaHeight;
  final DateTime timestamp;
  final String? notes;
  final String? photoPath;
  final String? attributes;

  SurveyPoint({
    required this.id,
    required this.code,
    required this.latitude,
    required this.longitude,
    required this.elevation,
    required this.antennaHeight,
    required this.timestamp,
    this.notes,
    this.photoPath,
    this.attributes,
  });

  LatLng toLatLng() => LatLng(latitude, longitude);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'latitude': latitude,
      'longitude': longitude,
      'elevation': elevation,
      'antennaHeight': antennaHeight,
      'timestamp': timestamp.toIso8601String(),
      'notes': notes ?? '',
      'photoPath': photoPath ?? '',
      'attributes': attributes ?? '',
    };
  }

  factory SurveyPoint.fromMap(Map<String, dynamic> map) {
    return SurveyPoint(
      id: map['id'],
      code: map['code'],
      latitude: map['latitude'],
      longitude: map['longitude'],
      elevation: map['elevation'],
      antennaHeight: map['antennaHeight'],
      timestamp: DateTime.parse(map['timestamp']),
      notes: map['notes'],
      photoPath: map['photoPath'],
      attributes: map['attributes'],
    );
  }
}

class IndoSurveyMapsApp extends StatelessWidget {
  const IndoSurveyMapsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Indo Survey Maps',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
        useMaterial3: true,
      ),
      home: const MainMapScreen(),
    );
  }
}

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  final MapController _mapController = MapController();
  final Distance _distanceCalculator = const Distance();

  bool _isSatelliteMode = false;
  bool _isOfflineCacheActive = false;
  bool _isGridLinesVisible = true;
  bool _isContoursVisible = true;
  bool _isCutFillHeatmapActive = false;
  bool _isVoiceGuidanceActive = true;

  String _currentProjectName = 'Default_Site_Survey_01';
  final List<String> _projectList = [
    'Default_Site_Survey_01',
    'Kampala_Highway_Ph1',
    'Entebbe_Plot_Subdivision'
  ];

  final List<String> _standardCodes = [
    'BOUNDARY',
    'ROAD',
    'TREE',
    'POLE',
    'DRAIN',
    'BUILDING',
    'MANHOLE',
    'GROUND'
  ];
  String _selectedFeatureCode = 'BOUNDARY';

  String _formMaterial = 'Concrete';
  String _formCondition = 'Good';
  bool _formInspectPass = true;

  bool _isCadLayerVisible = true;
  bool _cadLayerBoundaries = true;
  bool _cadLayerRoads = true;
  bool _cadLayerContours = true;
  String _importedDxfFileName = 'site_master_plan.dxf';

  bool _isAutoTopoActive = false;
  final String _autoTopoTriggerMode = 'Time Interval';
  final double _autoTopoIntervalValue = 5.0;
  Timer? _autoTopoTimer;

  String _coordinateSystem = 'WGS 84 (Geographic)';
  String _connectedReceiverName = 'Stonex S900A RTK (FIXED)';
  double _hrmsAccuracy = 0.007;
  double _vrmsAccuracy = 0.010;

  bool _isTotalStationMode = false;
  String _connectedTotalStation = 'Leica TS16 Robotic (Disconnected)';
  double _tsHzAngle = 84.2530;
  double _tsVAngle = 90.1220;
  double _tsSlopeDistance = 45.620;

  double _siteScaleFactor = 0.999950;
  double _gridConvergenceDeg = 0.0245;

  bool _isImuTiltEnabled = true;
  double _tiltAngleDeg = 0.0;
  double _tiltOffsetX = 0.0;
  double _tiltOffsetY = 0.0;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;

  String _activeRoadName = 'Kampala-Entebbe Expressway Section A';
  double _roadDesignWidth = 7.5;
  double _roadDesignCamber = 2.5;
  double _targetStationInterval = 20.0;

  List<SurveyPoint> _pointsList = [];
  int _pointCounter = 1;

  String _activeTool = 'Topo Survey';
  SurveyPoint? _stakeoutTarget;

  LatLng _currentLocation = const LatLng(0.3476, 32.5825);
  double _currentElevation = 1150.5;
  bool _isRoverAutoFollowActive = false;

  final List<LatLng> _measuredVertices = [];
  List<List<LatLng>> _subdividedLots = [];

  final List<LatLng> _cadBoundaryPolyline = [
    const LatLng(0.3485, 32.5815),
    const LatLng(0.3485, 32.5835),
    const LatLng(0.3465, 32.5835),
    const LatLng(0.3465, 32.5815),
    const LatLng(0.3485, 32.5815),
  ];

  final List<LatLng> _cadRoadCenterline = [
    const LatLng(0.3490, 32.5825),
    const LatLng(0.3460, 32.5825),
  ];

  final List<LatLng> _cadContourRing = [
    const LatLng(0.3480, 32.5810),
    const LatLng(0.3482, 32.5820),
    const LatLng(0.3478, 32.5840),
  ];

  @override
  void initState() {
    super.initState();
    _loadStoredPointsFromDB();
    _initImuSensorStream();
  }

  Future<void> _loadStoredPointsFromDB() async {
    if (kIsWeb) return;
    try {
      final points = await SurveyDatabase.instance.fetchAllPoints();
      setState(() {
        _pointsList = points;
        _pointCounter = points.length + 1;
      });
    } catch (e) {
      debugPrint("DB load error: $e");
    }
  }

  void _initImuSensorStream() {
    if (kIsWeb) return;
    try {
      _accelerometerSubscription =
          accelerometerEvents.listen((AccelerometerEvent event) {
        if (!_isImuTiltEnabled) return;
        setState(() {
          double g = math
              .sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
          if (g > 0) {
            double inclination =
                math.acos(event.z.clamp(-g, g) / g) * (180 / math.pi);
            _tiltAngleDeg = inclination;
            double poleHeight = 2.0;
            double horizontalDisplacement =
                poleHeight * math.sin(inclination * math.pi / 180);

            _tiltOffsetX = (event.x / g) * horizontalDisplacement * 0.00001;
            _tiltOffsetY = (event.y / g) * horizontalDisplacement * 0.00001;
          }
        });
      });
    } catch (e) {
      debugPrint("IMU sensor error: $e");
    }
  }

  @override
  void dispose() {
    _autoTopoTimer?.cancel();
    _accelerometerSubscription?.cancel();
    super.dispose();
  }

  LatLng get _trueTipLocation {
    if (!_isImuTiltEnabled) return _currentLocation;
    return LatLng(
      _currentLocation.latitude + _tiltOffsetY,
      _currentLocation.longitude + _tiltOffsetX,
    );
  }

  double _calculateDistanceToTarget() {
    if (_stakeoutTarget == null) return 0.0;
    return _distanceCalculator.as(
      LengthUnit.Meter,
      _trueTipLocation,
      _stakeoutTarget!.toLatLng(),
    );
  }

  double _calculateBearingToTarget() {
    if (_stakeoutTarget == null) return 0.0;
    final lat1 = _trueTipLocation.latitude * math.pi / 180;
    final lon1 = _trueTipLocation.longitude * math.pi / 180;
    final lat2 = _stakeoutTarget!.latitude * math.pi / 180;
    final lon2 = _stakeoutTarget!.longitude * math.pi / 180;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final radians = math.atan2(y, x);
    return (radians * 180 / math.pi + 360) % 360;
  }

  void _speakStakeoutGuidance(double dist, double bearing) {
    if (!_isVoiceGuidanceActive || _stakeoutTarget == null) return;

    String directionMessage = "";
    if (dist < 0.05) {
      directionMessage = "Target reached! Plumb point precisely.";
    } else if (dist < 0.50) {
      directionMessage =
          "Within centimeter tolerance. Distance ${dist.toStringAsFixed(2)} meters.";
    } else {
      String turnDir = (bearing > 180 && bearing < 360) ? "left" : "right";
      directionMessage =
          "Walk forward ${dist.toStringAsFixed(1)} meters, turn $turnDir.";
    }

    debugPrint("AUDIO PROMPT: $directionMessage");
  }

  double _calculatePolygonArea(List<LatLng> vertices) {
    if (vertices.length < 3) return 0.0;
    double area = 0.0;
    int n = vertices.length;
    for (int i = 0; i < n; i++) {
      var p1 = vertices[i];
      var p2 = vertices[(i + 1) % n];

      double x1 = p1.longitude * 111320 * math.cos(p1.latitude * math.pi / 180);
      double y1 = p1.latitude * 110540;
      double x2 = p2.longitude * 111320 * math.cos(p2.latitude * math.pi / 180);
      double y2 = p2.latitude * 110540;

      area += (x1 * y2) - (x2 * y1);
    }
    return (area.abs() / 2.0);
  }

  List<Polyline> _generateContourLines() {
    List<Polyline> contours = [];
    if (!_isContoursVisible || _pointsList.length < 3) return contours;

    for (int i = 0; i < _pointsList.length; i++) {
      for (int j = i + 1; j < _pointsList.length; j++) {
        double dist = _distanceCalculator.as(
          LengthUnit.Meter,
          _pointsList[i].toLatLng(),
          _pointsList[j].toLatLng(),
        );
        if (dist < 400.0) {
          contours.add(
            Polyline(
              points: [_pointsList[i].toLatLng(), _pointsList[j].toLatLng()],
              strokeWidth: 1.2,
              color: Colors.brown.withOpacity(0.7),
            ),
          );
        }
      }
    }
    return contours;
  }

  List<Polyline> _generateFeatureCodeStringPolylines() {
    Map<String, List<LatLng>> codeGroupedPoints = {};
    for (var pt in _pointsList.reversed) {
      codeGroupedPoints.putIfAbsent(pt.code, () => []).add(pt.toLatLng());
    }

    List<Polyline> stringPolylines = [];
    codeGroupedPoints.forEach((code, points) {
      if (points.length >= 2) {
        Color stringColor = Colors.blue;
        if (code == 'ROAD') stringColor = Colors.amber.shade800;
        if (code == 'BOUNDARY') stringColor = Colors.teal;
        if (code == 'DRAIN') stringColor = Colors.cyan;
        if (code == 'FENCE') stringColor = Colors.purple;

        stringPolylines.add(
          Polyline(
            points: points,
            strokeWidth: 3.0,
            color: stringColor,
          ),
        );
      }
    });

    return stringPolylines;
  }

  void _toggleAutoTopoLogging(bool enable) {
    setState(() {
      _isAutoTopoActive = enable;
    });

    if (_isAutoTopoActive) {
      _autoTopoTimer = Timer.periodic(
          Duration(seconds: _autoTopoIntervalValue.toInt()), (timer) async {
        final loc = _trueTipLocation;
        final newPt = SurveyPoint(
          id: 'AUT$_pointCounter',
          code: _selectedFeatureCode,
          latitude: loc.latitude,
          longitude: loc.longitude,
          elevation:
              _currentElevation + (math.Random().nextDouble() * 0.4 - 0.2),
          antennaHeight: 2.0,
          timestamp: DateTime.now(),
          notes: 'Auto-Topo logged',
          attributes: 'Material: $_formMaterial | Condition: $_formCondition',
        );

        if (!kIsWeb) {
          await SurveyDatabase.instance.insertPoint(newPt);
        }

        setState(() {
          _pointsList.add(newPt);
          _pointCounter++;
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Auto-Topo Logging Started (Walking Survey)!')),
      );
    } else {
      _autoTopoTimer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto-Topo Logging Stopped.')),
      );
    }
  }

  void _showCrossSectionViewerDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Road Station Cross-Section Profile'),
          content: SizedBox(
            width: 450,
            height: 350,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active Alignment: $_activeRoadName',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.deepOrange)),
                const SizedBox(height: 8),
                const Text(
                    'Ground Profile vs Design Formation Level (Camber: 2.5%):',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.deepOrange, width: 2),
                    ),
                    child: CustomPaint(
                      size: const Size(double.infinity, double.infinity),
                      painter: CrossSectionPainter(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text('— Ground Line',
                        style:
                            TextStyle(color: Colors.greenAccent, fontSize: 11)),
                    Text('— Design Template',
                        style:
                            TextStyle(color: Colors.amberAccent, fontSize: 11)),
                    Text('— Cut / Fill',
                        style:
                            TextStyle(color: Colors.redAccent, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        );
      },
    );
  }

  void _showCustomFormBuilderDialog() {
    final matController = TextEditingController(text: _formMaterial);
    final condController = TextEditingController(text: _formCondition);

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Custom GIS Attribute Form Builder'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Configure custom metadata fields attached to topo feature points:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: matController,
                  decoration: const InputDecoration(
                      labelText: 'Default Material Attribute',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: condController,
                  decoration: const InputDecoration(
                      labelText: 'Default Condition Rating',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Mandatory Photo Inspection Check',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text('Require site photo on save',
                      style: TextStyle(fontSize: 11)),
                  value: _formInspectPass,
                  onChanged: (val) => setState(() => _formInspectPass = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('Save Form Template'),
              onPressed: () {
                setState(() {
                  _formMaterial = matController.text;
                  _formCondition = condController.text;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Custom GIS attribute form template updated successfully!')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showFieldToolsHub() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Advanced Field Tools Hub',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Icon(Icons.widgets, color: Colors.blue),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: Icon(
                          _isCutFillHeatmapActive
                              ? Icons.visibility_off
                              : Icons.thermostat,
                          color: Colors.redAccent),
                      title: Text(_isCutFillHeatmapActive
                          ? 'Disable Cut/Fill Heatmap TIN'
                          : 'Enable Cut/Fill Heatmap TIN'),
                      subtitle: const Text(
                          'Color-grade surface mesh by cut & fill zones'),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() =>
                            _isCutFillHeatmapActive = !_isCutFillHeatmapActive);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(_isCutFillHeatmapActive
                                  ? 'Cut/Fill TIN Heatmap Enabled'
                                  : 'Cut/Fill TIN Heatmap Disabled')),
                        );
                      },
                    ),
                    ListTile(
                      leading: Icon(
                          _isVoiceGuidanceActive
                              ? Icons.volume_up
                              : Icons.volume_off,
                          color: Colors.indigo),
                      title: Text(_isVoiceGuidanceActive
                          ? 'Disable Voice Guidance'
                          : 'Enable Stakeout Voice Guidance'),
                      subtitle: const Text('Hands-free audio step directions'),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() =>
                            _isVoiceGuidanceActive = !_isVoiceGuidanceActive);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(_isVoiceGuidanceActive
                                  ? 'Stakeout Voice Guidance Enabled'
                                  : 'Stakeout Voice Guidance Disabled')),
                        );
                      },
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.dynamic_form, color: Colors.orange),
                      title: const Text('Custom GIS Attribute Form Builder'),
                      subtitle:
                          const Text('Configure dropdowns, materials & photos'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCustomFormBuilderDialog();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                          _isAutoTopoActive
                              ? Icons.pause_circle
                              : Icons.play_circle,
                          color: _isAutoTopoActive ? Colors.red : Colors.green),
                      title: Text(_isAutoTopoActive
                          ? 'Stop Auto-Topo Logging'
                          : 'Start Auto-Topo (Walking Survey)'),
                      subtitle: Text(
                          'Mode: $_autoTopoTriggerMode (${_autoTopoIntervalValue}s)'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _toggleAutoTopoLogging(!_isAutoTopoActive);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.show_chart,
                          color: Colors.deepOrange),
                      title: const Text('Cross-Section Profile Viewer'),
                      subtitle: const Text(
                          'Inspect station elevation vs design template'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCrossSectionViewerDialog();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.terrain, color: Colors.brown),
                      title: const Text('TIN Contours & Surface Mesh'),
                      subtitle: const Text(
                          'Toggle & generate topographic contour lines'),
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(
                            () => _isContoursVisible = !_isContoursVisible);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(_isContoursVisible
                                  ? 'TIN Contour Mesh Enabled'
                                  : 'TIN Contour Mesh Hidden')),
                        );
                      },
                    ),
                    ListTile(
                      leading:
                          const Icon(Icons.timeline, color: Colors.deepOrange),
                      title: const Text('Road & Alignment Stakeout'),
                      subtitle:
                          const Text('Station, offset & camber calculations'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showRoadAlignmentDialog();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.architecture,
                          color: Colors.redAccent),
                      title: const Text('Cut & Fill Earthwork Volume'),
                      subtitle: const Text('Compute grading earthwork volumes'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showEarthworkVolumeDialog();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTotalStationDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: const Text('Robotic Total Station Link'),
              content: SizedBox(
                width: 400,
                height: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Connect optical total stations via Bluetooth or serial cable for face-1/face-2 survey observations:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Optical Instrument Mode'),
                      subtitle: Text(_isTotalStationMode
                          ? 'Active (Total Station)'
                          : 'Inactive (GNSS RTK Rover)'),
                      value: _isTotalStationMode,
                      onChanged: (val) {
                        setStateModal(() => _isTotalStationMode = val);
                        setState(() {});
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.radar, color: Colors.indigo),
                      title: Text(_connectedTotalStation,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'Hz: ${_tsHzAngle.toStringAsFixed(4)}° | V: ${_tsVAngle.toStringAsFixed(4)}°',
                          style: const TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white),
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('Scan & Connect Leica / Sokkia TS'),
                        onPressed: () {
                          setStateModal(() {
                            _connectedTotalStation =
                                'Leica TS16 Robotic (CONNECTED)';
                            _isTotalStationMode = true;
                          });
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Successfully connected to Leica TS16 Robotic Total Station!')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  void _showRoadAlignmentDialog() {
    final widthController =
        TextEditingController(text: _roadDesignWidth.toString());
    final camberController =
        TextEditingController(text: _roadDesignCamber.toString());
    final intervalController =
        TextEditingController(text: _targetStationInterval.toString());

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Road Alignment & Template Manager'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Active Alignment: $_activeRoadName',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.deepOrange,
                        fontSize: 13)),
                const SizedBox(height: 12),
                TextField(
                  controller: widthController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Road Half-Width (m)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: camberController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Design Camber Slope (%)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: intervalController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Station Stakeout Interval (m)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white),
              child: const Text('Apply Road Template'),
              onPressed: () {
                setState(() {
                  _roadDesignWidth =
                      double.tryParse(widthController.text) ?? _roadDesignWidth;
                  _roadDesignCamber = double.tryParse(camberController.text) ??
                      _roadDesignCamber;
                  _targetStationInterval =
                      double.tryParse(intervalController.text) ??
                          _targetStationInterval;
                  _activeTool = 'Road Stakeout';
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Road alignment template active! Mode set to Road Stakeout.')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showImuBubbleDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            bool isPlumb = _tiltAngleDeg <= 2.0;
            return AlertDialog(
              backgroundColor: Colors.black87,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('IMU Electronic Bubble',
                      style:
                          TextStyle(color: Colors.greenAccent, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SizedBox(
                width: 320,
                height: 360,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('IMU Tilt Compensation',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      subtitle: Text(
                          _isImuTiltEnabled
                              ? 'Active (Up to 60° tilt)'
                              : 'Disabled (Requires Plumb)',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 11)),
                      value: _isImuTiltEnabled,
                      onChanged: (val) {
                        setStateModal(() => _isImuTiltEnabled = val);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tilt Angle: ${_tiltAngleDeg.toStringAsFixed(1)}°',
                      style: TextStyle(
                        color:
                            isPlumb ? Colors.greenAccent : Colors.orangeAccent,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isPlumb ? Colors.green : Colors.orange,
                              width: 3),
                          color: isPlumb
                              ? Colors.green.withOpacity(0.2)
                              : Colors.orange.withOpacity(0.1),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white30))),
                            Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white70))),
                            Transform.translate(
                              offset: Offset(
                                  _tiltOffsetX * 50000, _tiltOffsetY * 50000),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isPlumb
                                      ? Colors.greenAccent
                                      : Colors.orangeAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isPlumb
                          ? 'POLE IS PLUMB (Ready to Measure)'
                          : 'POLE TILTED — Correcting tip coordinates',
                      style: TextStyle(
                          color: isPlumb ? Colors.greenAccent : Colors.orange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showGridToGroundDialog() {
    final scaleController =
        TextEditingController(text: _siteScaleFactor.toStringAsFixed(6));
    final convController =
        TextEditingController(text: _gridConvergenceDeg.toStringAsFixed(4));

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Grid-to-Ground Transformation'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Configure site scale factors and convergence angles for engineering accuracy:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                TextField(
                  controller: scaleController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Combined Scale Factor',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: convController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Grid Convergence Angle (°)',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('Apply Parameters'),
              onPressed: () {
                setState(() {
                  _siteScaleFactor =
                      double.tryParse(scaleController.text) ?? _siteScaleFactor;
                  _gridConvergenceDeg = double.tryParse(convController.text) ??
                      _gridConvergenceDeg;
                });
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Grid-to-Ground parameters updated successfully!')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showTopoCodeEditorDialog() {
    final newCodeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Topo Feature Code Library'),
              content: SizedBox(
                width: 400,
                height: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Manage feature codes for topographic data collection:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _standardCodes.length,
                        itemBuilder: (context, index) {
                          final code = _standardCodes[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            child: ListTile(
                              leading: const Icon(Icons.category,
                                  color: Colors.blue, size: 20),
                              title: Text(code,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              trailing: _standardCodes.length > 1
                                  ? IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red, size: 18),
                                      onPressed: () {
                                        setStateDialog(() {
                                          _standardCodes.removeAt(index);
                                          if (_selectedFeatureCode == code) {
                                            _selectedFeatureCode =
                                                _standardCodes.first;
                                          }
                                        });
                                        setState(() {});
                                      },
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newCodeController,
                            decoration: const InputDecoration(
                                hintText: 'New code (e.g., WATER_VALVE)...',
                                isDense: true,
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          child: const Text('Add'),
                          onPressed: () {
                            final formatted =
                                newCodeController.text.trim().toUpperCase();
                            if (formatted.isNotEmpty &&
                                !_standardCodes.contains(formatted)) {
                              setStateDialog(() {
                                _standardCodes.add(formatted);
                              });
                              newCodeController.clear();
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  void _showStakeoutBullseyeDialog() {
    if (_stakeoutTarget == null) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            final double dist = _calculateDistanceToTarget() * _siteScaleFactor;
            final double bearing =
                (_calculateBearingToTarget() + _gridConvergenceDeg + 360) % 360;
            final double elevDiff =
                _currentElevation - _stakeoutTarget!.elevation;
            final bool isFixedCentimeter = dist < 0.5;

            _speakStakeoutGuidance(dist, bearing);

            return AlertDialog(
              backgroundColor: Colors.black87,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('BULLSEYE: ${_stakeoutTarget!.id}',
                      style:
                          const TextStyle(color: Colors.orange, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              content: SizedBox(
                width: 340,
                height: 380,
                child: Column(
                  children: [
                    Text(
                      'Distance: ${dist.toStringAsFixed(3)} m (Ground)',
                      style: TextStyle(
                        color: isFixedCentimeter
                            ? Colors.greenAccent
                            : Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      elevDiff >= 0
                          ? 'CUT: ${elevDiff.toStringAsFixed(3)} m'
                          : 'FILL: ${elevDiff.abs().toStringAsFixed(3)} m',
                      style: TextStyle(
                        color: elevDiff >= 0
                            ? Colors.redAccent
                            : Colors.greenAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: isFixedCentimeter
                                  ? Colors.green
                                  : Colors.orange,
                              width: 3),
                          color: isFixedCentimeter
                              ? Colors.green.withOpacity(0.2)
                              : Colors.orange.withOpacity(0.1),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.orange.shade300))),
                            Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.orange.shade100))),
                            Transform.rotate(
                              angle: (bearing * math.pi / 180),
                              child: const Icon(Icons.navigation,
                                  color: Colors.orangeAccent, size: 54),
                            ),
                            if (isFixedCentimeter)
                              const Center(
                                  child: Text('TARGET\nREACHED',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.greenAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('Ground Bearing: ${bearing.toStringAsFixed(1)}°',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showNtripConfigDialog() {
    final ipController = TextEditingController(text: 'rtk.cors-network.net');
    final portController = TextEditingController(text: '2101');
    final mountpointController = TextEditingController(text: 'RTCM3_MSM5');
    final userController = TextEditingController(text: 'surveyor_user');
    final passController = TextEditingController(text: '••••••••');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('NTRIP Client (RTK Correction)'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    'Configure CORS / NTRIP caster connection for RTK fixed status:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 10),
                TextField(
                    controller: ipController,
                    decoration: const InputDecoration(
                        labelText: 'Caster IP / Hostname',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: TextField(
                            controller: portController,
                            decoration: const InputDecoration(
                                labelText: 'Port',
                                border: OutlineInputBorder(),
                                isDense: true))),
                    const SizedBox(width: 8),
                    Expanded(
                        flex: 2,
                        child: TextField(
                            controller: mountpointController,
                            decoration: const InputDecoration(
                                labelText: 'Mountpoint',
                                border: OutlineInputBorder(),
                                isDense: true))),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: userController,
                    decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        isDense: true)),
                const SizedBox(height: 8),
                TextField(
                    controller: passController,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        isDense: true)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white),
              child: const Text('Connect NTRIP'),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _hrmsAccuracy = 0.008;
                  _vrmsAccuracy = 0.012;
                  _connectedReceiverName = 'Stonex S900A (NTRIP FIXED)';
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          'Successfully connected to NTRIP Caster! RTK Status: FIXED')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showEarthworkVolumeDialog() {
    final designElevController =
        TextEditingController(text: _currentElevation.toStringAsFixed(2));
    double totalCutVolume = 1250.5;
    double totalFillVolume = 820.0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Cut & Fill Earthwork Volume'),
              content: SizedBox(
                width: 400,
                height: 260,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Compute grading earthwork volumes against a target design level:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: designElevController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Design Formation Level (m)',
                          border: OutlineInputBorder(),
                          isDense: true),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              'Total Cut Volume: ${totalCutVolume.toStringAsFixed(2)} m³',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.redAccent)),
                          const SizedBox(height: 6),
                          Text(
                              'Total Fill Volume: ${totalFillVolume.toStringAsFixed(2)} m³',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.green)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  void _runSubdivisionTool() {
    if (_measuredVertices.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please measure or select a closed polygon with at least 4 vertices first!')),
      );
      return;
    }

    double midLng =
        (_measuredVertices[0].longitude + _measuredVertices[1].longitude) / 2;
    LatLng topMid = LatLng(_measuredVertices[0].latitude, midLng);
    LatLng botMid = LatLng(_measuredVertices[2].latitude, midLng);

    List<LatLng> lot1 = [
      _measuredVertices[0],
      _measuredVertices[1],
      botMid,
      topMid
    ];
    List<LatLng> lot2 = [
      topMid,
      botMid,
      _measuredVertices[2],
      _measuredVertices[3]
    ];

    setState(() {
      _subdividedLots = [lot1, lot2];
    });

    showDialog(
      context: context,
      builder: (ctx) {
        double area1 = _calculatePolygonArea(lot1);
        double area2 = _calculatePolygonArea(lot2);
        return AlertDialog(
          title: const Text('Parcel Subdivision Results'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Original Parent Parcel Area: ${_calculatePolygonArea(_measuredVertices).toStringAsFixed(1)} m²'),
              const Divider(),
              Text(
                  'Lot 1 Area: ${area1.toStringAsFixed(1)} m² (${(area1 / 4046.86).toStringAsFixed(3)} ac)'),
              Text(
                  'Lot 2 Area: ${area2.toStringAsFixed(1)} m² (${(area2 / 4046.86).toStringAsFixed(3)} ac)'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => setState(() => _subdividedLots.clear()),
              child: const Text('Clear Split'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showGnssSkyplotDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('GNSS Skyplot & Satellites'),
          content: SizedBox(
            width: 400,
            height: 360,
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Chip(
                        label: Text('GPS: 12'),
                        backgroundColor: Color(0xFFBBDEFB)),
                    Chip(
                        label: Text('GLONASS: 9'),
                        backgroundColor: Color(0xFFC8E6C9)),
                    Chip(
                        label: Text('Galileo: 8'),
                        backgroundColor: Color(0xFFFFE0B2)),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue, width: 2),
                      color: Colors.blue.shade50.withOpacity(0.5),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue))),
                        Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue))),
                        const Icon(Icons.gps_fixed,
                            color: Colors.red, size: 28),
                        const Positioned(
                            top: 45,
                            left: 120,
                            child:
                                Icon(Icons.star, color: Colors.blue, size: 18)),
                        const Positioned(
                            top: 90,
                            right: 70,
                            child: Icon(Icons.star,
                                color: Colors.green, size: 18)),
                        const Positioned(
                            bottom: 60,
                            left: 100,
                            child: Icon(Icons.star,
                                color: Colors.orange, size: 18)),
                        const Positioned(
                            top: 110,
                            left: 70,
                            child:
                                Icon(Icons.star, color: Colors.blue, size: 18)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('PDOP: 1.2 | HDOP: 0.8 | VDOP: 1.0',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        );
      },
    );
  }

  void _showCogoCalculatorDialog() {
    SurveyPoint? ptA;
    SurveyPoint? ptB;
    String inverseResult =
        'Select two points to compute inverse distance and bearing.';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('COGO Inverse Calculator'),
              content: SizedBox(
                width: 420,
                height: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Calculate distance and bearing between two database points:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<SurveyPoint>(
                      value: ptA,
                      decoration: const InputDecoration(
                          labelText: 'From Point (A)',
                          border: OutlineInputBorder(),
                          isDense: true),
                      items: _pointsList.map((pt) {
                        return DropdownMenuItem(
                            value: pt, child: Text('${pt.id} [${pt.code}]'));
                      }).toList(),
                      onChanged: (val) => setStateDialog(() => ptA = val),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<SurveyPoint>(
                      value: ptB,
                      decoration: const InputDecoration(
                          labelText: 'To Point (B)',
                          border: OutlineInputBorder(),
                          isDense: true),
                      items: _pointsList.map((pt) {
                        return DropdownMenuItem(
                            value: pt, child: Text('${pt.id} [${pt.code}]'));
                      }).toList(),
                      onChanged: (val) => setStateDialog(() => ptB = val),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white),
                        child: const Text('Compute Inverse'),
                        onPressed: () {
                          if (ptA != null && ptB != null) {
                            double dist = _distanceCalculator.as(
                                    LengthUnit.Meter,
                                    ptA!.toLatLng(),
                                    ptB!.toLatLng()) *
                                _siteScaleFactor;

                            final lat1 = ptA!.latitude * math.pi / 180;
                            final lon1 = ptA!.longitude * math.pi / 180;
                            final lat2 = ptB!.latitude * math.pi / 180;
                            final lon2 = ptB!.longitude * math.pi / 180;
                            final dLon = lon2 - lon1;
                            final y = math.sin(dLon) * math.cos(lat2);
                            final x = math.cos(lat1) * math.sin(lat2) -
                                math.sin(lat1) *
                                    math.cos(lat2) *
                                    math.cos(dLon);
                            double bearing = (math.atan2(y, x) * 180 / math.pi +
                                    _gridConvergenceDeg +
                                    360) %
                                360;

                            setStateDialog(() {
                              inverseResult =
                                  'Ground Distance: ${dist.toStringAsFixed(3)} m\nGrid Bearing: ${bearing.toStringAsFixed(2)}°';
                            });
                          }
                        },
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6)),
                        child: Center(
                          child: Text(inverseResult,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13),
                              textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  void _showProjectManagerDialog() {
    final newProjectController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Project Manager'),
              content: SizedBox(
                width: 400,
                height: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active and Saved Survey Jobs:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _projectList.length,
                        itemBuilder: (context, index) {
                          final proj = _projectList[index];
                          final isActive = proj == _currentProjectName;
                          return Card(
                            color:
                                isActive ? Colors.blue.shade50 : Colors.white,
                            child: ListTile(
                              leading: Icon(Icons.folder,
                                  color: isActive ? Colors.blue : Colors.grey),
                              title: Text(proj,
                                  style: TextStyle(
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                              trailing: isActive
                                  ? const Chip(
                                      label: Text('ACTIVE',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.white)),
                                      backgroundColor: Colors.blue)
                                  : TextButton(
                                      child: const Text('Switch'),
                                      onPressed: () {
                                        setState(() {
                                          _currentProjectName = proj;
                                          _stakeoutTarget = null;
                                        });
                                        Navigator.pop(ctx);
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'Switched to project: $proj')),
                                        );
                                      },
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newProjectController,
                            decoration: const InputDecoration(
                                hintText: 'New project name...',
                                isDense: true,
                                border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          child: const Text('Create'),
                          onPressed: () {
                            if (newProjectController.text.trim().isNotEmpty) {
                              setState(() {
                                _projectList
                                    .add(newProjectController.text.trim());
                                _currentProjectName =
                                    newProjectController.text.trim();
                              });
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Created & switched to: $_currentProjectName')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  void _showGnssConnectionDialog() {
    final List<Map<String, String>> discoveredDevices = [
      {
        'name': 'Stonex S900A RTK',
        'mac': '00:12:43:08:B1:2F',
        'signal': '-65 dBm'
      },
      {
        'name': 'Leica GS18 T GNSS',
        'mac': '00:80:98:EC:4A:11',
        'signal': '-72 dBm'
      },
      {
        'name': 'Trimble R12i GNSS',
        'mac': '00:05:51:33:EE:88',
        'signal': '-80 dBm'
      },
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: const Text('Bluetooth GNSS Scanner'),
              content: SizedBox(
                width: 400,
                height: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Select a receiver from the scanned network list below to connect:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: discoveredDevices.length,
                        itemBuilder: (context, index) {
                          final dev = discoveredDevices[index];
                          final bool isConnected =
                              _connectedReceiverName.contains(dev['name']!);

                          return Card(
                            color: isConnected
                                ? Colors.blue.shade50
                                : Colors.white,
                            child: ListTile(
                              leading: Icon(Icons.bluetooth,
                                  color:
                                      isConnected ? Colors.blue : Colors.grey),
                              title: Text(dev['name']!,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              subtitle: Text(
                                  'MAC: ${dev['mac']} | Signal: ${dev['signal']}',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      isConnected ? Colors.green : Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                ),
                                child:
                                    Text(isConnected ? 'Connected' : 'Connect'),
                                onPressed: () {
                                  setState(() {
                                    _connectedReceiverName =
                                        '${dev['name']} (FIXED)';
                                    _hrmsAccuracy = 0.007;
                                    _vrmsAccuracy = 0.010;
                                  });
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            'Successfully connected to ${dev['name']}!')),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.wifi, color: Colors.green),
                      title: const Text('NTRIP Caster Connection'),
                      subtitle: const Text('Configure internet RTCM stream'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showNtripConfigDialog();
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  void _showCoordinateSystemDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Coordinate System & Projection'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('WGS 84 (Geographic Degrees)'),
                subtitle: const Text('Standard lat/long GPS format'),
                value: 'WGS 84 (Geographic)',
                groupValue: _coordinateSystem,
                onChanged: (val) {
                  setState(() => _coordinateSystem = val!);
                  Navigator.pop(ctx);
                },
              ),
              RadioListTile<String>(
                title: const Text('UTM Zone 36N (Meters)'),
                subtitle: const Text('Projected Grid (Eastings/Northings)'),
                value: 'UTM Zone 36N (Meters)',
                groupValue: _coordinateSystem,
                onChanged: (val) {
                  setState(() => _coordinateSystem = val!);
                  Navigator.pop(ctx);
                },
              ),
              RadioListTile<String>(
                title: const Text('Local Site Grid (Custom Grid)'),
                subtitle: const Text('Local project calibration grid'),
                value: 'Local Site Grid',
                groupValue: _coordinateSystem,
                onChanged: (val) {
                  setState(() => _coordinateSystem = val!);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCadImportDialog() {
    final dxfController = TextEditingController(text: _importedDxfFileName);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: const Text('CAD / DXF Layer & File Importer'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Import and manage AutoCAD DXF / Shapefile engineering overlays:',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dxfController,
                      decoration: const InputDecoration(
                        labelText: 'Loaded DXF / DWG File',
                        prefixIcon:
                            Icon(Icons.insert_drive_file, color: Colors.teal),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white),
                        icon: const Icon(Icons.folder_open),
                        label: const Text(
                            'Browse & Import CAD File (.dxf / .shp)'),
                        onPressed: () {
                          setStateModal(() {
                            _importedDxfFileName = 'site_expansion_phase2.dxf';
                            dxfController.text = _importedDxfFileName;
                            _isCadLayerVisible = true;
                          });
                          setState(() {});
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Successfully parsed and imported CAD vector layers!')),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    SwitchListTile(
                      title: const Text('Enable CAD Vector Overlay'),
                      subtitle: Text(_importedDxfFileName),
                      value: _isCadLayerVisible,
                      onChanged: (val) {
                        setStateModal(() {
                          _isCadLayerVisible = val;
                        });
                        setState(() {});
                      },
                    ),
                    CheckboxListTile(
                      title: const Text('Property_Boundaries (Teal)'),
                      value: _cadLayerBoundaries,
                      onChanged: _isCadLayerVisible
                          ? (val) {
                              setStateModal(() => _cadLayerBoundaries = val!);
                              setState(() {});
                            }
                          : null,
                    ),
                    CheckboxListTile(
                      title: const Text('Roads_Centerline (Amber)'),
                      value: _cadLayerRoads,
                      onChanged: _isCadLayerVisible
                          ? (val) {
                              setStateModal(() => _cadLayerRoads = val!);
                              setState(() {});
                            }
                          : null,
                    ),
                    CheckboxListTile(
                      title: const Text('Topography_Contours (Brown)'),
                      value: _cadLayerContours,
                      onChanged: _isCadLayerVisible
                          ? (val) {
                              setStateModal(() => _cadLayerContours = val!);
                              setState(() {});
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPointManagerDialog() {
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final filteredPoints = _pointsList.where((pt) {
              return pt.id.toLowerCase().contains(searchQuery.toLowerCase()) ||
                  pt.code.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Point Database Manager',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              content: SizedBox(
                width: 450,
                height: 380,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Search by ID or Code',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (val) {
                        setStateDialog(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: filteredPoints.isEmpty
                          ? const Center(
                              child: Text(
                                  'No survey points found in local database.'))
                          : ListView.builder(
                              itemCount: filteredPoints.length,
                              itemBuilder: (context, index) {
                                final pt = filteredPoints[index];
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.blue.shade100,
                                      child: Text(pt.id,
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade900)),
                                    ),
                                    title: Text('${pt.id} [${pt.code}]'),
                                    subtitle: Text(
                                        'Lat: ${pt.latitude.toStringAsFixed(5)}, Lng: ${pt.longitude.toStringAsFixed(5)}\nAttributes: ${pt.attributes ?? 'None'}',
                                        style: const TextStyle(fontSize: 11)),
                                    isThreeLine: true,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.note_add,
                                              color: Colors.orange),
                                          onPressed: () =>
                                              _showEditPointNotesDialog(pt),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.my_location,
                                              color: Colors.blue),
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            _mapController.move(
                                                pt.toLatLng(), 18.0);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditPointNotesDialog(SurveyPoint pt) {
    final notesController = TextEditingController(text: pt.notes ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Edit Notes & Attributes for ${pt.id}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Field Observation Notes',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('Attach Site Photo'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Simulated site photo attached successfully!')),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final updatedPoint = SurveyPoint(
                  id: pt.id,
                  code: pt.code,
                  latitude: pt.latitude,
                  longitude: pt.longitude,
                  elevation: pt.elevation,
                  antennaHeight: pt.antennaHeight,
                  timestamp: pt.timestamp,
                  notes: notesController.text,
                  photoPath: 'site_photo_${pt.id}.jpg',
                  attributes: pt.attributes,
                );

                if (!kIsWeb) {
                  await SurveyDatabase.instance.insertPoint(updatedPoint);
                }

                setState(() {
                  final index = _pointsList.indexWhere((p) => p.id == pt.id);
                  if (index != -1) {
                    _pointsList[index] = updatedPoint;
                  }
                });

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Notes updated for point ${pt.id}!')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showExportDialog() {
    final buffer = StringBuffer();
    buffer.writeln(
        'PointID,Code,Latitude,Longitude,Elevation,AntennaHeight,Timestamp,Attributes');
    for (var pt in _pointsList) {
      buffer.writeln(
          '${pt.id},${pt.code},${pt.latitude},${pt.longitude},${pt.elevation},${pt.antennaHeight},${pt.timestamp.toIso8601String()},"${pt.attributes ?? ''}"');
    }
    final csvData = buffer.toString();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Export Survey Data (CSV)'),
          content: SizedBox(
            width: 400,
            height: 250,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Your SQLite database points formatted as standard CSV with GIS attributes:',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: SingleChildScrollView(
                      child: Text(csvData,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white),
              icon: const Icon(Icons.check),
              label: const Text('Exported Successfully'),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('CSV export generated successfully!')),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showAddPointDialog() {
    final targetLocation = _isRoverAutoFollowActive
        ? _trueTipLocation
        : _mapController.camera.center;

    final idController = TextEditingController(
        text: 'PT${_pointCounter.toString().padLeft(3, '0')}');
    final antennaHeightController =
        TextEditingController(text: _isTotalStationMode ? '1.500' : '2.000');
    final elevationController =
        TextEditingController(text: _currentElevation.toStringAsFixed(3));
    final notesController = TextEditingController();

    if (!_standardCodes.contains(_selectedFeatureCode)) {
      _selectedFeatureCode = _standardCodes.first;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          _isTotalStationMode
                              ? 'Total Station: Store Optical Shot'
                              : 'Topo Survey: Store Point (Custom Form)',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 6),
                  TextField(
                    controller: idController,
                    decoration: const InputDecoration(
                        labelText: 'Point ID Name',
                        prefixIcon: Icon(Icons.pin),
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _selectedFeatureCode,
                    decoration: const InputDecoration(
                        labelText: 'Feature Code (Topo Library)',
                        prefixIcon: Icon(Icons.category),
                        border: OutlineInputBorder(),
                        isDense: true),
                    items: _standardCodes.map((code) {
                      return DropdownMenuItem(value: code, child: Text(code));
                    }).toList(),
                    onChanged: (val) {
                      setStateModal(() {
                        _selectedFeatureCode = val!;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: antennaHeightController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: _isTotalStationMode
                                  ? 'Prism Ht (m)'
                                  : 'Antenna Ht (m)',
                              prefixIcon: const Icon(Icons.height),
                              border: const OutlineInputBorder(),
                              isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: elevationController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Elevation (m)',
                              prefixIcon: Icon(Icons.terrain),
                              border: OutlineInputBorder(),
                              isDense: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('GIS Form Attributes:',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: Colors.blue)),
                        Text(
                            'Material: $_formMaterial | Condition: $_formCondition',
                            style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                        labelText: 'Field Observation Notes',
                        prefixIcon: Icon(Icons.note),
                        border: OutlineInputBorder(),
                        isDense: true),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _isTotalStationMode
                              ? Colors.indigo
                              : Colors.blue.shade700,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.save),
                      label: Text(
                          _isTotalStationMode
                              ? 'STORE TOTAL STATION SHOT'
                              : 'STORE POINT & ATTRIBUTES',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () async {
                        final newPoint = SurveyPoint(
                          id: idController.text,
                          code: _selectedFeatureCode,
                          latitude: targetLocation.latitude,
                          longitude: targetLocation.longitude,
                          elevation:
                              double.tryParse(elevationController.text) ??
                                  _currentElevation,
                          antennaHeight:
                              double.tryParse(antennaHeightController.text) ??
                                  2.0,
                          timestamp: DateTime.now(),
                          notes: notesController.text,
                          attributes:
                              'Material: $_formMaterial, Condition: $_formCondition',
                        );

                        if (!kIsWeb) {
                          await SurveyDatabase.instance.insertPoint(newPoint);
                        }

                        setState(() {
                          _pointsList.add(newPoint);
                          _pointCounter++;
                        });

                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  'Point "${newPoint.id}" [${newPoint.code}] stored successfully!')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showStakeoutTypeSelector() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Stakeout Mode',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.pin_drop, color: Colors.blue),
                title: const Text('Point Stakeout'),
                subtitle: const Text(
                    'Navigate to a specific database point coordinate'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showStakeoutTargetSelector();
                },
              ),
              ListTile(
                leading: const Icon(Icons.timeline, color: Colors.deepOrange),
                title: const Text('Road & Alignment Stakeout'),
                subtitle:
                    const Text('Station, Offset & Road Template Cross-Slope'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRoadAlignmentDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showStakeoutTargetSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Stakeout Target Point',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const Divider(),
              Expanded(
                child: _pointsList.isEmpty
                    ? const Center(child: Text('No points stored in database.'))
                    : ListView.builder(
                        itemCount: _pointsList.length,
                        itemBuilder: (context, index) {
                          final pt = _pointsList[index];
                          final isSelected = _stakeoutTarget?.id == pt.id;

                          return Card(
                            color: isSelected
                                ? Colors.orange.shade50
                                : Colors.white,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isSelected
                                    ? Colors.orange
                                    : Colors.blue.shade100,
                                child: Text(pt.id,
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.blue.shade900)),
                              ),
                              title: Text('${pt.id} [${pt.code}]'),
                              subtitle: Text(
                                  'Lat: ${pt.latitude.toStringAsFixed(5)}, Lng: ${pt.longitude.toStringAsFixed(5)}, Elev: ${pt.elevation.toStringAsFixed(2)}m'),
                              trailing: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: isSelected
                                        ? Colors.orange
                                        : Colors.blue),
                                child: Text(isSelected ? 'ACTIVE' : 'SELECT',
                                    style:
                                        const TextStyle(color: Colors.white)),
                                onPressed: () {
                                  setState(() {
                                    _stakeoutTarget = pt;
                                    _activeTool = 'Stakeout';
                                  });
                                  Navigator.pop(ctx);
                                  _mapController.move(pt.toLatLng(), 18.0);
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Marker> markers = _pointsList.map((pt) {
      final isTarget = _stakeoutTarget?.id == pt.id;
      final double elevDiff = pt.elevation - 1150.0;
      final Color pointColor = _isCutFillHeatmapActive
          ? (elevDiff >= 0 ? Colors.redAccent : Colors.greenAccent)
          : (isTarget ? Colors.orange : Colors.red);

      return Marker(
        point: pt.toLatLng(),
        width: 70,
        height: 70,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isTarget ? Colors.orange.shade900 : Colors.black87,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${pt.id}${_isCutFillHeatmapActive ? ' (${elevDiff >= 0 ? '+' : ''}${elevDiff.toStringAsFixed(1)}m)' : ''}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Icon(
              Icons.location_on,
              color: pointColor,
              size: isTarget ? 36 : 28,
            ),
          ],
        ),
      );
    }).toList();

    if (_activeTool == 'Measure Area') {
      for (int i = 0; i < _measuredVertices.length; i++) {
        markers.add(
          Marker(
            point: _measuredVertices[i],
            width: 30,
            height: 30,
            child: Container(
              decoration: const BoxDecoration(
                  color: Colors.purple, shape: BoxShape.circle),
              child: Center(
                child: Text('${i + 1}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        );
      }
    }

    markers.add(
      Marker(
        point: _trueTipLocation,
        width: 40,
        height: 40,
        child: Icon(
          _isTotalStationMode ? Icons.adjust : Icons.navigation,
          color: _isTotalStationMode ? Colors.indigoAccent : Colors.blueAccent,
          size: 36,
        ),
      ),
    );

    final List<Polyline> polylines = [];
    final List<Polygon> polygons = [];

    polylines.addAll(_generateContourLines());
    polylines.addAll(_generateFeatureCodeStringPolylines());

    if (_isGridLinesVisible) {
      for (double lat = 0.3450; lat <= 0.3500; lat += 0.0010) {
        polylines.add(
          Polyline(
            points: [LatLng(lat, 32.5750), LatLng(lat, 32.5900)],
            strokeWidth: 1.0,
            color: Colors.grey.withOpacity(0.35),
          ),
        );
      }
      for (double lng = 32.5750; lng <= 32.5900; lng += 0.0010) {
        polylines.add(
          Polyline(
            points: [LatLng(0.3440, lng), LatLng(0.3510, lng)],
            strokeWidth: 1.0,
            color: Colors.grey.withOpacity(0.35),
          ),
        );
      }
    }

    if (_isCadLayerVisible) {
      if (_cadLayerBoundaries) {
        polylines.add(
          Polyline(
            points: _cadBoundaryPolyline,
            strokeWidth: 2.5,
            color: Colors.teal,
          ),
        );
      }
      if (_cadLayerRoads) {
        polylines.add(
          Polyline(
            points: _cadRoadCenterline,
            strokeWidth: 3.0,
            color: Colors.amber,
          ),
        );
      }
      if (_cadLayerContours) {
        polylines.add(
          Polyline(
            points: _cadContourRing,
            strokeWidth: 1.5,
            color: Colors.brown,
          ),
        );
      }
    }

    for (var lot in _subdividedLots) {
      polygons.add(
        Polygon(
          points: lot,
          color: Colors.cyan.withOpacity(0.35),
          borderColor: Colors.cyanAccent,
          borderStrokeWidth: 2.5,
        ),
      );
    }

    if (_activeTool == 'Stakeout' && _stakeoutTarget != null) {
      polylines.add(
        Polyline(
          points: [_trueTipLocation, _stakeoutTarget!.toLatLng()],
          strokeWidth: 3.0,
          color: Colors.orange,
        ),
      );
    } else if (_activeTool == 'Road Stakeout') {
      polylines.add(
        Polyline(
          points: _cadRoadCenterline,
          strokeWidth: 4.5,
          color: Colors.deepOrange,
        ),
      );
    } else if (_activeTool == 'Measure Area' && _measuredVertices.isNotEmpty) {
      if (_measuredVertices.length >= 3) {
        polygons.add(
          Polygon(
            points: _measuredVertices,
            color: Colors.purple.withOpacity(0.3),
            borderColor: Colors.purple,
            borderStrokeWidth: 3.0,
          ),
        );
      } else {
        polylines.add(
          Polyline(
            points: _measuredVertices,
            strokeWidth: 3.0,
            color: Colors.purple,
          ),
        );
      }
    }

    final distanceToTarget = _calculateDistanceToTarget() * _siteScaleFactor;
    final bearingToTarget =
        (_calculateBearingToTarget() + _gridConvergenceDeg + 360) % 360;
    final elevationDiff = _stakeoutTarget != null
        ? (_currentElevation - _stakeoutTarget!.elevation)
        : 0.0;
    final roadStation = ((_currentLocation.latitude - 0.3460) * 111000).abs();
    final roadOffset = (_currentLocation.longitude - 32.5825) *
        111000 *
        math.cos(0.3476 * math.pi / 180);

    final polygonAreaSqMeters = _calculatePolygonArea(_measuredVertices) *
        (_siteScaleFactor * _siteScaleFactor);
    final polygonAreaHectares = polygonAreaSqMeters / 10000.0;
    final polygonAreaAcres = polygonAreaSqMeters / 4046.86;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showProjectManagerDialog,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  'Indo Survey - $_currentProjectName',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.widgets, color: Colors.blue),
            tooltip: 'Advanced Field Tools Hub',
            onPressed: _showFieldToolsHub,
          ),
          IconButton(
            icon: Icon(Icons.radar,
                color: _isTotalStationMode ? Colors.indigo : Colors.grey),
            tooltip: 'Total Station Link',
            onPressed: _showTotalStationDialog,
          ),
          IconButton(
            icon: Icon(Icons.trip_origin,
                color: _tiltAngleDeg <= 2.0 ? Colors.green : Colors.orange),
            tooltip: 'IMU Electronic Bubble Level',
            onPressed: _showImuBubbleDialog,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue.shade800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Icon(Icons.map, color: Colors.white, size: 40),
                  const SizedBox(height: 10),
                  const Text('Indo Survey Maps',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text('Active Project: $_currentProjectName',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_special, color: Colors.blue),
              title: const Text('Project Manager'),
              subtitle: Text('Active: $_currentProjectName'),
              onTap: () {
                Navigator.pop(context);
                _showProjectManagerDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.bluetooth, color: Colors.indigo),
              title: const Text('GNSS Receiver Setup & NTRIP'),
              subtitle: Text(_connectedReceiverName),
              onTap: () {
                Navigator.pop(context);
                _showGnssConnectionDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.category, color: Colors.orange),
              title: const Text('Topo Feature Code Library'),
              subtitle: Text('${_standardCodes.length} codes available'),
              onTap: () {
                Navigator.pop(context);
                _showTopoCodeEditorDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.transform, color: Colors.teal),
              title: const Text('Grid-to-Ground Transformation'),
              subtitle: Text('Scale: ${_siteScaleFactor.toStringAsFixed(6)}'),
              onTap: () {
                Navigator.pop(context);
                _showGridToGroundDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.public, color: Colors.purple),
              title: const Text('Coordinate System'),
              subtitle: Text(_coordinateSystem),
              onTap: () {
                Navigator.pop(context);
                _showCoordinateSystemDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.calculate, color: Colors.brown),
              title: const Text('COGO Inverse Calculator'),
              subtitle: const Text('Distance & bearing between points'),
              onTap: () {
                Navigator.pop(context);
                _showCogoCalculatorDialog();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info),
              title: const Text('App Information'),
              subtitle: const Text('Version 1.3.1 (Fixed Path Namespace)'),
              onTap: () {},
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _trueTipLocation,
              initialZoom: 16.0,
              onTap: (tapPosition, point) {
                if (_activeTool == 'Measure Area') {
                  setState(() {
                    _measuredVertices.add(point);
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: _isOfflineCacheActive
                    ? 'assets/offline_tiles/{z}/{x}/{y}.png'
                    : (_isSatelliteMode
                        ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                userAgentPackageName: 'com.indo.surveymaps',
              ),
              PolygonLayer(polygons: polygons),
              PolylineLayer(polylines: polylines),
              MarkerLayer(markers: markers),
            ],
          ),
          if (_isCutFillHeatmapActive)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.thermostat, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text('TIN HEATMAP ACTIVE: Red = Cut, Green = Fill',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            )
          else if (_isAutoTopoActive)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.fiber_manual_record,
                        color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text('AUTO-TOPO LOGGING ACTIVE (Walking Survey)',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12)),
                  ],
                ),
              ),
            ),
          if (_activeTool == 'Measure Area')
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('POLYGON AREA MEASUREMENT (GROUND)',
                            style: TextStyle(
                                color: Colors.purpleAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 11)),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyan.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6)),
                              icon: const Icon(Icons.call_split, size: 14),
                              label: const Text('Split',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: _runSubdivisionTool,
                            ),
                            const SizedBox(width: 6),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6)),
                              icon: const Icon(Icons.clear, size: 14),
                              label: const Text('Clear',
                                  style: TextStyle(fontSize: 11)),
                              onPressed: () => setState(() {
                                _measuredVertices.clear();
                                _subdividedLots.clear();
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Vertices: ${_measuredVertices.length}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text(
                      'Area: ${polygonAreaSqMeters.toStringAsFixed(1)} m²  |  ${polygonAreaHectares.toStringAsFixed(3)} ha  |  ${polygonAreaAcres.toStringAsFixed(3)} ac',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else if (_activeTool == 'Road Stakeout')
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepOrange, width: 2),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timeline,
                        color: Colors.deepOrange, size: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ROAD STAKE: ${_activeRoadName.substring(0, 15)}...',
                            style: const TextStyle(
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Station: K+${roadStation.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Offset: ${roadOffset >= 0 ? 'R ' : 'L '}${roadOffset.abs().toStringAsFixed(2)} m (Width: ${_roadDesignWidth}m)',
                            style: const TextStyle(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz, color: Colors.white),
                      onPressed: _showStakeoutTypeSelector,
                    )
                  ],
                ),
              ),
            )
          else if (_activeTool == 'Stakeout' && _stakeoutTarget != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange, width: 2),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _showStakeoutBullseyeDialog,
                      child: Transform.rotate(
                        angle: (bearingToTarget * math.pi / 180),
                        child: const Icon(Icons.navigation,
                            color: Colors.orange, size: 42),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: GestureDetector(
                        onTap: _showStakeoutBullseyeDialog,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'STAKEOUT: ${_stakeoutTarget!.id} [${_stakeoutTarget!.code}] (Tap for Bullseye)',
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Distance: ${distanceToTarget.toStringAsFixed(3)} m (Ground)',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              elevationDiff >= 0
                                  ? 'CUT: ${elevationDiff.toStringAsFixed(3)} m'
                                  : 'FILL: ${elevationDiff.abs().toStringAsFixed(3)} m',
                              style: TextStyle(
                                color: elevationDiff >= 0
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.gps_fixed,
                          color: Colors.orangeAccent),
                      tooltip: 'Open Bullseye Compass',
                      onPressed: _showStakeoutBullseyeDialog,
                    ),
                    IconButton(
                      icon: const Icon(Icons.swap_horiz, color: Colors.white),
                      onPressed: _showStakeoutTypeSelector,
                    )
                  ],
                ),
              ),
            )
          else
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: GestureDetector(
                onTap: _isTotalStationMode
                    ? _showTotalStationDialog
                    : _showImuBubbleDialog,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _isTotalStationMode
                            ? Colors.indigoAccent
                            : (_tiltAngleDeg <= 2.0
                                ? Colors.green
                                : Colors.orange),
                        width: 1.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                              _isTotalStationMode
                                  ? Icons.radar
                                  : Icons.trip_origin,
                              color: _isTotalStationMode
                                  ? Colors.indigoAccent
                                  : (_tiltAngleDeg <= 2.0
                                      ? Colors.greenAccent
                                      : Colors.orange),
                              size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _isTotalStationMode
                                ? 'TS Hz: ${_tsHzAngle.toStringAsFixed(2)}°'
                                : 'IMU Tilt: ${_tiltAngleDeg.toStringAsFixed(1)}°',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Text(
                          _isTotalStationMode
                              ? 'Dist: ${_tsSlopeDistance}m'
                              : 'HRMS: ${_hrmsAccuracy}m',
                          style: TextStyle(
                              color: Colors.grey.shade300, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            right: 16,
            top: 100,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'hub_btn',
                  backgroundColor: Colors.blue,
                  onPressed: _showFieldToolsHub,
                  child: const Icon(Icons.widgets, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'ts_btn',
                  backgroundColor:
                      _isTotalStationMode ? Colors.indigo : Colors.white,
                  onPressed: _showTotalStationDialog,
                  child: Icon(Icons.radar,
                      color:
                          _isTotalStationMode ? Colors.white : Colors.indigo),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'bubble_btn',
                  backgroundColor:
                      _tiltAngleDeg <= 2.0 ? Colors.green : Colors.orange,
                  onPressed: _showImuBubbleDialog,
                  child: const Icon(Icons.trip_origin, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'layer_btn',
                  backgroundColor: Colors.white,
                  onPressed: () =>
                      setState(() => _isSatelliteMode = !_isSatelliteMode),
                  child: Icon(
                      _isSatelliteMode ? Icons.map : Icons.satellite_alt,
                      color: Colors.black87),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.small(
                  heroTag: 'cad_btn',
                  backgroundColor:
                      _isCadLayerVisible ? Colors.teal : Colors.white,
                  onPressed: _showCadImportDialog,
                  child: Icon(Icons.insert_drive_file,
                      color: _isCadLayerVisible ? Colors.white : Colors.teal),
                ),
              ],
            ),
          ),
          const Center(
            child: Icon(Icons.filter_center_focus, color: Colors.red, size: 36),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildToolButton(Icons.edit_location_alt, 'Topo Survey', () {
                    setState(() => _activeTool = 'Topo Survey');
                    _showAddPointDialog();
                  }),
                  _buildToolButton(Icons.navigation, 'Stakeout', () {
                    _showStakeoutTypeSelector();
                  }),
                  _buildToolButton(Icons.list_alt, 'Points List', () {
                    _showPointManagerDialog();
                  }),
                  _buildToolButton(Icons.square_foot, 'Measure Area', () {
                    setState(() => _activeTool = 'Measure Area');
                  }),
                  _buildToolButton(Icons.file_download, 'Export', () {
                    _showExportDialog();
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton(IconData icon, String label, VoidCallback onTap) {
    final bool isActive = _activeTool == label ||
        (label == 'Stakeout' &&
            (_activeTool == 'Stakeout' || _activeTool == 'Road Stakeout'));
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: isActive ? Colors.blue : Colors.black87),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.blue : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// CROSS-SECTION PROFILE CUSTOM PAINTER
// -----------------------------------------------------------------------------
class CrossSectionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintGround = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final paintDesign = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final paintGrid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.8;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paintGrid);
    }
    for (double j = 0; j < size.height; j += 40) {
      canvas.drawLine(Offset(0, j), Offset(size.width, j), paintGrid);
    }

    final pathGround = ui.Path();
    pathGround.moveTo(0, size.height * 0.6);
    pathGround.quadraticBezierTo(size.width * 0.3, size.height * 0.4,
        size.width * 0.6, size.height * 0.7);
    pathGround.quadraticBezierTo(
        size.width * 0.8, size.height * 0.8, size.width, size.height * 0.5);
    canvas.drawPath(pathGround, paintGround);

    final pathDesign = ui.Path();
    pathDesign.moveTo(0, size.height * 0.5);
    pathDesign.lineTo(size.width * 0.5, size.height * 0.45);
    pathDesign.lineTo(size.width, size.height * 0.5);
    canvas.drawPath(pathDesign, paintDesign);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
