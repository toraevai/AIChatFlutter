import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/database_service.dart';
import '../api/openrouter_client.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _showPinInput = false;

  @override
  void initState() {
    super.initState();
    _checkSavedAuth();
  }

  Future<void> _checkSavedAuth() async {
    final db = DatabaseService();
    final authData = await db.getAuthData();
    if (authData != null) {
      setState(() {
        _showPinInput = true;
      });
    }
  }

  Future<void> _handleApiKeySubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiKey = _apiKeyController.text.trim();
      final providerInfo = OpenRouterClient.detectProvider(apiKey);
      final provider = providerInfo['provider']!;
      final baseUrl = providerInfo['baseUrl']!;

      // Обновляем клиент с новым ключом
      final client = OpenRouterClient();
      client.updateApiKey(apiKey);

      // Проверяем баланс (для VSEGPT может быть пропущена)
      final balance = await client.getBalance();
      if (balance == 'Error') {
        throw Exception('Ошибка проверки API ключа');
      }

      // Для OpenRouter проверяем нулевой баланс
      if (provider == 'OpenRouter' && balance.contains('0.00')) {
        throw Exception('Недостаточно средств на балансе');
      }

      // Генерируем PIN
      final pin = _generatePin();

      // Сохраняем данные
      final db = DatabaseService();
      await db.saveAuthData(
          apiKey,
          pin,
          provider,
          provider == 'OpenRouter'
              ? double.parse(balance.replaceAll(RegExp(r'[^0-9.]'), ''))
              : 0.0);

      // Переходим на основной экран
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/chat');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка авторизации: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handlePinSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final db = DatabaseService();
      final isValid = await db.checkPin(_pinController.text);

      if (isValid) {
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/chat');
        }
      } else {
        throw Exception('Неверный PIN');
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetApiKey() async {
    final db = DatabaseService();
    await db.clearAuthData();
    setState(() {
      _showPinInput = false;
      _apiKeyController.clear();
      _pinController.clear();
    });
  }

  String _generatePin() {
    final random = DateTime.now().millisecondsSinceEpoch;
    return (random % 9000 + 1000).toString(); // 4-значный PIN
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Авторизация'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_showPinInput) _buildPinInput() else _buildApiKeyInput(),
              const SizedBox(height: 20),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              const SizedBox(height: 20),
              _isLoading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _showPinInput
                          ? _handlePinSubmit
                          : _handleApiKeySubmit,
                      child: Text(_showPinInput ? 'Войти' : 'Проверить ключ'),
                    ),
              if (_showPinInput)
                TextButton(
                  onPressed: _resetApiKey,
                  child: const Text('Сбросить ключ'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApiKeyInput() {
    return TextFormField(
      controller: _apiKeyController,
      decoration: const InputDecoration(
        labelText: 'API ключ',
        hintText: 'Введите ваш API ключ',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Пожалуйста, введите API ключ';
        }
        if (!value.startsWith('sk-or-v') || value.length < 20) {
          return 'Неверный формат API ключа';
        }
        return null;
      },
      obscureText: true,
    );
  }

  Widget _buildPinInput() {
    return TextFormField(
      controller: _pinController,
      decoration: const InputDecoration(
        labelText: 'PIN код',
        hintText: 'Введите 4-значный PIN',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Пожалуйста, введите PIN';
        }
        if (value.length != 4 || !RegExp(r'^[0-9]+$').hasMatch(value)) {
          return 'PIN должен состоять из 4 цифр';
        }
        return null;
      },
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 4,
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _pinController.dispose();
    super.dispose();
  }
}
