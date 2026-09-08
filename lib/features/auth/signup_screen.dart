import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:storage_client/storage_client.dart' show FileOptions;
import '../../core/theme/app_theme.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/birr_text_field.dart';
import '../../core/widgets/document_upload_card.dart';

enum SignupRole { user, vehicleProvider, serviceProvider }

class SignupScreen extends ConsumerStatefulWidget {
  final SignupRole role;
  const SignupScreen({super.key, required this.role});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _error;

  File? _nationalIdImage;
  File? _licenseImage;
  bool _uploadingDocs = false;
  String? _uploadError;

  final _picker = ImagePicker();
  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _nationalIdController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isProvider =>
      widget.role == SignupRole.vehicleProvider ||
      widget.role == SignupRole.serviceProvider;

  String get _roleName {
    switch (widget.role) {
      case SignupRole.user:
        return 'User';
      case SignupRole.vehicleProvider:
        return 'Vehicle Provider';
      case SignupRole.serviceProvider:
        return 'Service Provider';
    }
  }

  String get _providerType {
    switch (widget.role) {
      case SignupRole.vehicleProvider:
        return 'VEHICLE_PROVIDER';
      case SignupRole.serviceProvider:
        return 'SERVICE_PROVIDER';
      default:
        return '';
    }
  }

