import 'package:flutter/material.dart';
import '../models/armario.dart';
import '../services/locker_service.dart';

/// Tela do aluno: vê o estado do armário e pode pedir a abertura pela API.
class AlunoScreen extends StatefulWidget {
  final Perfil perfil;
  const AlunoScreen({super.key, required this.perfil});
  @override
  State<AlunoScreen> createState() => _AlunoScreenState();
}

class _AlunoScreenState extends State<AlunoScreen> {
  final svc = LockerService();
  bool _ocupado = false;
  String? _msg;
  Color _cor = Colors.grey;

  Future<void> _abrir(String id) async {
    if (_ocupado) return;
    setState(() { _ocupado = true; _msg = null; });
    try {
      await svc.abrir(id);
      setState(() { _msg = 'Pedido enviado! O armário será liberado em instantes.'; _cor = Colors.green; });
    } catch (e) {
      setState(() { _msg = 'Não foi possível abrir: ${e.toString().replaceFirst("Exception: ", "")}'; _cor = Colors.red; });
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meu = widget.perfil.armario;
    return Scaffold(
      appBar: AppBar(
        title: Text('Olá, ${widget.perfil.nome.split(" ").first}'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: svc.logout)],
      ),
      body: meu == null
          ? const Center(child: Text('Você ainda não possui um armário.'))
          : StreamBuilder<Armario?>(
              stream: svc.um(meu),
              builder: (_, s) {
                final a = s.data;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(children: [
                      Icon(a?.portaAberta == true ? Icons.lock_open : Icons.lock, size: 88, color: a?.cor ?? Colors.grey),
                      const SizedBox(height: 8),
                      Text(meu, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      if (a != null) Text(a.rotulo, style: TextStyle(color: a.cor, fontSize: 16)),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: 260, height: 52,
                        child: FilledButton.icon(
                          icon: _ocupado
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.lock_open),
                          label: const Text('Abrir meu armário'),
                          onPressed: _ocupado ? null : () => _abrir(meu),
                        ),
                      ),
                      if (_msg != null) ...[
                        const SizedBox(height: 16),
                        Text(_msg!, textAlign: TextAlign.center, style: TextStyle(color: _cor, fontSize: 16)),
                      ],
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
