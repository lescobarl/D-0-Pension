import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/app_metadata.dart';
import '../../core/models/periodo_salarial.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pension_constants.dart';
import '../../core/utils/input_validator.dart';
import '../../presentation/widgets/validation_indicator.dart';
import '../../services/retroactive_provider.dart';

/// Ultra-compact data capture view fitting entirely on one screen.
///
/// Four sections in a single compact layout:
/// - DATOS PERSONALES (fecha cálculo, nacimiento, esposa, hijos, padres)
/// - DATOS LABORALES (salario, semanas antes Mod40, edad retiro, UMA, salario mínimo)
/// - MODALIDAD 40 (inicio, semanas, salario, total)
/// - DESGLOSE SAL. PROM MOD 40 (periodos detallados)
class CapturaView extends StatefulWidget {
  const CapturaView({super.key});

  @override
  State<CapturaView> createState() => _CapturaViewState();
}

class _CapturaViewState extends State<CapturaView> {
  late TextEditingController _fechaCalculoController;

  /// Prevents showing the "Configuración recuperada" SnackBar more than once.
  bool _hasShownLoadMessage = false;
  late TextEditingController _fechaNacimientoController;
  late TextEditingController _salarioPromedio250Controller;
  late TextEditingController _semanasAntesMod40Controller;
  late TextEditingController _semanasEnMod40Controller;
  late TextEditingController _salarioPromedioController;
  late TextEditingController _fechaInicioMod40Controller;
  late TextEditingController _numeroHijosController;
  late TextEditingController _numeroPadresController;
  late TextEditingController _umaDiariaController;
  late TextEditingController _salarioMinimoDiarioController;

  /// Per-period TextEditingControllers for the Desglose Sal. Prom section.
  /// Each entry holds [salarioController, semanasController] plus focus nodes.
  /// Using controllers (instead of initialValue+ValueKey) prevents focus loss
  /// on rebuild because the controller retains its text state independently.
  final List<_PeriodoControllers> _periodoControllers = [];

  /// Indices of period rows currently in "fechas" mode (capture inicio/fin
  /// instead of weeks). When both dates are set, weeks are auto-computed.
  final Set<int> _periodosEnModoFechas = {};

  @override
  void initState() {
    super.initState();
    final p = context.read<RetroactiveProvider>();
    _fechaCalculoController = TextEditingController(
      text: _formatDate(p.fechaCalculo),
    );
    _fechaNacimientoController = TextEditingController(
      text: _formatDate(p.fechaNacimiento),
    );
    _salarioPromedio250Controller = TextEditingController(
      text: p.salarioPromedio250Semanas.toStringAsFixed(4),
    );
    _semanasAntesMod40Controller = TextEditingController(
      text: p.semanasAntesMod40.toString(),
    );
    _semanasEnMod40Controller = TextEditingController(
      text: p.semanasEnMod40.toStringAsFixed(4),
    );
    _salarioPromedioController = TextEditingController(
      text: p.salarioDiarioPromedio.toStringAsFixed(4),
    );
    _fechaInicioMod40Controller = TextEditingController(
      text: _formatDate(p.startDate),
    );
    _numeroHijosController = TextEditingController(
      text: p.numeroHijos.toString(),
    );
    _numeroPadresController = TextEditingController(
      text: p.numeroPadres.toString(),
    );
    _umaDiariaController = TextEditingController(
      text: p.umaDiaria.toStringAsFixed(5),
    );
    _salarioMinimoDiarioController = TextEditingController(
      text: p.salarioMinimoDiario.toStringAsFixed(5),
    );


  }

  @override
  void dispose() {
    _fechaCalculoController.dispose();
    _fechaNacimientoController.dispose();
    _salarioPromedio250Controller.dispose();
    _semanasAntesMod40Controller.dispose();
    _semanasEnMod40Controller.dispose();
    _salarioPromedioController.dispose();
    _fechaInicioMod40Controller.dispose();
    _numeroHijosController.dispose();
    _numeroPadresController.dispose();
    _umaDiariaController.dispose();
    _salarioMinimoDiarioController.dispose();
    for (final pc in _periodoControllers) {
      pc.salario.dispose();
      pc.semanas.dispose();
      pc.salarioFocus.dispose();
      pc.semanasFocus.dispose();
    }
    super.dispose();
  }

