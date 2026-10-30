import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/armario.dart';

class Perfil {
  final String role; // 'admin', 'aluno' ou 'armario' (tela da fechadura)
  final String nome;
  final String? armario;
  Perfil(this.role, this.nome, this.armario);
}

/// Endereço da API. Web/PC = localhost; emulador Android = 10.0.2.2.
/// Para outro endereço: --dart-define=API_URL=https://SEU-APP.azurewebsites.net
const _apiEnv = String.fromEnvironment('API_URL');
String get apiUrl => _apiEnv.isNotEmpty
    ? _apiEnv
    : (!kIsWeb && defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:5000' : 'http://localhost:5000');

class LockerService {
  static final LockerService _i = LockerService._();
  factory LockerService() => _i;
  LockerService._();

  final _store = const FlutterSecureStorage();
  final sessao = ValueNotifier<Perfil?>(null);
  String? _token;

  Map<String, String> get _h =>
      {'Content-Type': 'application/json', if (_token != null) 'Authorization': 'Bearer $_token'};

  Perfil _perfil(Map m) =>
      Perfil(m['perfil'], m['nome'], (m['armario'] as String).isEmpty ? null : m['armario']);

  Future<void> restaurar() async {
    try {
      _token = await _store.read(key: 'token');
      final p = await _store.read(key: 'perfil');
      if (_token != null && p != null) sessao.value = _perfil(jsonDecode(p));
    } catch (_) {
      _token = null; // armazenamento do navegador indisponível/corrompido: pede login de novo
    }
  }

  Future<void> login(String prontuario, String senha) async {
    final r = await http.post(Uri.parse('$apiUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prontuario': prontuario.trim(), 'senha': senha}))
        .timeout(const Duration(seconds: 40));
    if (r.statusCode == 401) throw Exception('credenciais');
    if (r.statusCode != 200) throw Exception('A API respondeu com erro ${r.statusCode}.');
    await _iniciarSessao(r.body);
  }

  Future<void> _iniciarSessao(String body) async {
    final m = jsonDecode(body);
    _token = m['token'];
    await _store.write(key: 'token', value: _token);
    await _store.write(key: 'perfil', value: body);
    sessao.value = _perfil(m);
  }

  Future<void> logout() async {
    _token = null;
    try { await _store.deleteAll(); } catch (_) {}
    sessao.value = null;
  }

  /// Confere usuário/senha de administrador sem trocar a sessão (usado para sair do modo fechadura).
  Future<bool> conferirAdmin(String prontuario, String senha) async {
    final r = await http.post(Uri.parse('$apiUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prontuario': prontuario.trim(), 'senha': senha}))
        .timeout(const Duration(seconds: 40));
    return r.statusCode == 200 && jsonDecode(r.body)['perfil'] == 'admin';
  }

  /// Transforma ESTA tela (navegador do PC) na fechadura do armário [id]. O admin precisa estar logado.
  Future<void> virarFechadura(String id) async {
    final r = await http.post(Uri.parse('$apiUrl/armarios/$id/dispositivo'), headers: _h);
    if (r.statusCode != 200) throw Exception('Não foi possível configurar (erro ${r.statusCode}).');
    await _iniciarSessao(r.body);
  }

  Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$apiUrl$path'), headers: _h).timeout(const Duration(seconds: 20));
    if (r.statusCode == 401) { await logout(); throw Exception('sessão expirada'); }
    if (r.statusCode != 200) throw Exception('Erro ${r.statusCode}');
    return jsonDecode(r.body);
  }

  /// POST/DELETE. Em caso de erro, lança a mensagem enviada pela API.
  Future<void> _send(String method, String path, [Object? body]) async {
    final req = http.Request(method, Uri.parse('$apiUrl$path'))..headers.addAll(_h);
    if (body != null) req.body = jsonEncode(body);
    final r = await http.Response.fromStream(await req.send());
    if (r.statusCode >= 300) {
      final msg = r.body.replaceAll('"', '');
      throw Exception(msg.isNotEmpty && r.statusCode < 500 ? msg : 'Erro ${r.statusCode}');
    }
  }

  /// "Tempo real" por polling (a cada 5 s).
  Stream<T> _poll<T>(Future<T> Function() f) async* {
    while (true) {
      yield await f();
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  Stream<List<Armario>> todos() => _poll(() async =>
      ((await _get('/armarios')) as List).map((e) => Armario.fromMap(e)).toList());
  Stream<Armario?> um(String id) => _poll(() async => Armario.fromMap(await _get('/armarios/$id')));

  Future<void> abrir(String id) => _send('POST', '/armarios/$id/abrir');
  Future<void> resetarAlerta(String id) => _send('POST', '/armarios/$id/resetar-alerta');
  Future<void> criarArmario(String codigo) => _send('POST', '/armarios', {'codigo': codigo.trim()});
  Future<void> excluirArmario(String codigo) => _send('DELETE', '/armarios/$codigo');

  Future<List<Map>> usuarios() async => ((await _get('/usuarios')) as List).cast<Map>();
  Future<void> criarUsuario(String prontuario, String nome, String curso, String armario, String senha) =>
      _send('POST', '/usuarios', {
        'prontuario': prontuario.trim(), 'nome': nome.trim(), 'curso': curso.trim(),
        'armario': armario.trim().isEmpty ? null : armario.trim(), 'senha': senha,
      });

  Future<List<Map>> acessos() async => ((await _get('/acessos')) as List).cast<Map>();

  // ── Tela da fechadura ──
  Future<Map> estadoDispositivo() async => (await _get('/dispositivo/estado')) as Map;
  Future<void> statusDispositivo(String status) => _send('POST', '/dispositivo/status', {'status': status});
}