  Future<void> _pickImage(ImageSource source, bool isNationalId) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked != null) {
        final file = File(picked.path);
        final size = await file.length();
        if (size > 10 * 1024 * 1024) {
          setState(() => _uploadError = 'Image must be under 10 MB');
          return;
        }
        setState(() {
          if (isNationalId) {
            _nationalIdImage = file;
          } else {
            _licenseImage = file;
          }
          _uploadError = null;
        });
      }
    } catch (e) {
      setState(() => _uploadError = 'Failed to pick image');
    }
  }

  void _showImagePicker(bool isNationalId) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera, isNationalId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery, isNationalId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadDocument(File file, String bucket, String path) async {
    try {
      await _supabase.storage.from(bucket).upload(path, file,
          fileOptions: const FileOptions(upsert: true));
      return path;
    } catch (e) {
      return null;
    }
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isProvider) {
      if (_nationalIdImage == null) {
        setState(() => _uploadError = 'National ID image is required');
        return;
      }
      if (_licenseImage == null) {
        setState(() => _uploadError = _roleName == 'Vehicle Provider'
            ? 'Driving license image is required'
            : 'Trading license image is required');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _uploadError = null;
    });

    try {
      if (_isProvider) {
        await ref.read(authProvider.notifier).signUpAsProvider(
              phone: _phoneController.text.trim(),
              password: _passwordController.text,
              businessName: _nameController.text.trim(),
              ownerNationalId: _nationalIdController.text.trim(),
              providerType: _providerType,
            );

        // Upload documents after account is created
        final userId = _supabase.auth.currentUser?.id;
        if (userId != null) {
          setState(() => _uploadingDocs = true);
          final nationalIdPath =
              '$userId/national_id_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final licensePath =
              '$userId/license_${DateTime.now().millisecondsSinceEpoch}.jpg';

          await _uploadDocument(
              _nationalIdImage!, 'user-documents', nationalIdPath);
          await _uploadDocument(
              _licenseImage!, 'user-documents', licensePath);

          // Record documents
          await _supabase.from('user_documents').insert([
            {
              'user_id': userId,
              'document_type': 'NATIONAL_ID',
              'storage_path': nationalIdPath,
            },
            {
              'user_id': userId,
              'document_type': _roleName == 'Vehicle Provider'
                  ? 'DRIVING_LICENSE'
                  : 'TRADE_LICENSE',
              'storage_path': licensePath,
            },
          ]);
        }
      } else {
        await ref.read(authProvider.notifier).signUp(
              phone: _phoneController.text.trim(),
              password: _passwordController.text,
              fullName: _nameController.text.trim(),
              nationalId: _nationalIdController.text.trim(),
              role: AppUserRole.user,
            );
      }

      if (mounted) {
        context.go('/pending-approval');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _uploadingDocs = false;
          _error = _friendlyError(e.toString());
        });
      }
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('already registered') ||
        raw.contains('already exists') ||
        raw.contains('duplicate')) {
      return 'An account with this phone number already exists.';
    }
    if (raw.contains('Password should be at least')) {
      return 'Password must be at least 6 characters.';
    }
    if (raw.contains('network') || raw.contains('SocketException')) {
      return 'Network error. Please check your connection.';
    }
    return 'Registration failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$_roleName Registration'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => context.go('/role-select'),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 24),
                  if (_isProvider) ...[
                    _buildDocumentSection(),
                    const SizedBox(height: 20),
                  ],
                  _buildFormFields(),
                  const SizedBox(height: 12),
                  if (_uploadError != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_uploadError!,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.error)),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.error)),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: PrimaryButton(
                      label: _isProvider ? 'SUBMIT APPLICATION' : 'CREATE ACCOUNT',
                      isLoading: _isLoading,
                      onPressed: _handleSignup,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          if (_isLoading || _uploadingDocs)
            Container(
              color: Colors.black26,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                          color: AppTheme.primaryGreen),
                      const SizedBox(height: 16),
                      Text(
                        _uploadingDocs
                            ? 'Uploading documents...'
                            : 'Creating account...',
                        style: const TextStyle(
                            fontSize: 14, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(
            _isProvider ? Icons.storefront : Icons.person_add_outlined,
            color: AppTheme.primaryGreen,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Register as $_roleName',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  _isProvider
                      ? 'Your application will be reviewed by our team before activation.'
                      : 'Create your account to start using 5BIRR.',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Required Documents',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 4),
        const Text('Upload clear photos of your documents',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        const SizedBox(height: 12),
        DocumentUploadCard(
          title: 'National ID',
          subtitle: 'Clear photo of front side',
          file: _nationalIdImage,
          onPick: () => _showImagePicker(true),
          onRemove: () => setState(() => _nationalIdImage = null),
        ),
        const SizedBox(height: 12),
        DocumentUploadCard(
          title: _roleName == 'Vehicle Provider'
              ? 'Driving License'
              : 'Trading License',
          subtitle: _roleName == 'Vehicle Provider'
              ? 'Updated driving license'
              : 'Valid trading license',
          file: _licenseImage,
          onPick: () => _showImagePicker(false),
          onRemove: () => setState(() => _licenseImage = null),
        ),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        BirrTextField(
          label: _isProvider ? 'Business / Owner Name' : 'Full Name',
          controller: _nameController,
          textInputAction: TextInputAction.next,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Name is required';
            if (v.trim().length < 2) return 'Name is too short';
            return null;
          },
        ),
        if (_isProvider) ...[
          const SizedBox(height: 16),
          BirrTextField(
            label: 'Phone Number',
            hint: '+251 9XX XXX XXX',
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Phone number is required';
              }
              return null;
            },
          ),
        ],
        if (!_isProvider) ...[
          const SizedBox(height: 16),
          BirrTextField(
            label: 'Phone Number',
            hint: '+251 9XX XXX XXX',
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'Phone number is required';
              }
              return null;
            },
          ),
        ],
        const SizedBox(height: 16),
        BirrTextField(
          label: 'National ID Number',
          controller: _nationalIdController,
          textInputAction: TextInputAction.next,
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'National ID is required';
            }
            if (v.trim().length < 4) return 'Invalid national ID';
            return null;
          },
        ),
        const SizedBox(height: 16),
        BirrTextField(
          label: 'Password',
          controller: _passwordController,
          obscure: _obscurePassword,
          textInputAction: TextInputAction.next,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppTheme.textMuted,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Password is required';
            if (v.length < 6) return 'Password must be at least 6 characters';
            return null;
          },
        ),
        const SizedBox(height: 16),
        BirrTextField(
          label: 'Confirm Password',
          controller: _confirmPasswordController,
          obscure: _obscureConfirm,
          textInputAction: TextInputAction.done,
          onEditingComplete: _handleSignup,
          suffixIcon: IconButton(
            icon: Icon(
              _obscureConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppTheme.textMuted,
              size: 20,
            ),
            onPressed: () =>
                setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          validator: (v) {
            if (v == null || v.isEmpty) return 'Please confirm your password';
            if (v != _passwordController.text) return 'Passwords do not match';
            return null;
          },
        ),
      ],
    );
  }
}