  /// Synchronizes [_periodoControllers] with [provider.periodos] structurally.
  ///
  /// Creates new controllers for new periods and disposes controllers for
  /// removed periods. Updates the controller texts for existing periods
  /// when the provider values have changed, without interrupting user input.
  void _syncPeriodoControllers(RetroactiveProvider provider) {
    final periodos = provider.periodos;
    // Dispose excess controllers if periods were removed
    while (_periodoControllers.length > periodos.length) {
      final removed = _periodoControllers.removeLast();
      removed.salario.dispose();
      removed.semanas.dispose();
      removed.salarioFocus.dispose();
      removed.semanasFocus.dispose();
    }
    // Add controllers for new periods only — never overwrite existing text
    for (int i = 0; i < periodos.length; i++) {
      if (i >= _periodoControllers.length) {
        _periodoControllers.add(_PeriodoControllers(
          TextEditingController(text: periodos[i].salarioDiario.toStringAsFixed(4)),
          TextEditingController(text: periodos[i].semanas.toStringAsFixed(2)),
          FocusNode(),
          FocusNode(),
        ));
      } else {
        final controller = _periodoControllers[i];
        if (!controller.salarioFocus.hasFocus) {
          _setControllerText(controller.salario, periodos[i].salarioDiario.toStringAsFixed(4));
        }
        if (!controller.semanasFocus.hasFocus) {
          _setControllerText(controller.semanas, periodos[i].semanas.toStringAsFixed(2));
        }
      }
    }
  }

