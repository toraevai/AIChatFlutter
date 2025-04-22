// Import JSON library
import 'dart:convert';
// Import HTTP client
import 'package:http/http.dart' as http;
// Import Flutter core classes
import 'package:flutter/foundation.dart';
// Import package for working with .env files
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Класс клиента для работы с API OpenRouter
class OpenRouterClient {
  // API ключ для авторизации
  String? apiKey;
  // Базовый URL API
  String? baseUrl;
  // Заголовки HTTP запросов
  final Map<String, String> headers;

  // Единственный экземпляр класса (Singleton)
  static final OpenRouterClient _instance = OpenRouterClient._internal();

  // Фабричный метод для получения экземпляра
  factory OpenRouterClient() {
    return _instance;
  }

  // Приватный конструктор для реализации Singleton
  OpenRouterClient._internal()
      : apiKey = dotenv.env['OPENROUTER_API_KEY'],
        baseUrl = dotenv.env['BASE_URL'],
        headers = {
          'Content-Type': 'application/json',
          'X-Title': 'AI Chat Flutter',
        } {
    if (apiKey != null) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    _initializeClient();
  }

  // Метод определения провайдера и URL по ключу
  static Map<String, String> detectProvider(String apiKey) {
    if (apiKey.startsWith('sk-or-vv-')) {
      return {'provider': 'VSEGPT', 'baseUrl': 'https://api.vsegpt.ru/v1'};
    } else if (apiKey.startsWith('sk-or-v1-')) {
      return {
        'provider': 'OpenRouter',
        'baseUrl': 'https://openrouter.ai/api/v1'
      };
    }
    throw Exception('Invalid API key format');
  }

  // Метод обновления API ключа и URL
  void updateApiKey(String newApiKey) {
    final providerInfo = detectProvider(newApiKey);
    apiKey = newApiKey;
    baseUrl = providerInfo['baseUrl'];
    headers['Authorization'] = 'Bearer $newApiKey';
    if (kDebugMode) {
      print('Updated API key to: $newApiKey');
      print('Using base URL: $baseUrl');
    }
    _initializeClient();
  }

  // Метод инициализации клиента
  void _initializeClient() {
    // Если ключ не установлен, пропускаем проверки
    if (apiKey == null || apiKey!.isEmpty) return;
    try {
      if (kDebugMode) {
        print('Initializing OpenRouterClient...');
        print('Base URL: $baseUrl');
      }

      // Проверка наличия API ключа
      if (apiKey == null) {
        throw Exception('OpenRouter API key not found in .env');
      }
      // Проверка наличия базового URL
      if (baseUrl == null) {
        throw Exception('BASE_URL not found in .env');
      }

      if (kDebugMode) {
        print('OpenRouterClient initialized successfully');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error initializing OpenRouterClient: $e');
        print('Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  // Метод получения списка доступных моделей
  Future<List<Map<String, dynamic>>> getModels() async {
    try {
      // Выполнение GET запроса для получения моделей
      final response = await http.get(
        Uri.parse('$baseUrl/models'),
        headers: headers,
      );

      if (kDebugMode) {
        print('Models response status: ${response.statusCode}');
        print('Models response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        // Парсинг данных о моделях
        final modelsData = json.decode(response.body);
        if (modelsData['data'] != null) {
          return (modelsData['data'] as List)
              .map((model) => {
                    'id': model['id'] as String,
                    'name': (() {
                      try {
                        return utf8.decode((model['name'] as String).codeUnits);
                      } catch (e) {
                        // Remove invalid UTF-8 characters and try again
                        final cleaned = (model['name'] as String)
                            .replaceAll(RegExp(r'[^\x00-\x7F]'), '');
                        return utf8.decode(cleaned.codeUnits);
                      }
                    })(),
                    'pricing': {
                      'prompt': model['pricing']['prompt'] as String,
                      'completion': model['pricing']['completion'] as String,
                    },
                    'context_length': (model['context_length'] ??
                            model['top_provider']['context_length'] ??
                            0)
                        .toString(),
                  })
              .toList();
        }
        throw Exception('Invalid API response format');
      } else {
        // Возвращение моделей по умолчанию, если API недоступен
        return [
          {'id': 'deepseek-coder', 'name': 'DeepSeek'},
          {'id': 'claude-3-sonnet', 'name': 'Claude 3.5 Sonnet'},
          {'id': 'gpt-3.5-turbo', 'name': 'GPT-3.5 Turbo'},
        ];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting models: $e');
      }
      // Возвращение моделей по умолчанию в случае ошибки
      return [
        {'id': 'deepseek-coder', 'name': 'DeepSeek'},
        {'id': 'claude-3-sonnet', 'name': 'Claude 3.5 Sonnet'},
        {'id': 'gpt-3.5-turbo', 'name': 'GPT-3.5 Turbo'},
      ];
    }
  }

  // Метод отправки сообщения через API
  Future<Map<String, dynamic>> sendMessage(String message, String model) async {
    try {
      // Подготовка данных для отправки
      final data = {
        'model': model, // Модель для генерации ответа
        'messages': [
          {'role': 'user', 'content': message} // Сообщение пользователя
        ],
        'max_tokens': int.parse(dotenv.env['MAX_TOKENS'] ??
            '1000'), // Максимальное количество токенов
        'temperature': double.parse(
            dotenv.env['TEMPERATURE'] ?? '0.7'), // Температура генерации
        'stream': false, // Отключение потоковой передачи
      };

      if (kDebugMode) {
        print('Sending message to API: ${json.encode(data)}');
      }

      // Выполнение POST запроса
      final response = await http.post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: headers,
        body: json.encode(data),
      );

      if (kDebugMode) {
        print('Message response status: ${response.statusCode}');
        print('Message response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        // Успешный ответ
        final responseData = json.decode(utf8.decode(response.bodyBytes));
        return responseData;
      } else {
        // Обработка ошибки
        final errorData = json.decode(utf8.decode(response.bodyBytes));
        return {
          'error': errorData['error']?['message'] ?? 'Unknown error occurred'
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending message: $e');
      }
      return {'error': e.toString()};
    }
  }

  // Метод получения текущего баланса
  Future<String> getBalance() async {
    try {
      // Для VSEGPT пропускаем проверку баланса, если она отключена
      if (baseUrl?.contains('vsegpt.ru') == true) {
        return 'Баланс не проверен';
      }

      // Для OpenRouter выполняем обычную проверку
      final response = await http.get(
        Uri.parse('$baseUrl/credits'),
        headers: headers,
      );

      if (kDebugMode) {
        print('Balance response status: ${response.statusCode}');
        print('Balance response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['data'] != null) {
          final credits = data['data']['total_credits'] ?? 0;
          final usage = data['data']['total_usage'] ?? 0;
          return '\$${(credits - usage).toStringAsFixed(2)}';
        }
      }
      return '\$0.00';
    } catch (e) {
      if (kDebugMode) {
        print('Error getting balance: $e');
      }
      return 'Error'; // Возвращение ошибки в случае исключения
    }
  }

  // Метод форматирования цен
  String formatPricing(double pricing) {
    try {
      if (baseUrl?.contains('vsegpt.ru') == true) {
        return '${pricing.toStringAsFixed(3)}₽/K';
      } else {
        return '\$${(pricing * 1000000).toStringAsFixed(3)}/M';
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error formatting pricing: $e');
      }
      return '0.00';
    }
  }
}
