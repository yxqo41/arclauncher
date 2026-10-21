import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Data model for dynamic tvOS profiles.
class TvProfile {
  final String id;
  final String name;
  final int colorValue;
  final String avatarType; // 'preset', 'image', 'initials'
  final String? imagePath;
  final String? presetId;

  const TvProfile({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.avatarType,
    this.imagePath,
    this.presetId,
  });

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'avatarType': avatarType,
        'imagePath': imagePath,
        'presetId': presetId,
      };

  factory TvProfile.fromJson(Map<String, dynamic> json) => TvProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        colorValue: json['colorValue'] as int? ?? 0xFFBCE3F7,
        avatarType: json['avatarType'] as String? ?? 'initials',
        imagePath: json['imagePath'] as String?,
        presetId: json['presetId'] as String?,
      );
}

const String _kProfilesPrefsKey = 'tvos_custom_profiles_list';
const String _kLastSelectedProfileKey = 'tvos_last_selected_profile_id';

/// List of curated tvOS palette colors for setup.
const List<Color> kProfilePaletteColors = [
  Color(0xFFBCE3F7), // Sky Blue (Default Elton)
  Color(0xFFF7A2B6), // Pastel Pink (Charlene)
  Color(0xFFB9F1CD), // Mint Green (Yishuang)
  Color(0xFFFDE18C), // Lemon Yellow (Gino)
  Color(0xFFD8B4F8), // Soft Lilac
  Color(0xFFF8A88A), // Warm Peach
  Color(0xFF86E3CE), // Aqua Cyan
  Color(0xFFFF9AA2), // Coral Rose
  Color(0xFF5A78FF), // Vivid Electric Blue
  Color(0xFF38434F), // Slate Charcoal
];

/// Apple tvOS-style Profile Switcher overlay with customizable user setup.
class AppleTvProfileSelector extends StatefulWidget {
  final Function(TvProfile profile)? onProfileSelected;

  const AppleTvProfileSelector({
    super.key,
    this.onProfileSelected,
  });

  @override
  State<AppleTvProfileSelector> createState() => _AppleTvProfileSelectorState();
}

