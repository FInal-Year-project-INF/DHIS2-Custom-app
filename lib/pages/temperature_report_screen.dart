import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/dhis2_service.dart';

class TemperatureReportScreen extends StatefulWidget {
  const TemperatureReportScreen({super.key});

  @override
  TemperatureReportScreenState createState() => TemperatureReportScreenState();
}

class TemperatureReportScreenState extends State<TemperatureReportScreen> {
  final _dhis2Service = DHIS2Service();
  bool _isLoading = true;
  String _errorMessage = '';

  List<Map<String, dynamic>> _patients = [];
  Map<String, List<Map<String, dynamic>>> _temperatureData = {};
  List<String> _selectedPatientIds = [];

  @override
  void initState() {
    super.initState();
    _loadPatients();
  }

  Future<void> _loadPatients() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final orgUnitId = authProvider.organizationUnit;

      if (orgUnitId.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No organization unit selected.';
        });
        return;
      }

      final patients = await _dhis2Service.getPatients(orgUnitId: orgUnitId);
      final patientsWithTemperature = patients.where((patient) {
        final attributes = patient['attributes'] as Map<String, String>;
        return attributes.containsKey('temperature') &&
            attributes['temperature'] != null &&
            attributes['temperature']!.isNotEmpty;
      }).toList();

      Map<String, List<Map<String, dynamic>>> temperatureData = {};

      for (var patient in patientsWithTemperature) {
        final id = patient['id'] as String;
        final attributes = patient['attributes'] as Map<String, String>;
        final tempValue = attributes['temperature']!;
        final temperature = double.tryParse(tempValue);

        if (temperature != null) {
          temperatureData[id] = [
            {
              'date': DateTime.now().toIso8601String(),
              'temperature': temperature,
            },
          ];

          try {
            final history = await _dhis2Service.getPatientTemperatureHistory(id);
            if (history.isNotEmpty) {
              temperatureData[id] = history;
            }
          } catch (_) {}
        }
      }

      final patientsWithHistory = patientsWithTemperature.where((p) {
        final id = p['id'] as String;
        return temperatureData.containsKey(id) && temperatureData[id]!.isNotEmpty;
      }).toList();

      setState(() {
        _patients = patientsWithHistory;
        _temperatureData = temperatureData;
        _isLoading = false;

        if (_patients.isNotEmpty) {
          _selectedPatientIds = [_patients.first['id']];
        }
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load patient data: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DHIS2 Reports')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(child: Text(_errorMessage))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildPatientSelector(),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: _buildTemperatureKey(),
                    ),
                    Expanded(
                      child: _selectedPatientIds.isNotEmpty
                          ? _buildTemperatureChart()
                          : const Center(child: Text('Select patients to view temperature data')),
                    ),
                  ],
                ),
    );
  }

  Widget _buildPatientSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ElevatedButton(
          onPressed: _showMultiSelectPatientDialog,
          child: const Text('Select patients'),
        ),
        const SizedBox(height: 12),
        if (_selectedPatientIds.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedPatientIds.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final id = _selectedPatientIds[index];
                final patient = _patients.firstWhere((p) => p['id'] == id, orElse: () => {});
                final name = patient['displayName'] ?? 'Unknown';

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: getPatientColor(id),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(name, style: const TextStyle(fontSize: 14)),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildTemperatureKey() {
    // Key for temperature ranges
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.grey[100],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _tempKeyBox('Below 35°C', 'Concerning', Colors.red[200]!),
              const SizedBox(width: 12),
              _tempKeyBox('35–37.5°C', 'Normal', Colors.green[300]!),
              const SizedBox(width: 12),
              _tempKeyBox('37.6–38.9°C', 'Mild fever', Colors.orange[300]!),
              const SizedBox(width: 12),
              _tempKeyBox('39°C and above', 'High fever', Colors.red[700]!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tempKeyBox(String range, String meaning, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 16, height: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(range, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text(meaning, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ],
    );
  }

  void _showMultiSelectPatientDialog() {
    // Use a temp list for selection in the modal
    List<String> tempSelectedIds = List<String>.from(_selectedPatientIds);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Select Patients',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          controller: scrollController,
                          itemCount: _patients.length,
                          itemBuilder: (context, index) {
                            final patient = _patients[index];
                            final id = patient['id'];
                            final name = patient['displayName'] ?? 'Unknown';

                            return CheckboxListTile(
                              title: Text(name),
                              value: tempSelectedIds.contains(id),
                              activeColor: getPatientColor(id),
                              onChanged: (bool? selected) {
                                setModalState(() {
                                  if (selected == true) {
                                    tempSelectedIds.add(id);
                                  } else {
                                    tempSelectedIds.remove(id);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _selectedPatientIds = List<String>.from(tempSelectedIds);
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  /// This function maps temperature to the key color.
  Color getTempDotColor(double temp) {
    if (temp < 35) {
      return Colors.red[200]!;
    } else if (temp <= 37.5) {
      return Colors.green[300]!;
    } else if (temp <= 38.9) {
      return Colors.orange[300]!;
    } else {
      return Colors.red[700]!;
    }
  }

  Widget _buildTemperatureChart() {
    List<LineChartBarData> lines = [];

    for (final patientId in _selectedPatientIds) {
      final readings = _temperatureData[patientId];
      if (readings == null || readings.isEmpty) continue;

      readings.sort((a, b) => a['date'].compareTo(b['date']));
      final spots = <FlSpot>[];

      for (int i = 0; i < readings.length; i++) {
        final temp = readings[i]['temperature'];
        double y;
        if (temp is num) {
          y = temp.toDouble();
        } else if (temp is String) {
          y = double.tryParse(temp) ?? 0;
        } else {
          y = 0;
        }
        spots.add(FlSpot(i.toDouble(), y));
      }

      lines.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: getPatientColor(patientId),
        barWidth: 3,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) {
            return FlDotCirclePainter(
              radius: 4,
              color: getTempDotColor(spot.y),
              strokeWidth: 1.5,
              strokeColor: Colors.black,
            );
          },
        ),
        belowBarData: BarAreaData(show: false),
      ));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            child: LineChart(
              LineChartData(
                lineBarsData: lines,
                minY: 30,
                maxY: 40,
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1.5,
                      getTitlesWidget: (value, _) => Text('${value.toStringAsFixed(1)}°C'),
                    ),
                  ),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: _selectedPatientIds.map((id) {
              final patient = _patients.firstWhere((p) => p['id'] == id, orElse: () => {});
              final name = patient['displayName'] ?? 'Unknown';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: getPatientColor(id),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(name, style: const TextStyle(fontSize: 12)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color getPatientColor(String patientId) {
    final index = _selectedPatientIds.indexOf(patientId);
    return Colors.primaries[index % Colors.primaries.length];
  }
}


