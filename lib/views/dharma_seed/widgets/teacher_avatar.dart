import 'package:flutter/material.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// A teacher's photo in a circle, or calm generated artwork seeded by their
/// name when Dharma Seed has no photo.
class TeacherAvatar extends StatelessWidget {
  const TeacherAvatar({
    super.key,
    required this.name,
    required this.photoUrl,
    this.size = 72,
  });

  final String name;
  final String photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: NetworkImageWidget(
          url: photoUrl,
          seed: name,
          shouldCache: true,
          alignment: Alignment.topCenter,
        ),
      ),
    );
  }
}