class _AppleTvProfileSelectorState extends State<AppleTvProfileSelector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;

  List<TvProfile> _profiles = [];
  bool _isLoading = true;
  bool _isSetupOpen = false;
  TvProfile? _editingProfile;

  int _focusedIndex = 0;
  List<FocusNode> _focusNodes = [];
  final FocusNode _addFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );

    _animController.forward();
    _loadProfiles();
  }

  @override
  void dispose() {
    _animController.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    _addFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_kProfilesPrefsKey);

    List<TvProfile> loaded = [];
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson) as List<dynamic>;
        loaded = decoded
            .map((e) => TvProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        loaded = [];
      }
    }

    if (!mounted) return;

    if (loaded.isEmpty) {
      // If no profiles exist yet, open the Setup Screen directly so user can configure
      setState(() {
        _profiles = [];
        _isLoading = false;
        _isSetupOpen = true;
        _editingProfile = null;
      });
    } else {
      _rebuildFocusNodes(loaded);
      setState(() {
        _profiles = loaded;
        _isLoading = false;
        _isSetupOpen = false;
        _focusedIndex = 0;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focusNodes.isNotEmpty) {
          _focusNodes[0].requestFocus();
        }
      });
    }
  }

  void _rebuildFocusNodes(List<TvProfile> profiles) {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusNodes = List.generate(
      profiles.length,
      (i) => FocusNode(debugLabel: 'profile_$i'),
    );
  }

  Future<void> _saveProfile(TvProfile newProfile) async {
    final updated = List<TvProfile>.from(_profiles);
    final existingIdx = updated.indexWhere((p) => p.id == newProfile.id);

    if (existingIdx >= 0) {
      updated[existingIdx] = newProfile;
    } else {
      updated.add(newProfile);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kProfilesPrefsKey,
      jsonEncode(updated.map((p) => p.toJson()).toList()),
    );

    _rebuildFocusNodes(updated);
    setState(() {
      _profiles = updated;
      _isSetupOpen = false;
      _editingProfile = null;
      _focusedIndex = existingIdx >= 0 ? existingIdx : updated.length - 1;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNodes.length > _focusedIndex) {
        _focusNodes[_focusedIndex].requestFocus();
      }
    });
  }

  Future<void> _deleteProfile(String profileId) async {
    final updated = _profiles.where((p) => p.id != profileId).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kProfilesPrefsKey,
      jsonEncode(updated.map((p) => p.toJson()).toList()),
    );

    _rebuildFocusNodes(updated);
    setState(() {
      _profiles = updated;
      _isSetupOpen = updated.isEmpty;
      _editingProfile = null;
      _focusedIndex = 0;
    });
  }

  void _selectProfile(TvProfile profile) {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_kLastSelectedProfileKey, profile.id);
    });

    _animController.reverse().then((_) {
      if (mounted) {
        widget.onProfileSelected?.call(profile);
      }
    });
  }

  void _openSetupModal({TvProfile? profile}) {
    setState(() {
      _editingProfile = profile;
      _isSetupOpen = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // tvOS frosted gradient background
            const _TvOsBackdrop(),

            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            else if (_isSetupOpen)
              // Setup / Profile Creation Screen
              _ProfileSetupView(
                existingProfile: _editingProfile,
                canCancel: _profiles.isNotEmpty,
                onSave: _saveProfile,
                onDelete: _editingProfile != null
                    ? () => _deleteProfile(_editingProfile!.id)
                    : null,
                onCancel: () {
                  setState(() {
                    _isSetupOpen = false;
                    _editingProfile = null;
                  });
                },
              )
            else
              // Horizontal Row of Profiles
              Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      for (int i = 0; i < _profiles.length; i++) ...[
                        _ProfileAvatarButton(
                          profile: _profiles[i],
                          focusNode: _focusNodes[i],
                          autofocus: i == _focusedIndex,
                          onFocused: () {
                            setState(() {
                              _focusedIndex = i;
                            });
                          },
                          onSelect: () => _selectProfile(_profiles[i]),
                          onLongPress: () => _openSetupModal(profile: _profiles[i]),
                        ),
                        const SizedBox(width: 32),
                      ],

                      // "+" Add Profile Button
                      _AddUserButton(
                        focusNode: _addFocusNode,
                        onFocused: () {
                          setState(() {
                            _focusedIndex = _profiles.length;
                          });
                        },
                        onSelect: () => _openSetupModal(),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Frosted Glass & Pastel Gradient background inspired by Apple tvOS
class _TvOsBackdrop extends StatelessWidget {
  const _TvOsBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.55, -0.35),
              radius: 1.45,
              colors: [
                Color(0xFFECA392), // warm peachy coral glow on top-left
                Color(0xFF90B8CF), // soft sky tone
                Color(0xFF4A7D9D), // deeper tvOS blue
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            color: Colors.black.withOpacity(0.15),
          ),
        ),
      ],
    );
  }
}

/// Setup & Profile Customization Screen
class _ProfileSetupView extends StatefulWidget {
  final TvProfile? existingProfile;
  final bool canCancel;
  final ValueChanged<TvProfile> onSave;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  const _ProfileSetupView({
    this.existingProfile,
    required this.canCancel,
    required this.onSave,
    this.onDelete,
    required this.onCancel,
  });

