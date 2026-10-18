import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:frontend/components/self_bias_identification/services/profile_name_service.dart';
import 'package:frontend/components/self_bias_identification/services/profile_photo_service.dart';

/// The student's round picture: their photo, or the first letter of their id
/// when they have not added one. Updates by itself when the photo changes.
class ProfileAvatar extends StatelessWidget {
  final double size;
  final double borderWidth;
  final Color accent;

  const ProfileAvatar({
    super.key,
    this.size = 42,
    this.borderWidth = 1.5,
    this.accent = const Color(0xFF35E47B),
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
        [ProfilePhotoService.photo, ProfileNameService.name],
      ),
      builder: (context, _) {
        final Uint8List? bytes = ProfilePhotoService.photo.value;
        final shown = ProfileNameService.displayName;
        final initial = shown.isNotEmpty ? shown[0].toUpperCase() : 'U';
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withValues(alpha: 0.14),
            border: Border.all(
              color: accent.withValues(alpha: 0.5),
              width: borderWidth,
            ),
          ),
          child: bytes == null
              ? Text(
                  initial,
                  style: GoogleFonts.outfit(
                    color: accent,
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : ClipOval(
                  child: Image.memory(
                    bytes,
                    width: size - borderWidth * 2,
                    height: size - borderWidth * 2,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stack) => Text(
                      initial,
                      style: GoogleFonts.outfit(
                        color: accent,
                        fontSize: size * 0.4,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
