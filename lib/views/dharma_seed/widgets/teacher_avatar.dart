import 'package:flutter/material.dart';
import 'package:medito/widgets/cover_art.dart';
import 'package:medito/widgets/network_image_widget.dart';

/// A teacher's photo in a circle, or generated art for their id when they
/// have no photo.
class TeacherAvatar extends StatelessWidget {
  const TeacherAvatar({
    super.key,
    required this.id,
    required this.name,
    required this.photoUrl,
    this.size = 72,
  });

  final String id;
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
          art: teacherArt(id),
          shouldCache: true,
          alignment: Alignment.topCenter,
        ),
      ),
    );
  }
}