  @override
  State<_ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<_ProfileSetupView> {
  late final TextEditingController _nameController;
  late final TextEditingController _imagePathController;

  late Color _selectedColor;
  late String _avatarType; // 'preset', 'image', 'initials'
  String _selectedPreset = 'elton';

  final List<String> _availablePresets = const [
    'elton',
    'charlene',
    'yishuang',
    'gino',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.existingProfile;
    _nameController = TextEditingController(text: p?.name ?? '');
    _imagePathController = TextEditingController(text: p?.imagePath ?? '');

    _selectedColor = p != null ? p.color : kProfilePaletteColors[0];
    _avatarType = p?.avatarType ?? 'preset';
    _selectedPreset = p?.presetId ?? 'elton';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _imagePathController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final profile = TvProfile(
      id: widget.existingProfile?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      colorValue: _selectedColor.value,
      avatarType: _avatarType,
      imagePath: _avatarType == 'image' ? _imagePathController.text.trim() : null,
      presetId: _avatarType == 'preset' ? _selectedPreset : null,
    );

    widget.onSave(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        decoration: BoxDecoration(
          color: const Color(0xFF1E2631).withOpacity(0.92),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.18), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 36,
              spreadRadius: 4,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Header
              Text(
                widget.existingProfile != null ? 'Edit Profile' : 'Set Up Your Profile',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 18),

              // Live Avatar Preview
              _buildLivePreview(),
              const SizedBox(height: 22),

              // Name TextField
              TextField(
                controller: _nameController,
                style: const TextStyle(color: Colors.white, fontSize: 17),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Profile Name',
                  labelStyle: TextStyle(color: Colors.white.withOpacity(0.75)),
                  prefixIcon: const Icon(Icons.person_outline, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.08),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Color Palette Picker
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose Background Color',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildColorPalette(),
              const SizedBox(height: 20),

              // Avatar Type Selector Tabs
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose Avatar Style',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildAvatarTypeSelector(),
              const SizedBox(height: 14),

              // Content based on Avatar Type
              if (_avatarType == 'preset')
                _buildPresetSelector()
              else if (_avatarType == 'image')
                _buildImagePathInput(),

              const SizedBox(height: 28),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (widget.canCancel)
                    TextButton(
                      onPressed: widget.onCancel,
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 16),
                      ),
                    ),
                  if (widget.onDelete != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: widget.onDelete,
                      child: const Text(
                        'Delete',
                        style: TextStyle(color: Colors.redAccent, fontSize: 16),
                      ),
                    ),
                  ],
                  const SizedBox(width: 14),
                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF1E2631),
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Save Profile',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLivePreview() {
    final previewProfile = TvProfile(
      id: 'preview',
      name: _nameController.text.trim().isEmpty ? 'Your Name' : _nameController.text.trim(),
      colorValue: _selectedColor.value,
      avatarType: _avatarType,
      imagePath: _imagePathController.text.trim(),
      presetId: _selectedPreset,
    );

    return Column(
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _selectedColor,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.4),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: _buildAvatarContent(previewProfile, 110),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          previewProfile.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildColorPalette() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final color in kProfilePaletteColors) ...[
            GestureColorTile(
              color: color,
              isSelected: _selectedColor.value == color.value,
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
              },
            ),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatarTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildTabItem('Memoji Preset', 'preset'),
          _buildTabItem('Initials Badge', 'initials'),
          _buildTabItem('Custom Image / URL', 'image'),
        ],
      ),
    );
  }

  Widget _buildTabItem(String label, String type) {
    final isSelected = _avatarType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _avatarType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF1E2631) : Colors.white70,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetSelector() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in _availablePresets) ...[
            GestureDetector(
              onTap: () => setState(() => _selectedPreset = preset),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _selectedPreset == preset ? Colors.white : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _selectedColor.withOpacity(0.65),
                  ),
                  child: ClipOval(
                    child: _CharacterAvatarPainterWidget(type: preset, size: 58),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagePathInput() {
    return TextField(
      controller: _imagePathController,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: 'Local File Path or Image URL',
        hintText: 'e.g. /sdcard/Pictures/avatar.png or https://...',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.75)),
        prefixIcon: const Icon(Icons.image_outlined, color: Colors.white70),
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Interactive Color Circle Button with TV focus support
class GestureColorTile extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const GestureColorTile({
    super.key,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected || isFocused ? Colors.white : Colors.transparent,
                  width: isSelected ? 3.5 : 2.0,
                ),
                boxShadow: isSelected || isFocused
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.6),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              child: isSelected
                  ? const Center(
                      child: Icon(Icons.check, size: 20, color: Colors.black87),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }
}

/// Helper function to build avatar image, monogram initials, or Memoji preset
Widget _buildAvatarContent(TvProfile profile, double size) {
  if (profile.avatarType == 'image' &&
      profile.imagePath != null &&
      profile.imagePath!.isNotEmpty) {
    final path = profile.imagePath!;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitials(profile.name, size),
      );
    } else {
      final file = File(path);
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildInitials(profile.name, size),
      );
    }
  } else if (profile.avatarType == 'preset' && profile.presetId != null) {
    return _CharacterAvatarPainterWidget(type: profile.presetId!, size: size);
  } else {
    return _buildInitials(profile.name, size);
  }
}

