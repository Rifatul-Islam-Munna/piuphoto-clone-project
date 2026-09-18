import 'package:auto_route/auto_route.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/utilities/app_toast.dart';

@RoutePage()
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _role = 'event_planner';
  bool _loading = false;

  Future<void> _register() async {
    setState(() => _loading = true);
    try {
      await DioHelper.post(
        '/user',
        data: {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'role': _role,
        },
      );

      AppToast.success('Registration successful. Please login.');
      if (mounted) {
        context.router.replace(const LoginRoute());
      }
    } on DioException catch (error) {
      AppToast.error(
        error.response?.data?['message']?.toString() ?? 'Register failed',
      );
    } catch (_) {
      AppToast.error('Register failed');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => context.router.maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.muted,
                          foregroundColor: AppColors.foreground,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Airpix',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.45,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Text(
                    'Build your workspace',
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose the workspace that matches how you use Airpix. You can keep your event and delivery tools in one place.',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.mutedForeground,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: AppColors.muted,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'event_planner',
                          label: Text('Planner'),
                          icon: Icon(Icons.event_available_outlined, size: 18),
                        ),
                        ButtonSegment(
                          value: 'photographer',
                          label: Text('Photographer'),
                          icon: Icon(Icons.photo_camera_outlined, size: 18),
                        ),
                      ],
                      selected: {_role},
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        side: const WidgetStatePropertyAll(BorderSide.none),
                        textStyle: const WidgetStatePropertyAll(
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                      onSelectionChanged: (value) =>
                          setState(() => _role = value.first),
                    ),
                  ),
                  const SizedBox(height: 18),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWarm,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _role == 'photographer'
                                ? Icons.auto_awesome_motion_outlined
                                : Icons.calendar_month_outlined,
                            color: AppColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _role == 'photographer'
                                ? 'Capture, upload and deliver photos from your photographer workspace.'
                                : 'Create events, invite photographers and manage guest delivery.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.foreground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _loading ? null : _register,
                            child: _loading
                                ? const SizedBox(
                                    height: 21,
                                    width: 21,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Create account'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: () =>
                          context.router.replace(const LoginRoute()),
                      child: const Text('Already have an account? Sign in'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
