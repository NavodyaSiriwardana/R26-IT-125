import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'new_entry_screen.dart';
import 'task_selection_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String _error = '';

  Future<void> _register() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _error = 'Please fill all fields');
      return;
    }

    setState(() {
      _loading = true;
      _error = '';
    });

    final success = await AuthService.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    setState(() => _loading = false);

    if (success && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TaskSelectionScreen()),
        (route) => false,
      );
    } else {
      setState(() => _error = 'Registration failed. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A16),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF9784FF)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create account',
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -1.0),
            radius: 1.5,
            colors: [Color(0xFF191533), Color(0xFF0A0A16)],
            stops: [0.0, 0.6],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                const Text(
                  'Join to start tracking your day',
                  style: TextStyle(
                    color: Color(0xFF8888AC),
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 28),
                _buildField('FULL NAME', _nameController, 'Navodya Animsara',
                    false, Icons.person_outline_rounded),
                const SizedBox(height: 16),
                _buildField('EMAIL', _emailController, 'your@email.com',
                    false, Icons.mail_outline_rounded),
                const SizedBox(height: 16),
                _buildField('PASSWORD', _passwordController, '••••••••',
                    true, Icons.lock_outline_rounded),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE24B4A).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFE24B4A).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Color(0xFFE24B4A), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error,
                              style: const TextStyle(
                                  color: Color(0xFFE24B4A), fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7B61FF).withValues(alpha: 0.35),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _loading ? null : _register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7B61FF),
                        disabledBackgroundColor:
                            const Color(0xFF7B61FF).withValues(alpha: 0.6),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Create account',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller,
      String hint, bool obscure, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              color: Color(0xFF8888AC),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            )),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF4a4a6a)),
            prefixIcon: Icon(icon, size: 19, color: const Color(0xFF6a6a8e)),
            filled: true,
            fillColor: const Color(0xFF13132A),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF26263e)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF26263e)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF7B61FF), width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