Widget _buildInitials(String name, double size) {
  final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
  return Center(
    child: Text(
      initial,
      style: TextStyle(
        color: Colors.white,
        fontSize: size * 0.44,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    ),
  );
}

/// Individual Profile button with tvOS focus ring, scale animation, and name
class _ProfileAvatarButton extends StatefulWidget {
  final TvProfile profile;
  final FocusNode focusNode;
  final bool autofocus;
  final VoidCallback onFocused;
  final VoidCallback onSelect;
  final VoidCallback onLongPress;

  const _ProfileAvatarButton({
    required this.profile,
    required this.focusNode,
    required this.autofocus,
    required this.onFocused,
    required this.onSelect,
    required this.onLongPress,
  });

  @override
  State<_ProfileAvatarButton> createState() => _ProfileAvatarButtonState();
}

class _ProfileAvatarButtonState extends State<_ProfileAvatarButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _isFocused = widget.autofocus;
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      final focused = widget.focusNode.hasFocus;
      if (focused != _isFocused) {
        setState(() {
          _isFocused = focused;
        });
        if (focused) {
          widget.onFocused();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const double avatarSize = 138;

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _isFocused ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Circular Avatar with Glowing Focus Ring
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.profile.color,
                  border: _isFocused
                      ? Border.all(color: Colors.white.withOpacity(0.95), width: 3.5)
                      : Border.all(color: Colors.transparent, width: 3.5),
                  boxShadow: _isFocused
                      ? [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.45),
                            blurRadius: 22,
                            spreadRadius: 3,
                          ),
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                child: ClipOval(
                  child: _buildAvatarContent(widget.profile, avatarSize),
                ),
              ),
              const SizedBox(height: 14),

              // Profile Name
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: _isFocused ? Colors.white : Colors.white.withOpacity(0.78),
                  fontSize: 18,
                  fontWeight: _isFocused ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: 0.3,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(widget.profile.name),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "+" Add Profile button in frosted translucent circle
class _AddUserButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onFocused;
  final VoidCallback onSelect;

  const _AddUserButton({
    required this.focusNode,
    required this.onFocused,
    required this.onSelect,
  });

  @override
  State<_AddUserButton> createState() => _AddUserButtonState();
}

