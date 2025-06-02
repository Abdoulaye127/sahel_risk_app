import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:csv/csv.dart';

class SahelRiskApp extends StatefulWidget {
  const SahelRiskApp({super.key});

  @override
  State<SahelRiskApp> createState() => _SahelRiskAppState();
}

class _SahelRiskAppState extends State<SahelRiskApp> {
  String selectedLayer = '';
  Map<String, double> regionValues = {};
  Map<String, Map<String, double>> allLayers = {};

  @override
  void initState() {
    super.initState();
    _loadAllLayers();
  }

  String normalize(String input) {
    return input
        .toUpperCase()
        .replaceAll('É', 'E')
        .replaceAll('È', 'E')
        .replaceAll('Ê', 'E')
        .replaceAll('Ô', 'O')
        .replaceAll('Â', 'A')
        .replaceAll('Î', 'I')
        .replaceAll('Û', 'U')
        .replaceAll('À', 'A')
        .replaceAll('Ç', 'C')
        .replaceAll('’', '')
        .replaceAll("'", '')
        .replaceAll('-', ' ')
        .replaceAll('.', '')
        .replaceAll('Ã', 'E')
        .replaceAll('Ã¨', 'E')
        .replaceAll('Ã©', 'E')
        .replaceAll('Ã´', 'O')
        .replaceAll('Ãª', 'E')
        .replaceAll('Ã ', 'A')
        .replaceAll('Ã', 'A')
        .trim();
  }

  Future<void> _loadAllLayers() async {
    final layers = ['hazard', 'exposure', 'vulnerability', 'lcc'];
    for (final layer in layers) {
      final raw = await rootBundle.loadString('assets/data/$layer.csv');
      final rows = const CsvToListConverter().convert(raw, eol: '\n');
      final Map<String, double> values = {};
      for (var row in rows.skip(1)) {
        if (row.length < 2) continue;
        final region = normalize(row[0].toString());
        final value = double.tryParse(row[1].toString()) ?? 0.0;
        values[region] = value.clamp(0.0, 1.0);
      }
      allLayers[layer] = values;
    }
  }

  Future<void> _loadCSVLayer(String layer) async {
    setState(() {
      selectedLayer = layer;
      if (layer.toLowerCase() == 'risk') {
        final risk = <String, double>{};
        allLayers['hazard']?.forEach((region, h) {
          final v = allLayers['vulnerability']?[region] ?? 0;
          final e = allLayers['exposure']?[region] ?? 0;
          final l = allLayers['lcc']?[region] ?? 0;
          risk[region] = (h * v * e * l).clamp(0.0, 1.0);
        });
        regionValues = risk;
      } else {
        regionValues = allLayers[layer.toLowerCase()] ?? {};
      }
    });
  }

  Color classifyColor(double value) {
    if (value <= 0.2) return Colors.green;
    if (value <= 0.5) return Colors.yellow;
    if (value <= 0.75) return Colors.orange;
    return Colors.red;
  }

  Future<List<Polygon>> _loadPolygons() async {
    final geojsonRaw = await rootBundle.loadString('assets/geojson/SAHEL_Risk.geojson');
    final geojson = json.decode(geojsonRaw);
    List<Polygon> polygons = [];

    for (var feature in geojson['features']) {
      final rawName = feature['properties']['region'] ?? feature['properties']['Region'] ?? feature['properties']['NAME_1'];
      final regionName = normalize(rawName.toString());
      final double value = regionValues[regionName] ?? -1.0;

      if (value == -1.0) continue;
      final geometry = feature['geometry'];
      final Color color = classifyColor(value).withOpacity(0.7);

      if (geometry['type'] == 'MultiPolygon') {
        for (var polygon in geometry['coordinates']) {
          final points = (polygon[0] as List)
              .map<LatLng>((c) => LatLng(c[1], c[0]))
              .toList();
          polygons.add(_buildPolygon(points, color));
        }
      } else if (geometry['type'] == 'Polygon') {
        final points = (geometry['coordinates'][0] as List)
            .map<LatLng>((c) => LatLng(c[1], c[0]))
            .toList();
        polygons.add(_buildPolygon(points, color));
      }
    }
    return polygons;
  }

  Polygon _buildPolygon(List<LatLng> points, Color fillColor) {
    return Polygon(
      points: points,
      color: fillColor,
      borderColor: Colors.black,
      borderStrokeWidth: 1,
      isFilled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
            width: double.infinity,
            color: Colors.blue.shade900,
            child: Column(
              children: [
                const Text(
                  "Multi-Hazard Risk Assessment",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  "Forecast extreme heat, drought, and wildfire risk across\nWest Africa using advanced climate data.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                Wrap(
                  spacing: 12,
                  children: [
                    for (var layer in ['Hazard', 'Exposure', 'Vulnerability', 'LCC', 'Risk'])
                      ElevatedButton(
                        onPressed: () => _loadCSVLayer(layer),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: selectedLayer == layer ? Colors.white : Colors.white70,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(layer),
                      ),
                  ],
                )
              ],
            ),
          ),
          if (selectedLayer.isNotEmpty)
            Expanded(
              child: FutureBuilder<List<Polygon>>(
                future: _loadPolygons(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(14.0, 0.0),
                      initialZoom: 5.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.sahel_risk_app',
                      ),
                      PolygonLayer(polygons: snapshot.data!),
                    ],
                  );
                },
              ),
            )
        ],
      ),
    );
  }
}