  /// Force-updates all controller text to match [provider.periodos].
  ///
  /// Used after resetPeriodosToBaseline() to reload Excel baseline data into
  /// the controllers. This is safe because the user is not actively typing
  /// during a reset operation.
  void _forceSyncPeriodoControllers(RetroactiveProvider provider) {
    final periodos = provider.periodos;
    for (int i = 0; i < periodos.length && i < _periodoControllers.length; i++) {
      _periodoControllers[i].salario.text =
          periodos[i].salarioDiario.toStringAsFixed(4);
      _periodoControllers[i].semanas.text =
          periodos[i].semanas.toStringAsFixed(2);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Parses date from YYYY-MM-DD or YYYYMMDD format.
  DateTime _parseDate(String text) {
    try {
      String cleaned = text.replaceAll('-', '').trim();
      if (cleaned.length == 8) {
        return DateTime(
          int.parse(cleaned.substring(0, 4)),
          int.parse(cleaned.substring(4, 6)),
          int.parse(cleaned.substring(6, 8)),
        );
      }
    } catch (e) {
      debugPrint('[CapturaView] Error parsing date "$text": $e');
    }
    return DateTime.now();
  }

  /// Formats YYYYMMDD → YYYY-MM-DD for display.
  String _autoFormatDate(String text) {
    final cleaned = text.replaceAll('-', '').trim();
    if (cleaned.length == 8) {
      return '${cleaned.substring(0, 4)}-${cleaned.substring(4, 6)}-${cleaned.substring(6, 8)}';
    }
    return text;
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
  }

  void _syncControllersFromProvider(RetroactiveProvider provider) {
    if (!mounted) return;
    _setControllerText(_umaDiariaController, provider.umaDiaria.toStringAsFixed(5));
    _setControllerText(_salarioMinimoDiarioController, provider.salarioMinimoDiario.toStringAsFixed(5));
    _setControllerText(_salarioPromedio250Controller, provider.salarioPromedio250Semanas.toStringAsFixed(4));
    _setControllerText(_salarioPromedioController, provider.salarioDiarioPromedio.toStringAsFixed(4));
    _setControllerText(_semanasEnMod40Controller, provider.semanasEnMod40.toStringAsFixed(4));
    _setControllerText(_semanasAntesMod40Controller, provider.semanasAntesMod40.toStringAsFixed(0));
    _syncPeriodoControllers(provider);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RetroactiveProvider>(
      builder: (context, provider, _) {
        _syncControllersFromProvider(provider);

        if (provider.loadedFromPersistence && !_hasShownLoadMessage) {
          _hasShownLoadMessage = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Configuración recuperada'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          });
        }

        // Natural-height layout: each section takes only the space its content
        // needs (no stretching, no hidden fields). Compact spacing keeps
        // everything on one screen on normal windows; the scroll view is only
        // a safety net for very short windows.
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 1),
              _buildElegibilidadBanner(provider),
              const SizedBox(height: 1),
              _buildDatosPersonales(provider),
              const SizedBox(height: 1),
              _buildDatosLaborales(provider),
              const SizedBox(height: 1),
              _buildDatosMod40(provider),
              const SizedBox(height: 1),
              _buildSaveButton(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.edit_note, color: AppTheme.accent, size: 14),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Captura SIMPLIFICADA',
              style: TextStyle(
                fontSize: AppTheme.fontSizeCardTitle,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'Ley 1973',
              style: TextStyle(
                fontSize: AppTheme.fontSizeBodySmall,
                fontWeight: FontWeight.w600,
                color: AppTheme.accentLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatosPersonales(RetroactiveProvider provider) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppTheme.dividerColor),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(Icons.person, 'Datos Personales'),
            const SizedBox(height: 1),
            // Fecha Cálculo + Fecha Nacimiento side by side
            Row(
              children: [
                Expanded(child: _buildValidatedDateField('Fecha de Cálculo', _fechaCalculoController, (v) {
                  final parsed = _parseDate(v);
                  provider.setFechaCalculo(parsed);
                })),
                const SizedBox(width: 6),
                Expanded(child: _buildValidatedDateField('Fecha de Nacimiento', _fechaNacimientoController, (v) {
                  final parsed = _parseDate(v);
                  provider.setFechaNacimiento(parsed);
                })),
              ],
            ),
            const SizedBox(height: 1),
            // Esposa toggle + Hijos + Padres in one row
            Row(
              children: [
                // Esposa toggle — compact, matches text field height exactly
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 2),
                        child: Text('¿Esposa?',
                            style: TextStyle(
                              fontSize: AppTheme.fontSizeBodySmall,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                      GestureDetector(
                        onTap: () => provider.setTieneEsposa(!provider.tieneEsposa),
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.dividerColor),
                          ),
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Text(
                                provider.tieneEsposa ? 'Sí' : 'No',
                                style: const TextStyle(
                                  fontSize: AppTheme.fontSizeInput,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                provider.tieneEsposa ? Icons.check_circle : Icons.radio_button_unchecked,
                                size: 20,
                                color: provider.tieneEsposa ? const Color(0xFF4CAF50) : AppTheme.textHint,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: _buildValidatedNumberField('Hijos', _numeroHijosController, (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null) provider.setNumeroHijos(parsed);
                  }, (value) {
                    if (value.isEmpty) return ValidationResult.valid();
                    final parsed = int.tryParse(value);
                    if (parsed == null) {
                      return ValidationResult.error('Debe ser un número entero');
                    }
                    if (parsed < 0) {
                      return ValidationResult.error('No puede ser negativo');
                    }
                    if (parsed > 20) {
                      return ValidationResult.warning('Valor alto de hijos');
                    }
                    return ValidationResult.valid();
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: _buildValidatedNumberField('Padres', _numeroPadresController, (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null) provider.setNumeroPadres(parsed);
                  }, (value) {
                    if (value.isEmpty) return ValidationResult.valid();
                    final parsed = int.tryParse(value);
                    if (parsed == null) {
                      return ValidationResult.error('Debe ser un número entero');
                    }
                    if (parsed < 0) {
                      return ValidationResult.error('No puede ser negativo');
                    }
                    if (parsed > 4) {
                      return ValidationResult.warning('Valor alto de padres');
                    }
                    return ValidationResult.valid();
                  }),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Banner informativo de PROYECCIÓN (Ley 73). La app es una herramienta de
  /// proyección: la pensión SIEMPRE se proyecta a la edad de retiro
  /// seleccionada, por lo que la edad actual nunca bloquea el cálculo. El
  /// banner muestra la proyección ("Proyección a los {edad} años (faltan X
  /// años)") y, en su caso, la advertencia NO bloqueante por semanas < 500.
  Widget _buildElegibilidadBanner(RetroactiveProvider provider) {
    final advertencias = provider.requisitosPensionFaltantes;
    final tieneAdvertencia = advertencias.isNotEmpty;
    final color = tieneAdvertencia ? AppTheme.warningColor : AppTheme.primary;
    final icon =
        tieneAdvertencia ? Icons.warning_amber_rounded : Icons.schedule;
    final titulo =
        'Proyección a los ${provider.edadRetiro.toStringAsFixed(0)} años '
        '(faltan ${provider.anosFaltantesEdadRetiro.toStringAsFixed(2)} años)';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeBody,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          if (tieneAdvertencia) ...[
            const SizedBox(height: 4),
            ...advertencias.map(
              (r) => Padding(
                padding: const EdgeInsets.only(left: 22, bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.cancel_outlined,
                        size: 13, color: AppTheme.errorColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        r,
                        style: const TextStyle(
                          fontSize: AppTheme.fontSizeBodySmall,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatosLaborales(RetroactiveProvider provider) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppTheme.dividerColor),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(Icons.work, 'Datos Laborales'),
            const SizedBox(height: 1),
            // Semanas antes Mod40 + Edad Retiro side by side
            Row(
              children: [
                Expanded(
                  child: _buildValidatedNumberField('Semanas Cotizadas (antes Mod40)', _semanasAntesMod40Controller, (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) provider.setSemanasAntesMod40(parsed);
                  }, (value) {
                    if (value.isEmpty) return ValidationResult.valid();
                    final parsed = double.tryParse(value);
                    if (parsed == null) {
                      return ValidationResult.error('Debe ser un número válido');
                    }
                    if (parsed < 0) {
                      return ValidationResult.error('No puede ser negativo');
                    }
                    if (parsed > 5000) {
                      return ValidationResult.warning('Valor muy alto de semanas');
                    }
                    if (parsed < PensionConstants.minSemanasLey73) {
                      return InputValidator.validateMinSemanasLey73(parsed.toInt());
                    }
                    return ValidationResult.valid();
                  }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildEdadRetiroCompact(provider, provider.edadRetiro, (v) {
                    if (v != null) provider.setEdadRetiro(v);
                  }, AppTheme.primary),
                ),
              ],
            ),
            const SizedBox(height: 1),
            // UMA Diaria + Salario Mínimo Diario side by side
            Row(
              children: [
                Expanded(
                  child: _buildValidatedNumberField('UMA Diaria', _umaDiariaController, (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) provider.setUmaDiaria(parsed);
                  }, (value) {
                    if (value.isEmpty) return ValidationResult.valid();
                    final parsed = double.tryParse(value);
                    if (parsed == null) {
                      return ValidationResult.error('Debe ser un número válido');
                    }
                    if (parsed <= 0) {
                      return ValidationResult.error('Debe ser mayor a cero');
                    }
                    if (parsed > 1000) {
                      return ValidationResult.warning('Valor muy alto de UMA');
                    }
                    return ValidationResult.valid();
                  }),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildValidatedNumberField('Salario Mínimo Diario', _salarioMinimoDiarioController, (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) provider.setSalarioMinimoDiario(parsed);
                  }, InputValidator.validateSalary),
                ),
              ],
            ),
            const SizedBox(height: 1),
            _buildReadOnlyField('Salario Promedio 250 Semanas', provider.salarioPromedio250Semanas.toStringAsFixed(4)),
            const SizedBox(height: 1),
            _buildDesglosePeriodos(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildDatosMod40(RetroactiveProvider provider) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: AppTheme.dividerColor),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(Icons.trending_up, 'Modalidad 40'),
            const SizedBox(height: 1),
            // Inicio Mod40 (full width)
            _buildValidatedDateField('Inicio de aportaciones Mod40', _fechaInicioMod40Controller, (v) {
              final parsed = _parseDate(v);
              provider.setStartDate(parsed);
            }),
            const SizedBox(height: 1),
            // UMA Multiplier selector (1-25)
            _buildUmaMultiplierField(provider),
            const SizedBox(height: 1),
            // Semanas en Mod40 + Salario Promedio side by side
            Row(
              children: [
                Expanded(
                  child: _buildReadOnlyField('Semanas en Mod40', provider.semanasEnMod40.toStringAsFixed(4)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildReadOnlyField('Salario Promedio (con Mod40)', provider.nuevoSalarioPromedio.toStringAsFixed(4)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a dropdown for selecting the UMA multiplier (1-25).
  /// Shows the resulting salario registrado in real time.
  Widget _buildUmaMultiplierField(RetroactiveProvider provider) {
    final double umaDiaria = provider.umaDiaria;
    final double multiplier = provider.umaMultiplier;
    final double salarioCalculado = multiplier * umaDiaria;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 20,
                  color: Color(0xFF4CAF50),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'UMAs a pagar:',
                    style: const TextStyle(
                      fontSize: AppTheme.fontSizeBody,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: DropdownButton<double>(
              value: multiplier,
              isDense: true,
              // isExpanded evita el overflow horizontal: el texto seleccionado
              // se ajusta (con ellipsis) al ancho asignado por el Expanded en
              // lugar de dimensionarse por su contenido intrínseco.
              isExpanded: true,
              underline: const SizedBox(),
              items: List.generate(25, (i) => i + 1).map((v) {
                final val = v.toDouble();
                return DropdownMenuItem<double>(
                  value: val,
                  child: Text(
                    '$v UMAs',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: AppTheme.fontSizeBody),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  provider.setUmaMultiplier(value);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              '= \$${salarioCalculado.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the SAL. PROM MOD 40 period breakdown section.
  ///
  /// Shows each period as a row with editable salarioDiario and semanas fields,
  /// plus the calculated resultado (salarioDiario × semanas).
  /// The first period (Mod40) is highlighted and auto-filled from _salarioRegistrado.
  /// All fields are always editable — changes recalculate in real time.
  ///
  /// The section is collapsible (expandable) to save screen space.
  /// Uses a prominent background and icon to make it obvious it's tappable.
  Widget _buildDesglosePeriodos(RetroactiveProvider provider) {
    final periodos = provider.periodos;
    final totalSemanasPromedio =
        provider.evaluator.metadata.financialRules.totalSemanasPromedio;

    // Sync controllers with the current period list (add/remove/reset)
    _syncPeriodoControllers(provider);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        collapsedBackgroundColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        leading: Icon(
          Icons.table_chart,
          size: 20,
          color: AppTheme.primary,
        ),
        title: Text(
          'Captura de salario promedio y Modalidad 40',
          style: TextStyle(
            fontSize: AppTheme.fontSizeLabel,
            fontWeight: FontWeight.w600,
            color: AppTheme.primary,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(
              periodos.isNotEmpty
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 20,
              color: periodos.isNotEmpty
                  ? const Color(0xFF4CAF50)
                  : AppTheme.textHint,
            ),
            const SizedBox(width: 4),
            Text(
              periodos.isNotEmpty
                  ? '${periodos.length} periodos — toca para ver detalle'
                  : 'Sin periodos — toca para agregar',
              style: TextStyle(
                fontSize: AppTheme.fontSizeBodySmall - 1,
                color: AppTheme.textHint,
              ),
            ),
          ],
        ),
        children: [
          const SizedBox(height: 4),
          if (periodos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Sin periodos. Agrega uno nuevo.',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeBodySmall,
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...periodos.asMap().entries.map((entry) {
              final index = entry.key;
              final periodo = entry.value;
              return _buildPeriodoRow(provider, index, periodo);
            }),
          const SizedBox(height: 4),
          // Summary row
          _buildPeriodosSummary(periodos, totalSemanasPromedio),
          const SizedBox(height: 4),
          // Action buttons row
          Row(
            children: [
              // Add period button — compact text button
              TextButton.icon(
                onPressed: () => provider.addPeriodo(),
                icon: const Icon(Icons.add, size: 13),
                label: const Text('Agregar periodo',
                    style: TextStyle(fontSize: AppTheme.fontSizeBodySmall)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              // Reload Excel baseline data button
              TextButton.icon(
                onPressed: () {
                  provider.resetPeriodosToBaseline();
                  // Force-sync controllers to match the new baseline values
                  _forceSyncPeriodoControllers(provider);
                },
                icon: const Icon(Icons.restore, size: 13),
                label: const Text('Recargar datos Excel',
                    style: TextStyle(fontSize: AppTheme.fontSizeBodySmall)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.warningColor,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Builds a single period row with editable salarioDiario and semanas.
  ///
  /// Uses [TextEditingController] from [_periodoControllers] (instead of
  /// initialValue+ValueKey) to prevent focus loss on rebuild. The controller
  /// retains its text state independently of the widget lifecycle, so even
  /// when [provider.updatePeriodo] calls notifyListeners(), the TextFormField
  /// is not disposed/recreated and keeps focus and cursor position.
  Widget _buildPeriodoRow(
    RetroactiveProvider provider,
    int index,
    PeriodoSalarial periodo,
  ) {
    // Get or create controllers for this period index
    final controllers = index < _periodoControllers.length
        ? _periodoControllers[index]
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      decoration: BoxDecoration(
        color: periodo.esMod40
            ? AppTheme.primary.withValues(alpha: 0.04)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: periodo.esMod40
              ? AppTheme.primary.withValues(alpha: 0.15)
              : AppTheme.dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Period label + delete icon inline
              SizedBox(
                width: 56,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          periodo.esMod40 ? 'Mod40' : 'P${index + 1}',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeTableData,
                            fontWeight: FontWeight.w500,
                            color: periodo.esMod40 ? AppTheme.primary : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (!periodo.esMod40) ...[
                      const SizedBox(width: 2),
                      GestureDetector(
                        onTap: () => provider.removePeriodo(index),
                        child: Icon(Icons.remove_circle_outline,
                            size: 13, color: AppTheme.errorColor.withValues(alpha: 0.7)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 2),
              // Salario Diario
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextFormField(
                    key: ValueKey('sal_$index'),
                    controller: controllers?.salario,
                    decoration: const InputDecoration(
                      labelText: 'Salario',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: AppTheme.fontSizeTableData),
                    focusNode: controllers?.salarioFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (v) {
                      final normalized = v.replaceAll(',', '.');
                      final parsed = double.tryParse(normalized);
                      if (parsed != null) {
                        final updated = periodo.copyWith(salarioDiario: parsed);
                        provider.updatePeriodo(index, updated);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // Semanas
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextFormField(
                    key: ValueKey('sem_$index'),
                    controller: controllers?.semanas,
                    decoration: const InputDecoration(
                      labelText: 'Semanas',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: AppTheme.fontSizeTableData),
                    focusNode: controllers?.semanasFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (v) {
                      final normalized = v.replaceAll(',', '.');
                      final parsed = double.tryParse(normalized);
                      if (parsed != null) {
                        final updated = periodo.copyWith(semanas: parsed);
                        provider.updatePeriodo(index, updated);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // Resultado (read-only)
              SizedBox(
                width: 80,
                child: Text(
                  '\$${periodo.resultado.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: AppTheme.fontSizeTableData,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              // Toggle modo fechas / semanas
              InkWell(
                onTap: () => _toggleModoFechas(index),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: _periodosEnModoFechas.contains(index)
                        ? AppTheme.primary.withValues(alpha: 0.15)
                        : AppTheme.dividerColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    _periodosEnModoFechas.contains(index)
                        ? Icons.edit_calendar
                        : Icons.calendar_today,
                    size: 13,
                    color: _periodosEnModoFechas.contains(index)
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          // Date range row (shown only in "fechas" mode)
          if (_periodosEnModoFechas.contains(index)) ...[
            const SizedBox(height: 3),
            _buildPeriodoFechasRow(provider, index, periodo),
          ],
        ],
      ),
    );
  }

  /// Toggles a period row between "semanas" (manual) and "fechas" mode.
  void _toggleModoFechas(int index) {
    setState(() {
      if (!_periodosEnModoFechas.remove(index)) {
        _periodosEnModoFechas.add(index);
      }
    });
  }

  /// Builds the date-range row for a period: Fecha Inicio + Fecha Fin pickers.
  /// When both dates are set, weeks are computed as (fin - inicio).days / 7
  /// and written to the period, mirroring the Excel SAL. PROM MOD 40 columns.
  Widget _buildPeriodoFechasRow(
    RetroactiveProvider provider,
    int index,
    PeriodoSalarial periodo,
  ) {
    final inicio = periodo.fechaInicio;
    final fin = periodo.fechaTermino;
    final tieneAmbas = inicio != null && fin != null;
    final semanasCalculadas =
        tieneAmbas ? fin.difference(inicio).inDays / 7.0 : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildFechaButton(
              label: 'Inicio',
              fecha: inicio,
              icon: Icons.event_available,
              onTap: () => _pickFechaPeriodo(provider, index, periodo, true),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildFechaButton(
              label: 'Fin',
              fecha: fin,
              icon: Icons.event_busy,
              onTap: () => _pickFechaPeriodo(provider, index, periodo, false),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            tieneAmbas
                ? '${semanasCalculadas.toStringAsFixed(2)} sem'
                : 'Fechas → sem',
            style: TextStyle(
              fontSize: AppTheme.fontSizeTableData,
              fontWeight: FontWeight.w600,
              color: tieneAmbas ? AppTheme.primary : AppTheme.textHint,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact date button used in the period date-range row.
  Widget _buildFechaButton({
    required String label,
    required DateTime? fecha,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppTheme.primary),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                fecha != null ? _formatDate(fecha) : '$label: —',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTheme.fontSizeTableData,
                  color: fecha != null
                      ? AppTheme.textPrimary
                      : AppTheme.textHint,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens a date picker for a period and, when both dates are set,
  /// computes the weeks and persists them on the period.
  Future<void> _pickFechaPeriodo(
    RetroactiveProvider provider,
    int index,
    PeriodoSalarial periodo,
    bool esInicio,
  ) async {
    final now = DateTime.now();
    final current = esInicio ? periodo.fechaInicio : periodo.fechaTermino;
    final firstDate = esInicio
        ? DateTime(now.year - 50)
        : (periodo.fechaInicio ?? DateTime(now.year - 50));
    final lastDate = esInicio ? now : DateTime(now.year + 5);

    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (esInicio ? DateTime(now.year - 1, now.month, now.day) : now),
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: esInicio ? 'Selecciona fecha de inicio' : 'Selecciona fecha de fin',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null || !mounted) return;

    final updated = esInicio
        ? periodo.copyWith(fechaInicio: picked)
        : periodo.copyWith(fechaTermino: picked);

    // If both dates are present, auto-compute weeks (dias / 7).
    if (updated.fechaInicio != null && updated.fechaTermino != null) {
      final dias = updated.fechaTermino!.difference(updated.fechaInicio!).inDays;
      if (dias >= 0) {
        updated.semanas = dias / 7.0;
      }
    }
    provider.updatePeriodo(index, updated);
  }

  /// Builds the summary row showing total semanas and weighted average.
  Widget _buildPeriodosSummary(
      List<PeriodoSalarial> periodos, int totalSemanasPromedio) {
    final totalSemanas =
        periodos.fold<double>(0, (sum, p) => sum + p.semanas);
    final sumaResultados =
        periodos.fold<double>(0, (sum, p) => sum + p.resultado);
    final promedio = totalSemanasPromedio > 0 ? sumaResultados / totalSemanasPromedio : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate, size: 13, color: AppTheme.primary.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Total: ${totalSemanas.toStringAsFixed(2)} / $totalSemanasPromedio sem  ·  Prom: \$${promedio.toStringAsFixed(4)}',
              style: TextStyle(
                fontSize: AppTheme.fontSizeTableData,
                fontWeight: FontWeight.w500,
                color: AppTheme.primary.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(RetroactiveProvider provider) {
    return ElevatedButton.icon(
      onPressed: () => _saveConfiguration(provider),
      icon: const Icon(Icons.save, size: 14),
      label: const Text('Guardar',
          style: TextStyle(
              fontSize: AppTheme.fontSizeBody,
              fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6)),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Future<void> _saveConfiguration(RetroactiveProvider provider) async {
    // La pensión SIEMPRE se proyecta a la edad de retiro: el guardado nunca
    // se bloquea por edad ni por semanas.
    await provider.persistAll();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Configuración guardada correctamente'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Icon(icon, size: 13, color: AppTheme.primary),
        const SizedBox(width: 3),
        Text(
          title,
          style: const TextStyle(
            fontSize: AppTheme.fontSizeCardTitle,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Compact edad retiro dropdown with label above (uniform with other fields).
  Widget _buildEdadRetiroCompact(
    RetroactiveProvider provider,
    double currentValue,
    ValueChanged<double?> onChanged,
    Color color,
  ) {
    final List<double> ages = provider.availableAgesRetiro;
    final rules = provider.evaluator.metadata.financialRules;
    
    // Helper to get percentage for an age
    String getPercentageText(double age) {
      final edadEntera = rules.edadRoundingRule.roundToInteger(age);
      final entry = rules.pensionAgePercentages.cast<PensionAgePercentage?>().firstWhere(
        (p) => p!.age == edadEntera,
        orElse: () => null,
      );
      if (entry != null) {
        return '${(entry.percentage * 100).toInt()}%';
      }
      if (edadEntera >= 65) {
        return '100%';
      }
      return '';
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label above the dropdown (uniform with other fields)
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text('Edad',
              style: const TextStyle(
                fontSize: AppTheme.fontSizeBodySmall,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              )),
        ),
        // Dropdown — compact, matches text field height exactly
        Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          alignment: Alignment.centerLeft,
          child: DropdownButton<double>(
            value: currentValue,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox(),
            style: const TextStyle(fontSize: AppTheme.fontSizeInput, color: AppTheme.textPrimary),
            items: ages
                .map((e) {
                  final percentageText = getPercentageText(e);
                  final ageText = e == e.roundToDouble()
                      ? '${e.toInt()} años'
                      : '${e.toStringAsFixed(2)} años';
                  final displayText = percentageText.isNotEmpty
                      ? '$ageText ($percentageText)'
                      : ageText;
                  return DropdownMenuItem(
                    value: e,
                    child: Text(
                      displayText,
                      style: const TextStyle(fontSize: AppTheme.fontSizeInput),
                    ),
                  );
                })
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: AppTheme.fontSizeBodySmall, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: const TextStyle(
              fontSize: AppTheme.fontSizeBody,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }


  /// Builds a validated date field with real-time validation feedback.
  Widget _buildValidatedDateField(
    String label,
    TextEditingController controller,
    ValueChanged<String> onChanged,
  ) {
    return ValidatedDateField(
      label: label,
      controller: controller,
      onChanged: (value) {
        // Auto-format if user types 8 digits (with or without hyphens)
        final cleaned = value.replaceAll('-', '');
        if (cleaned.length == 8) {
          final formatted = _autoFormatDate(cleaned);
          if (formatted != value) {
            controller.text = formatted;
            controller.selection = TextSelection.collapsed(offset: formatted.length);
          }
        }
        onChanged(value);
      },
      validator: InputValidator.validateDate,
      firstDate: PensionConstants.minDate,
      lastDate: PensionConstants.maxDate,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      compact: true,
    );
  }


  /// Builds a validated number field with real-time validation feedback.
  Widget _buildValidatedNumberField(
    String label,
    TextEditingController controller,
    ValueChanged<String> onChanged,
    ValidationFunction validator,
  ) {
    return ValidatedTextField(
      label: label,
      controller: controller,
      onChanged: (value) {
        onChanged(value);
      },
      validator: validator,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      compact: true,
    );
  }
}

/// Holds a pair of [TextEditingController]s for a single period row
/// (salario and semanas). Using controllers instead of initialValue+ValueKey
/// prevents focus loss on rebuild because the controller retains its text
/// state independently of the widget lifecycle.
class _PeriodoControllers {
  final TextEditingController salario;
  final TextEditingController semanas;
  final FocusNode salarioFocus;
  final FocusNode semanasFocus;

  _PeriodoControllers(
    this.salario,
    this.semanas,
    this.salarioFocus,
    this.semanasFocus,
  );
}