class _AddUserButtonState extends State<_AddUserButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      final focused = widget.focusNode.hasFocus;
      if (focused != _isFocused) {
        setState(() {
          _isFocused = focused;
        });
        if (focused) {
          widget.onFocused();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const double avatarSize = 138;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _isFocused ? 1.15 : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isFocused
                      ? Colors.white.withOpacity(0.35)
                      : Colors.white.withOpacity(0.20),
                  border: _isFocused
                      ? Border.all(color: Colors.white, width: 3.5)
                      : Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
                  boxShadow: _isFocused
                      ? [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.40),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Icon(
                    Icons.add,
                    size: 52,
                    color: _isFocused
                        ? Colors.white
                        : const Color(0xFF1E3A4B).withOpacity(0.75),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Add User',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom Canvas Painter rendering Apple Memoji-style avatars
class _CharacterAvatarPainterWidget extends StatelessWidget {
  final String type;
  final double size;

  const _CharacterAvatarPainterWidget({
    required this.type,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _MemojiPainter(type: type),
    );
  }
}

class _MemojiPainter extends CustomPainter {
  final String type;

  const _MemojiPainter({required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    switch (type) {
      case 'charlene':
        _drawCharlene(canvas, size, cx, cy);
        break;
      case 'elton':
        _drawElton(canvas, size, cx, cy);
        break;
      case 'yishuang':
        _drawYishuang(canvas, size, cx, cy);
        break;
      case 'gino':
        _drawGino(canvas, size, cx, cy);
        break;
      default:
        _drawElton(canvas, size, cx, cy);
    }
  }

  void _drawCharlene(Canvas canvas, Size size, double cx, double cy) {
    final hairPaint = Paint()..color = const Color(0xFF1F1D1D);
    canvas.drawCircle(Offset(cx + 36, cy + 24), 22, hairPaint);

    final earringPaint = Paint()..color = const Color(0xFFE22D3E);
    canvas.drawCircle(Offset(cx - 38, cy + 12), 4.5, earringPaint);
    canvas.drawCircle(Offset(cx + 38, cy + 12), 4.5, earringPaint);

    final skinPaint = Paint()..color = const Color(0xFFF9D3B4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 2), width: 72, height: 80),
      skinPaint,
    );

    final hairPath = Path()
      ..moveTo(cx - 36, cy + 4)
      ..cubicTo(cx - 38, cy - 38, cx + 38, cy - 38, cx + 36, cy + 4)
      ..cubicTo(cx + 25, cy - 18, cx - 25, cy - 18, cx - 36, cy + 4)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    final eyePaint = Paint()..color = const Color(0xFF261D1A);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 15, cy), width: 8, height: 11),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 15, cy), width: 8, height: 11),
      eyePaint,
    );

    final browPaint = Paint()
      ..color = const Color(0xFF3B2F2F)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - 15, cy - 10), width: 14, height: 8),
      3.14,
      3.14,
      false,
      browPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx + 15, cy - 10), width: 14, height: 8),
      3.14,
      3.14,
      false,
      browPaint,
    );

    final lipPaint = Paint()..color = const Color(0xFFD63B48);
    final smilePath = Path()
      ..moveTo(cx - 12, cy + 22)
      ..quadraticBezierTo(cx, cy + 30, cx + 12, cy + 22)
      ..quadraticBezierTo(cx, cy + 25, cx - 12, cy + 22)
      ..close();
    canvas.drawPath(smilePath, lipPaint);
  }

  void _drawElton(Canvas canvas, Size size, double cx, double cy) {
    final skinPaint = Paint()..color = const Color(0xFFFCD7BA);

    canvas.drawCircle(Offset(cx - 37, cy + 2), 10, skinPaint);
    canvas.drawCircle(Offset(cx + 37, cy + 2), 10, skinPaint);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 4), width: 72, height: 78),
      skinPaint,
    );

    final hairPaint = Paint()..color = const Color(0xFF231F20);
    final hairPath = Path()
      ..moveTo(cx - 36, cy - 8)
      ..cubicTo(cx - 32, cy - 42, cx - 10, cy - 46, cx + 5, cy - 40)
      ..cubicTo(cx + 22, cy - 44, cx + 38, cy - 25, cx + 36, cy - 8)
      ..cubicTo(cx + 18, cy - 18, cx - 18, cy - 18, cx - 36, cy - 8)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    final eyePaint = Paint()..color = const Color(0xFF261D1A);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 15, cy), width: 9, height: 11),
      eyePaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 15, cy), width: 9, height: 11),
      eyePaint,
    );

    final catchlight = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - 13, cy - 2), 2, catchlight);
    canvas.drawCircle(Offset(cx + 17, cy - 2), 2, catchlight);

    final browPaint = Paint()
      ..color = const Color(0xFF231F20)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - 15, cy - 11), width: 16, height: 9),
      3.14,
      3.14,
      false,
      browPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx + 15, cy - 11), width: 16, height: 9),
      3.14,
      3.14,
      false,
      browPaint,
    );

    final mouthPaint = Paint()..color = const Color(0xFF6B1D1D);
    final teethPaint = Paint()..color = Colors.white;

    final mouthRect = Rect.fromCenter(
      center: Offset(cx, cy + 22),
      width: 30,
      height: 18,
    );
    canvas.drawArc(mouthRect, 0, 3.14, true, mouthPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 11, cy + 18, 22, 6),
        const Radius.circular(3),
      ),
      teethPaint,
    );
  }

  void _drawYishuang(Canvas canvas, Size size, double cx, double cy) {
    final skinPaint = Paint()..color = const Color(0xFFFBD6B8);

    canvas.drawCircle(Offset(cx - 36, cy + 4), 9, skinPaint);
    canvas.drawCircle(Offset(cx + 36, cy + 4), 9, skinPaint);

    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 4), width: 70, height: 76),
      skinPaint,
    );

    final hairPaint = Paint()..color = const Color(0xFFB5B7B9);
    final hairPath = Path()
      ..moveTo(cx - 35, cy - 8)
      ..cubicTo(cx - 28, cy - 40, cx, cy - 44, cx + 22, cy - 38)
      ..cubicTo(cx + 36, cy - 32, cx + 36, cy - 18, cx + 35, cy - 8)
      ..cubicTo(cx + 18, cy - 20, cx - 18, cy - 20, cx - 35, cy - 8)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    final eyeArcPaint = Paint()
      ..color = const Color(0xFF261D1A)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - 15, cy), width: 14, height: 10),
      3.14,
      3.14,
      false,
      eyeArcPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx + 15, cy), width: 14, height: 10),
      3.14,
      3.14,
      false,
      eyeArcPaint,
    );

    final mouthPaint = Paint()..color = const Color(0xFF7A2020);
    final mouthRect = Rect.fromCenter(
      center: Offset(cx, cy + 22),
      width: 28,
      height: 16,
    );
    canvas.drawArc(mouthRect, 0, 3.14, true, mouthPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 10, cy + 18, 20, 5),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white,
    );
  }

  void _drawGino(Canvas canvas, Size size, double cx, double cy) {
    final hairPaint = Paint()..color = const Color(0xFF211D1C);

    canvas.drawCircle(Offset(cx - 36, cy + 24), 8, hairPaint);
    canvas.drawCircle(Offset(cx - 34, cy + 38), 7, hairPaint);
    canvas.drawCircle(Offset(cx - 30, cy + 50), 6, hairPaint);

    canvas.drawCircle(Offset(cx + 36, cy + 24), 8, hairPaint);
    canvas.drawCircle(Offset(cx + 34, cy + 38), 7, hairPaint);
    canvas.drawCircle(Offset(cx + 30, cy + 50), 6, hairPaint);

    final skinPaint = Paint()..color = const Color(0xFFFAD7BC);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 4), width: 70, height: 76),
      skinPaint,
    );

    final hairPath = Path()
      ..moveTo(cx - 35, cy - 2)
      ..cubicTo(cx - 32, cy - 36, cx - 12, cy - 38, cx, cy - 26)
      ..cubicTo(cx + 12, cy - 38, cx + 32, cy - 36, cx + 35, cy - 2)
      ..cubicTo(cx + 20, cy - 14, cx - 20, cy - 14, cx - 35, cy - 2)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    final eyePaint = Paint()..color = const Color(0xFF261D1A);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 15, cy + 1), width: 8, height: 10),
      eyePaint,
    );

    final winkPaint = Paint()
      ..color = const Color(0xFF261D1A)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx - 15, cy + 2), width: 14, height: 8),
      3.14,
      3.14,
      false,
      winkPaint,
    );

    final mouthPaint = Paint()..color = const Color(0xFF6B1D1D);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(cx, cy + 22), width: 24, height: 16),
      0,
      3.14,
      true,
      mouthPaint,
    );

    final tonguePaint = Paint()..color = const Color(0xFFEB687A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx + 2, cy + 24, 12, 14),
        const Radius.circular(6),
      ),
      tonguePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _MemojiPainter oldDelegate) =>
      oldDelegate.type != type;
}
