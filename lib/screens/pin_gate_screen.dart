import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../services/prefs_service.dart';
import '../state/admin_auth.dart';

/// Either sets the first-ever PIN or verifies an existing one before unlocking
/// Admin. Pops with `true` on success.
class PinGateScreen extends StatefulWidget {
  const PinGateScreen({super.key});

  @override
  State<PinGateScreen> createState() => _PinGateScreenState();
}

class _PinGateScreenState extends State<PinGateScreen> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final prefs = context.read<PrefsService>();
    final auth = context.read<AdminAuth>();
    final t = AppStrings.of(context);
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4 || pin.length > 6) {
      setState(() => _error = 'PIN must be 4–6 digits.');
      return;
    }
    setState(() {
      _error = null;
      _submitting = true;
    });
    try {
      if (prefs.hasPin) {
        if (!prefs.verifyPin(pin)) {
          setState(() => _error = t.pinMismatch);
          return;
        }
      } else {
        if (_confirmCtrl.text.trim() != pin) {
          setState(() => _error = 'PINs do not match.');
          return;
        }
        await prefs.setPin(pin);
      }
      auth.unlock();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppStrings.of(context);
    final prefs = context.watch<PrefsService>();
    final isSetup = !prefs.hasPin;
    return Scaffold(
      appBar: AppBar(title: Text(isSetup ? t.setPin : t.enterPin)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isSetup
                      ? 'Pick a 4–6 digit PIN. Children should not be able to guess it.'
                      : 'Enter the Teacher PIN to access Admin.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _pinCtrl,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'PIN',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (isSetup) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Confirm PIN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: Text(isSetup ? t.setPin : 'Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
