import 'dart:async';
import 'package:flutter/material.dart';
import '../services/locker_service.dart';

/// Tela da fechadura, aberta no navegador do PC (Flutter Web).
/// Não lê NFC: consulta a API a cada 1 s e muda na hora entre
/// TRANCADO (vermelho) e LIBERADO (verde) quando o banco é atualizado
/// (Atalhos do iPhone -> POST /atalho, app do aluno ou emergência do admin).
class ArmarioScreen extends StatefulWidget {
  final Perfil perfil;
  const ArmarioScreen({super.key, required this.perfil});
  @override
  State<ArmarioScreen> createState() => _ArmarioScreenState();
}

class _ArmarioScreenState extends State<ArmarioScreen> {
  final svc = LockerService();
  Timer? _timer;
  String? _status; // null = carregando
  String? _dono, _donoNome, _ultimaAcao, _ultimaHora;
  bool _online = true, _atualizando = false;

  String get _armario => widget.perfil.armario ?? '?';
  bool get _aberto => _status == 'aberta' || _status == 'abrir_agora';

  @override
  void initState() {
    super.initState();
    _atualizar();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _atualizar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _atualizar() async {
    if (_atualizando) return;
    _atualizando = true;
    try {
      final e = await svc.estadoDispositivo();
      var st = (e['statusPorta'] ?? 'fechada').toString();
      if (st == 'abrir_agora') {
        // Abertura pedida pelo app ou emergência do admin: a "fechadura" confirma que abriu.
        await svc.statusDispositivo('aberta');
        st = 'aberta';
      }
      final u = e['ultimo'] as Map?;
      if (!mounted) return;
      setState(() {
        _status = st;
        _dono = e['dono']?.toString();
        _donoNome = e['donoNome']?.toString();
        _ultimaAcao = u?['acao']?.toString();
        _ultimaHora = _hora(u?['dataHora']?.toString());
        _online = true;
      });
    } catch (_) {
      if (mounted) setState(() => _online = false);
    } finally {
      _atualizando = false;
    }
  }

  String? _hora(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return null;
    String p(int n) => n.toString().padLeft(2, '0');
    return '${p(d.day)}/${p(d.month)} ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
  }

  Future<void> _trancar() async {
    try {
      await svc.statusDispositivo('fechada');
      if (mounted) setState(() => _status = 'fechada');
    } catch (_) {
      if (mounted) setState(() => _online = false);
    }
  }

  /// Sair do modo fechadura exige usuário e senha de administrador.
  Future<void> _sair() async {
    final u = TextEditingController(), s = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair do modo fechadura'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: u, decoration: const InputDecoration(labelText: 'Usuário admin')),
          TextField(controller: s, obscureText: true, decoration: const InputDecoration(labelText: 'Senha')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
        ],
      ),
    );
    if (ok != true) return;
    bool admin = false;
    try { admin = await svc.conferirAdmin(u.text, s.text); } catch (_) {}
    if (admin) {
      await svc.logout();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Usuário ou senha de administrador incorretos.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final carregando = _status == null;
    final cor = carregando ? Colors.grey : (_aberto ? Colors.green : Colors.red.shade700);
    return Scaffold(
      backgroundColor: const Color(0xFF111418),
      body: SafeArea(
        child: Stack(children: [
          Positioned(
            top: 4, right: 4,
            child: Row(children: [
              Icon(_online ? Icons.cloud_done : Icons.cloud_off,
                  color: _online ? Colors.white38 : Colors.orangeAccent, size: 20),
              if (!_online)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Text('Sem conexão com a API', style: TextStyle(color: Colors.orangeAccent)),
                ),
              IconButton(icon: const Icon(Icons.settings, color: Colors.white24), onPressed: _sair),
            ]),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_armario.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
                Text(_dono == null ? 'Sem dono' : 'Dono: ${_donoNome ?? _dono}',
                    style: const TextStyle(color: Colors.white54, fontSize: 18)),
                const SizedBox(height: 32),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  width: 260, height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cor.withOpacity(0.15),
                    border: Border.all(color: cor, width: 8),
                    boxShadow: [BoxShadow(color: cor.withOpacity(0.5), blurRadius: 50)],
                  ),
                  child: carregando
                      ? const Padding(padding: EdgeInsets.all(90), child: CircularProgressIndicator())
                      : Icon(_aberto ? Icons.lock_open_rounded : Icons.lock_rounded, size: 140, color: cor),
                ),
                const SizedBox(height: 24),
                Text(carregando ? 'CONECTANDO...' : (_aberto ? 'LIBERADO' : 'TRANCADO'),
                    style: TextStyle(color: cor, fontSize: 44, fontWeight: FontWeight.w900, letterSpacing: 6)),
                const SizedBox(height: 24),
                if (_ultimaAcao != null)
                  Text('Último evento: $_ultimaAcao${_ultimaHora != null ? '  •  $_ultimaHora' : ''}',
                      textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('Use o atalho do iPhone ou o app para abrir/trancar.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 28),
                if (_aberto)
                  SizedBox(
                    width: 260, height: 56,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      icon: const Icon(Icons.lock),
                      label: const Text('Trancar agora', style: TextStyle(fontSize: 18)),
                      onPressed: _trancar,
                    ),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
