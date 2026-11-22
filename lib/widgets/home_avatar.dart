import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../services/user_service.dart';
import '../theme/app_colors.dart';

/// The user's picture at the top right of Home. Tapping it opens Profile.
///
/// Shows the profile photo inside the brand gradient square, so the gradient
/// becomes a thin frame. Shows the first letter of the name instead when
/// there is no photo, while it loads, or when it cannot be read (offline).
/// The square looks the same in every state, so nothing moves when the photo
/// arrives; the photo fades in over the letter. The photo is read again each
/// time Home is back on top, for example after Profile, where it can be
/// added, changed or removed.
class HomeAvatar extends StatefulWidget {
  /// The first letter of the user's name, shown when there is no photo.
  final String initial;

  /// Opens Profile.
  final VoidCallback onOpenProfile;

  /// Only tests pass this. The app reads the photo with UserService.
  final Future<Uint8List?> Function()? loadPhoto;

  const HomeAvatar({
    super.key,
    required this.initial,
    required this.onOpenProfile,
    this.loadPhoto,
  });

  @override
  State<HomeAvatar> createState() => _HomeAvatarState();
}

class _HomeAvatarState extends State<HomeAvatar> {
  static const double _size = 46;
  static const double _radius = 16;

  // The gradient shows as a thin frame around the photo.
  static const double _frame = 2;

  Uint8List? _photo;

  // Counts the reads, so an older answer that arrives late never replaces a
  // newer one.
  int _reads = 0;

  // Whether Home was the page on top the last time this was checked.
  bool? _wasOnTop;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  // Runs again whenever another page opens on top of Home or closes.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onTop = ModalRoute.isCurrentOf(context) ?? true;
    // Back on Home: the photo may have been added, changed or removed on
    // Profile. Profile's tabs replace one page with another, so this checks
    // that Home is on top again rather than waiting for Profile to close.
    if (_wasOnTop == false && onTop) _loadPhoto();
    _wasOnTop = onTop;
  }

  Future<void> _loadPhoto() async {
    final read = ++_reads;
    try {
      // Creating the service can throw too (no Firebase app in tests), so it
      // is done inside the try. Reading throws when no one is signed in or
      // the phone is offline.
      final load = widget.loadPhoto ?? UserService().getProfilePhoto;
      final photo = await load();
      if (!mounted || read != _reads) return;
      // The same photo again, the usual case when coming back: keep the
      // picture already shown, so it is not decoded again.
      if (photo != null && _photo != null && listEquals(photo, _photo)) {
        return;
      }
      setState(() => _photo = photo);
    } catch (e) {
      // Keep what is shown: the letter at first, or the last photo read.
      debugPrint('HOME PHOTO LOAD ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final letter = Text(
      widget.initial,
      style: const TextStyle(
        color: AppColors.onBrand,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );

    // The photo is decoded smaller than it is saved, to save memory. Only
    // the width is set, so the photo keeps its shape. It is twice the width
    // of the box, so a wide photo (up to twice as wide as it is tall) is
    // still at least as tall as the box and is not enlarged and blurred to
    // fill it.
    final decodeWidth =
        ((_size - 2 * _frame) * MediaQuery.devicePixelRatioOf(context) * 2)
            .round();

    return Semantics(
      container: true,
      button: true,
      label: 'Open profile',
      child: GestureDetector(
        onTap: widget.onOpenProfile,
        // The label above is read instead of the letter or the photo.
        child: ExcludeSemantics(
          child: Container(
            width: _size,
            height: _size,
            padding: const EdgeInsets.all(_frame),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.secondaryNavy, AppColors.teal],
              ),
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(
                  color: AppColors.teal.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            alignment: Alignment.center,
            // Fades between the letter and the photo. A changed photo keeps
            // the old picture until the new one is ready (gaplessPlayback).
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: photo == null
                  ? KeyedSubtree(key: const ValueKey('letter'), child: letter)
                  : ClipRRect(
                      key: const ValueKey('photo'),
                      borderRadius: BorderRadius.circular(_radius - _frame),
                      child: Image.memory(
                        photo,
                        width: _size - 2 * _frame,
                        height: _size - 2 * _frame,
                        cacheWidth: decodeWidth,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        // A picture that cannot be shown falls back to the letter.
                        errorBuilder: (context, error, stackTrace) =>
                            Center(child: letter),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
