import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/user_service.dart';
import '../theme/app_colors.dart';

/// The profile picture in the Profile header.
///
/// Shows the user's photo, or the first letter of their name when they have
/// not added one (the photo is optional). Tapping it lets them choose a
/// photo from the gallery or remove the current one.
class ProfileAvatar extends StatefulWidget {
  final String initial;

  /// Shows a message with the page's own toast style.
  final void Function(String message, {bool isError}) onMessage;

  const ProfileAvatar({
    super.key,
    required this.initial,
    required this.onMessage,
  });

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  static const double _size = 78;
  static const Color _removeRed = Color(0xFFD64545);

  final UserService _userService = UserService();

  Uint8List? _photo;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    try {
      final photo = await _userService.getProfilePhoto();
      if (!mounted) return;
      setState(() => _photo = photo);
    } catch (e) {
      // No photo, offline, or not allowed yet: keep showing the initial.
      debugPrint('PROFILE PHOTO LOAD ERROR: $e');
    }
  }

  // ---------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------

  Future<void> _openMenu() async {
    if (_busy) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.softBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.mediumGray,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.tealText,
                ),
                title: Text(
                  _photo == null ? 'Choose a photo' : 'Change photo',
                  style: TextStyle(
                    color: AppColors.navyText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => Navigator.pop(sheetContext, 'pick'),
              ),
              if (_photo != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: _removeRed,
                  ),
                  title: const Text(
                    'Remove photo',
                    style: TextStyle(
                      color: _removeRed,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.pop(sheetContext, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );

    if (action == 'pick') await _pickPhoto();
    if (action == 'remove') await _removePhoto();
  }

  Future<void> _pickPhoto() async {
    final XFile? file;
    try {
      // The picker shrinks the image, so it stays small enough for Firestore.
      file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
    } catch (e) {
      debugPrint('PROFILE PHOTO PICK ERROR: $e');
      widget.onMessage('Could not open your photos.', isError: true);
      return;
    }
    if (file == null) return; // the user closed the picker

    final bytes = await file.readAsBytes();
    if (bytes.length > UserService.maxPhotoBytes) {
      widget.onMessage(
        'This photo is too large. Please choose another one.',
        isError: true,
      );
      return;
    }

    await _run(
      () => _userService.saveProfilePhoto(bytes),
      onDone: () => _photo = bytes,
      success: 'Your profile photo has been updated.',
      failure: 'Could not save your photo. Please try again.',
    );
  }

  Future<void> _removePhoto() async {
    await _run(
      _userService.deleteProfilePhoto,
      onDone: () => _photo = null,
      success: 'Your profile photo has been removed.',
      failure: 'Could not remove your photo. Please try again.',
    );
  }

  Future<void> _run(
    Future<void> Function() task, {
    required VoidCallback onDone,
    required String success,
    required String failure,
  }) async {
    setState(() => _busy = true);
    try {
      await task();
      if (!mounted) return;
      setState(onDone);
      widget.onMessage(success);
    } catch (e) {
      debugPrint('PROFILE PHOTO SAVE ERROR: $e');
      if (mounted) widget.onMessage(failure, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------
  // UI
  // ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final photo = _photo;

    return Semantics(
      button: true,
      label: photo == null ? 'Add profile photo' : 'Change profile photo',
      child: GestureDetector(
        onTap: _openMenu,
        child: SizedBox(
          width: _size + 6,
          height: _size + 6,
          child: Stack(
            children: [
              Container(
                width: _size,
                height: _size,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.teal, AppColors.lightTeal],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: AppColors.onBrand.withValues(alpha: 0.18),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: photo != null
                    ? Image.memory(
                        photo,
                        width: _size,
                        height: _size,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Text(
                        widget.initial,
                        style: const TextStyle(
                          color: AppColors.onBrand,
                          fontSize: 35,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),

              // Small camera badge: shows the photo can be changed.
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.onBrand, width: 2),
                  ),
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF06365A),
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt_rounded,
                          size: 14,
                          color: Color(0xFF06365A),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
