import 'package:flutter/material.dart';
import 'package:medito/widgets/inputs/wheel_picker.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

@UseCase(name: 'Minutes', type: WheelPicker)
Widget minutesWheelPicker(BuildContext context) {
  return const Padding(padding: EdgeInsets.all(24), child: _MinutesWheel());
}

class _MinutesWheel extends StatefulWidget {
  const _MinutesWheel();

  @override
  State<_MinutesWheel> createState() => _MinutesWheelState();
}

class _MinutesWheelState extends State<_MinutesWheel> {
  int _minutes = 10;

  @override
  Widget build(BuildContext context) {
    return WheelPicker<int>(
      label: 'Duration',
      options: [
        for (var m = 1; m <= 60; m++)
          WheelOption(
            m,
            '$m min',
            semanticsLabel: m == 1 ? '1 minute' : '$m minutes',
          ),
      ],
      value: _minutes,
      onChanged: (v) => setState(() => _minutes = v),
      parseEntry: (text) {
        final v = int.tryParse(text);
        return v != null && v >= 1 && v <= 60 ? v : null;
      },
      entryHint: '1 to 60 minutes',
    );
  }
}
