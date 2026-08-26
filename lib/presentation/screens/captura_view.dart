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

/// Data capture view with all four sections on one scrollable screen.
///
/// Layout natural-height con espaciado cómodo: cada sección ocupa solo el
/// espacio que su contenido necesita y las separaciones (márgenes, gaps y
/// padding interno) son amplias para que el formulario se lea fácil, pensado
/// para personas mayores. El scroll es solo una red de seguridad en ventanas
/// muy cortas, no un requisito para llegar a todos los campos.
///
/// Tres secciones:
/// - DATOS PERSONALES (fecha cálculo, nacimiento, fecha de alta, esposa, hijos, padres)
/// - DATOS LABORALES (salario, semanas antes Mod40, edad retiro, UMA, salario mínimo)
/// - MODALIDAD 40 (inicio, semanas, salario, total y desglose de periodos)
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
  late TextEditingController _fechaAltaController;
  late TextEditingController _salarioPromedio250Controller;
  late TextEditingController _semanasCotizadasController;
  late TextEditingController _semanasEnMod40Controller;
  late TextEditingController _salarioPromedioController;
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
    _fechaAltaController = TextEditingController(
      text: p.fechaAlta != null ? _formatDate(p.fechaAlta!) : '',
    );
    _salarioPromedio250Controller = TextEditingController(
      text: p.salarioPromedio250Semanas.toStringAsFixed(2),
    );
    _semanasCotizadasController = TextEditingController(
      text: p.semanasCotizadas.toString(),
    );
    _semanasEnMod40Controller = TextEditingController(
      text: p.semanasEnMod40.toStringAsFixed(0),
    );
    _salarioPromedioController = TextEditingController(
      text: p.salarioDiarioPromedio.toStringAsFixed(2),
    );
    _numeroHijosController = TextEditingController(
      text: p.numeroHijos.toString(),
    );
    _numeroPadresController = TextEditingController(
      text: p.numeroPadres.toString(),
    );
    _umaDiariaController = TextEditingController(
      text: p.umaDiaria.toStringAsFixed(2),
    );
    _salarioMinimoDiarioController = TextEditingController(
      text: p.salarioMinimoDiario.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _fechaCalculoController.dispose();
    _fechaNacimientoController.dispose();
    _fechaAltaController.dispose();
    _salarioPromedio250Controller.dispose();
    _semanasCotizadasController.dispose();
    _semanasEnMod40Controller.dispose();
    _salarioPromedioController.dispose();
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
        _periodoControllers.add(
          _PeriodoControllers(
            TextEditingController(
              text: periodos[i].salarioDiario.toStringAsFixed(2),
            ),
            TextEditingController(text: periodos[i].semanas.toStringAsFixed(2)),
            FocusNode(),
            FocusNode(),
          ),
        );
      } else {
        final controller = _periodoControllers[i];
        if (!controller.salarioFocus.hasFocus) {
          _setControllerText(
            controller.salario,
            periodos[i].salarioDiario.toStringAsFixed(2),
          );
        }
        if (!controller.semanasFocus.hasFocus) {
          _setControllerText(
            controller.semanas,
            periodos[i].semanas.toStringAsFixed(2),
          );
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
    for (
      int i = 0;
      i < periodos.length && i < _periodoControllers.length;
      i++
    ) {
      _periodoControllers[i].salario.text = periodos[i].salarioDiario
          .toStringAsFixed(2);
      _periodoControllers[i].semanas.text = periodos[i].semanas.toStringAsFixed(
        2,
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Parses date from YYYY-MM-DD or YYYYMMDD format.
  /// Returns null when the text cannot be parsed into a valid date (never
  /// falls back to "today", which would silently corrupt the state).
  DateTime? _parseDate(String text) {
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
    return null;
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
    _setControllerText(
      _umaDiariaController,
      provider.umaDiaria.toStringAsFixed(2),
    );
    _setControllerText(
      _salarioMinimoDiarioController,
      provider.salarioMinimoDiario.toStringAsFixed(2),
    );
    _setControllerText(
      _salarioPromedio250Controller,
      provider.salarioPromedio250Semanas.toStringAsFixed(2),
    );
    _setControllerText(
      _salarioPromedioController,
      provider.salarioDiarioPromedio.toStringAsFixed(2),
    );
    _setControllerText(
      _semanasEnMod40Controller,
      provider.semanasEnMod40.toStringAsFixed(0),
    );
    _setControllerText(
      _semanasCotizadasController,
      provider.semanasCotizadas.toString(),
    );
    // Sincronizar también los campos que la IA puede haber corregido, para que
    // las correcciones (p. ej. padres = 1) se reflejen en la vista de captura.
    _setControllerText(
      _fechaCalculoController,
      _formatDate(provider.fechaCalculo),
    );
    _setControllerText(
      _fechaNacimientoController,
      _formatDate(provider.fechaNacimiento),
    );
    _setControllerText(
      _fechaAltaController,
      provider.fechaAlta != null ? _formatDate(provider.fechaAlta!) : '',
    );
    _setControllerText(_numeroHijosController, provider.numeroHijos.toString());
    _setControllerText(
      _numeroPadresController,
      provider.numeroPadres.toString(),
    );
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
        // needs (no stretching, no hidden fields). Márgenes y separaciones
        // amplios para que el formulario respire y sea fácil de leer (usuarios
        // mayores); el scroll es solo una red de seguridad en ventanas cortas.
        // Las áreas de error/advertencia se insertan solo cuando hay mensajes,
        // evitando renglones vacíos desperdiciados bajo el encabezado.
        final errorArea = _buildErrorArea(provider);
        final warningArea = _buildWarningArea(provider);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            12,
            AppTheme.spacingXs,
            12,
            AppTheme.spacingXs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              if (errorArea != null) ...[
                const SizedBox(height: AppTheme.spacingXs),
                errorArea,
              ],
              if (warningArea != null) ...[
                const SizedBox(height: AppTheme.spacingXs),
                warningArea,
              ],
              const SizedBox(height: AppTheme.spacingXs),
              _buildDatosPersonales(provider),
              const SizedBox(height: AppTheme.spacingXs),
              _buildDatosLaborales(provider),
              const SizedBox(height: AppTheme.spacingXs),
              _buildDatosMod40(provider),
              const SizedBox(height: AppTheme.spacingXs),
              _buildSaveButton(provider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: AppTheme.spacingSm,
      ),
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
            child: const Icon(
              Icons.edit_note,
              color: AppTheme.accent,
              size: 14,
            ),
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

  /// Área de mensajes de error (consola roja).
  ///
  /// Muestra únicamente los errores globales que bloquean Calcular/Guardar.
  /// Si no hay errores, no pinta nada (null). Las advertencias
  /// informativas van en [_buildWarningArea] (amarillas).
  Widget? _buildErrorArea(RetroactiveProvider provider) {
    final errores = provider.validacionesGlobales
        .where((v) => !v.isValid)
        .toList();

    if (errores.isEmpty) {
      return null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEF9A9A), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final v in errores)
            _buildValidationRow(v, const Color(0xFFC62828), Icons.error),
        ],
      ),
    );
  }

  Widget _buildValidationRow(ValidationResult v, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              v.message,
              style: TextStyle(fontSize: 12, color: color, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  /// Área de mensajes de advertencia (amarilla / informativa).
  ///
  /// Muestra las advertencias globales (isWarning) que NO bloquean el
  /// cálculo, p. ej. el tope de 25 UMAs (el excedente no cotiza) o el aviso
  /// de incrementos negativos. Si no hay advertencias, no pinta nada (null).
  Widget? _buildWarningArea(RetroactiveProvider provider) {
    final advertencias = provider.validacionesGlobales
        .where((v) => v.isWarning && v.message.isNotEmpty)
        .toList();

    if (advertencias.isEmpty) {
      return null;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFE082), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final v in advertencias)
            _buildValidationRow(
              v,
              const Color(0xFFF9A825),
              Icons.warning_amber_rounded,
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
        padding: const EdgeInsets.fromLTRB(
          12,
          AppTheme.spacingXs,
          12,
          AppTheme.spacingXs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(Icons.person, 'Datos Personales'),
            const SizedBox(height: 1),
            // Fecha Cálculo + Fecha Nacimiento side by side
            Row(
              children: [
                Expanded(
                  child: _buildValidatedDateField(
                    'Fecha de Cálculo',
                    _fechaCalculoController,
                    (v) {
                      final parsed = _parseDate(v);
                      if (parsed != null) {
                        provider.setFechaCalculo(parsed);
                      }
                    },
                    // Regla D: la fecha de cálculo no puede ser anterior a la
                    // de nacimiento.
                    validator: (v) {
                      final base = InputValidator.validateDate(v);
                      if (!base.isValid) return base;
                      final parsed = _parseDate(v);
                      if (parsed != null &&
                          parsed.isBefore(provider.fechaNacimiento)) {
                        return ValidationResult.error(
                          PensionConstants.errorFechaCalculoMenorNacimiento,
                        );
                      }
                      return base;
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildValidatedDateField(
                    'Fecha de Nacimiento',
                    _fechaNacimientoController,
                    (v) {
                      final parsed = _parseDate(v);
                      if (parsed != null) {
                        provider.setFechaNacimiento(parsed);
                      }
                    },
                    // Regla D (inverso: el nacimiento no puede ser posterior a
                    // la fecha de cálculo). La Regla A (aplicabilidad Ley 73)
                    // NO se valida aquí a propósito: su mensaje se muestra UNA
                    // sola vez, en el banner superior de errores globales.
                    validator: (v) {
                      final base = InputValidator.validateDate(v);
                      if (!base.isValid) return base;
                      final parsed = _parseDate(v);
                      if (parsed != null) {
                        if (parsed.isAfter(provider.fechaCalculo)) {
                          return ValidationResult.error(
                            PensionConstants.errorFechaCalculoMenorNacimiento,
                          );
                        }
                      }
                      return base;
                    },
                  ),
                ),
              ],
            ),
            // Fecha de Alta (IMSS): opcional, confirma la aplicabilidad de la
            // Ley 73 (el factor es haber cotizado antes del 1 de julio de 1997).
            // Campo vacío = "no capturado" (válido, se muestra un aviso suave).
            _buildValidatedDateField(
              'Fecha de Alta (IMSS)',
              _fechaAltaController,
              (v) {
                if (v.trim().isEmpty) {
                  provider.setFechaAlta(null);
                  return;
                }
                final parsed = _parseDate(v);
                if (parsed != null) {
                  provider.setFechaAlta(parsed);
                }
              },
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
                        child: Text(
                          '¿Esposa?',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeBodySmall,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () =>
                            provider.setTieneEsposa(!provider.tieneEsposa),
                        child: Container(
                          height: AppTheme.fieldHeight,
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
                                provider.tieneEsposa
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 20,
                                color: provider.tieneEsposa
                                    ? const Color(0xFF4CAF50)
                                    : AppTheme.textHint,
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
                  child: _buildValidatedNumberField(
                    'Hijos',
                    _numeroHijosController,
                    (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) provider.setNumeroHijos(parsed);
                    },
                    (value) {
                      if (value.isEmpty) return ValidationResult.valid();
                      final parsed = int.tryParse(value);
                      if (parsed == null) {
                        return ValidationResult.error(
                          'Debe ser un número entero',
                        );
                      }
                      if (parsed < 0) {
                        return ValidationResult.error('No puede ser negativo');
                      }
                      if (parsed > 20) {
                        return ValidationResult.warning('Valor alto de hijos');
                      }
                      return ValidationResult.valid();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 3,
                  child: _buildValidatedNumberField(
                    'Padres',
                    _numeroPadresController,
                    (v) {
                      final parsed = int.tryParse(v);
                      if (parsed != null) provider.setNumeroPadres(parsed);
                    },
                    (value) {
                      if (value.isEmpty) return ValidationResult.valid();
                      final parsed = int.tryParse(value);
                      if (parsed == null) {
                        return ValidationResult.error(
                          'Debe ser un número entero',
                        );
                      }
                      if (parsed < 0) {
                        return ValidationResult.error('No puede ser negativo');
                      }
                      if (parsed > 4) {
                        return ValidationResult.warning('Valor alto de padres');
                      }
                      return ValidationResult.valid();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
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
        padding: const EdgeInsets.fromLTRB(
          12,
          AppTheme.spacingXs,
          12,
          AppTheme.spacingXs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(Icons.work, 'Datos Laborales'),
            const SizedBox(height: 1),
            // Semanas antes Mod40 + Edad Retiro side by side
            Row(
              children: [
                Expanded(
                  // "Semanas cotizadas" = historial IMSS ANTES de Modalidad 40
                  // (fuente primaria); el total CON Mod40 se deriva en el cálculo.
                  child: _buildValidatedNumberField(
                    'Semanas cotizadas IMSS',
                    _semanasCotizadasController,
                    (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) {
                        provider.setSemanasCotizadas(parsed.round());
                      }
                    },
                    (value) {
                      if (value.isEmpty) return ValidationResult.valid();
                      final parsed = double.tryParse(value);
                      if (parsed == null) {
                        return ValidationResult.error(
                          'Debe ser un número válido',
                        );
                      }
                      if (parsed < 0) {
                        return ValidationResult.error('No puede ser negativo');
                      }
                      if (parsed > 5000) {
                        return ValidationResult.warning(
                          'Valor muy alto de semanas',
                        );
                      }
                      return ValidationResult.valid();
                    },
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildEdadRetiroCompact(
                    provider,
                    provider.edadRetiro,
                    (v) {
                      if (v != null) provider.setEdadRetiro(v);
                    },
                    AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            // UMA Diaria + Salario Mínimo Diario side by side
            Row(
              children: [
                Expanded(
                  child: _buildValidatedNumberField(
                    'UMA Diaria',
                    _umaDiariaController,
                    (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) provider.setUmaDiaria(parsed);
                    },
                    (value) {
                      if (value.isEmpty) return ValidationResult.valid();
                      final parsed = double.tryParse(value);
                      if (parsed == null) {
                        return ValidationResult.error(
                          'Debe ser un número válido',
                        );
                      }
                      if (parsed <= 0) {
                        return ValidationResult.error('Debe ser mayor a cero');
                      }
                      if (parsed > 1000) {
                        return ValidationResult.warning(
                          'Valor muy alto de UMA',
                        );
                      }
                      return ValidationResult.valid();
                    },
                    neutralStyle: true,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildValidatedNumberField(
                    'Salario Mínimo Diario',
                    _salarioMinimoDiarioController,
                    (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) {
                        provider.setSalarioMinimoDiario(parsed);
                      }
                    },
                    InputValidator.validateSalary,
                    neutralStyle: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            _buildReadOnlyField(
              'Salario Promedio 250 Semanas',
              provider.salarioPromedio250Semanas.toStringAsFixed(2),
            ),
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
        padding: const EdgeInsets.fromLTRB(
          12,
          AppTheme.spacingXs,
          12,
          AppTheme.spacingXs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pregunta clara con dos botones grandes (Sí / No). El toggle
            // permanece en la misma posición de scroll: la sección se expande
            // o colapsa debajo, nunca se navega a otra pantalla.
            _buildModalidad40Toggle(provider),
            if (!provider.modalidad40OptOut) ...[
              const SizedBox(height: 1),
              // UMA Multiplier selector (1-25)
              _buildUmaMultiplierField(provider),
              const SizedBox(height: 1),
              // Desglose de salario promedio y Modalidad 40 (periodos
              // detallados): va entre el campo "UMAs a pagar" y los resultados
              // de semanas, dentro de la tarjeta de Modalidad 40.
              _buildDesglosePeriodos(provider),
              const SizedBox(height: 1),
              // Resultados Mod40: etiqueta con ancho natural a la izquierda y
              // valor pegado al borde derecho. La caja ocupa todo el ancho de
              // la tarjeta, sin padding izquierdo y con interlineado mínimo
              // para que las etiquetas se vean completas (sin truncar).
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildReadOnlyField(
                    'Semanas en Mod40',
                    provider.semanasEnMod40.toStringAsFixed(0),
                  ),
                  const SizedBox(height: 1),
                  _buildReadOnlyField(
                    'Semanas Totales',
                    provider.totalSemanasConMod40.toStringAsFixed(0),
                  ),
                  const SizedBox(height: 1),
                  _buildReadOnlyField(
                    'Salario Promedio (con Mod40)',
                    provider.nuevoSalarioPromedio.toStringAsFixed(0),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 1),
              _buildSinMod40Message(),
            ],
          ],
        ),
      ),
    );
  }

  /// Pregunta principal de Modalidad 40 con dos botones grandes (Sí / No).
  /// Se mantiene SIEMPRE visible en la misma posición de scroll; al elegir
  /// "No" la sección se colapsa debajo y el cálculo corre por la ruta "Sin M40".
  Widget _buildModalidad40Toggle(RetroactiveProvider provider) {
    final optedOut = provider.modalidad40OptOut;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(
            '¿Vas a aportar Modalidad 40?',
            style: const TextStyle(
              fontSize: AppTheme.fontSizeInput,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildToggleOption(
                label: 'Sí',
                selected: !optedOut,
                onTap: () => provider.setModalidad40OptOut(false),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildToggleOption(
                label: 'No',
                selected: optedOut,
                onTap: () => provider.setModalidad40OptOut(true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Botón grande de selección (Sí / No) con estado visual claro.
  Widget _buildToggleOption({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.primary, width: selected ? 2 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTheme.fontSizeCardTitle,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  /// Mensaje breve y tranquilizador cuando el usuario elige "No" a Mod40.
  Widget _buildSinMod40Message() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.backgroundLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.dividerColor),
      ),
      child: const Text(
        'Sin Modalidad 40 tu pensión se calcula con las semanas que cotizaste '
        'ante el IMSS. No necesitas llenar más datos.',
        style: TextStyle(
          fontSize: AppTheme.fontSizeInput,
          color: AppTheme.textSecondary,
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
      height: AppTheme.fieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
          // Dropdown con ancho natural (sin isExpanded): el texto seleccionado
          // se muestra completo, p. ej. "15 UMAs". Label y "= $..." son
          // Expanded y absorben el espacio sobrante de la fila.
          DropdownButton<double>(
            value: multiplier,
            isDense: true,
            underline: const SizedBox(),
            items: List.generate(25, (i) => i + 1).map((v) {
              final val = v.toDouble();
              return DropdownMenuItem<double>(
                value: val,
                child: Text(
                  '$v UMAs',
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
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        collapsedBackgroundColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            Flexible(
              child: Text(
                'Captura de salario promedio y Modalidad 40',
                // Dos renglones para aprovechar el espacio sin truncar el
                // titulo; el badge (Desglose) se mantiene a la derecha y el
                // texto completo es visible incluso en pantallas angostas.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTheme.fontSizeLabel,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '(Desglose)',
                style: TextStyle(
                  fontSize: AppTheme.fontSizeTableData,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
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
          // Action buttons row — Wrap para que nunca se desborde en pantallas
          // angostas ni con escalado de texto accesible.
          Wrap(
            spacing: AppTheme.spacingSm,
            runSpacing: AppTheme.spacingXs,
            children: [
              // Add period button — compact text button
              TextButton.icon(
                onPressed: () => provider.addPeriodo(),
                icon: const Icon(Icons.add, size: 13),
                label: const Text(
                  'Agregar periodo',
                  style: TextStyle(fontSize: AppTheme.fontSizeBodySmall),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              // Reload Excel baseline data button
              TextButton.icon(
                onPressed: () {
                  provider.resetPeriodosToBaseline();
                  // Force-sync controllers to match the new baseline values
                  _forceSyncPeriodoControllers(provider);
                },
                icon: const Icon(Icons.restore, size: 13),
                label: const Text(
                  'Recargar datos Excel',
                  style: TextStyle(fontSize: AppTheme.fontSizeBodySmall),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.warningColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
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
                          periodo.esMod40 ? 'M40' : 'P${index + 1}',
                          style: TextStyle(
                            fontSize: AppTheme.fontSizeTableData,
                            fontWeight: FontWeight.w500,
                            color: periodo.esMod40
                                ? AppTheme.primary
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    if (!periodo.esMod40) ...[
                      const SizedBox(width: 2),
                      GestureDetector(
                        onTap: () => provider.removePeriodo(index),
                        child: Icon(
                          Icons.remove_circle_outline,
                          size: 13,
                          color: AppTheme.errorColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 2),
              // Salario Diario
              Expanded(
                child: SizedBox(
                  height: AppTheme.fieldHeight,
                  child: TextFormField(
                    key: ValueKey('sal_$index'),
                    controller: controllers?.salario,
                    decoration: const InputDecoration(
                      labelText: 'Salario',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: AppTheme.fontSizeTableData,
                    ),
                    focusNode: controllers?.salarioFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                  height: AppTheme.fieldHeight,
                  child: TextFormField(
                    key: ValueKey('sem_$index'),
                    controller: controllers?.semanas,
                    decoration: const InputDecoration(
                      labelText: 'Semanas',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      isDense: true,
                    ),
                    style: const TextStyle(
                      fontSize: AppTheme.fontSizeTableData,
                    ),
                    focusNode: controllers?.semanasFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                  '\$${periodo.resultado.toStringAsFixed(0)}',
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
    final semanasCalculadas = tieneAmbas
        ? fin.difference(inicio).inDays / 7.0
        : 0.0;

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
          Flexible(
            child: Text(
              tieneAmbas
                  ? '${semanasCalculadas.toStringAsFixed(2)} sem'
                  : 'Fechas → sem',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: AppTheme.fontSizeTableData,
                fontWeight: FontWeight.w600,
                color: tieneAmbas ? AppTheme.primary : AppTheme.textHint,
              ),
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
    // Altura canónica: la caja usa AppTheme.fieldHeight igual que el resto de
    // los campos de la pantalla de captura.
    return SizedBox(
      height: AppTheme.fieldHeight,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
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
                  maxLines: 1,
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
      initialDate:
          current ??
          (esInicio ? DateTime(now.year - 1, now.month, now.day) : now),
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: esInicio
          ? 'Selecciona fecha de inicio'
          : 'Selecciona fecha de fin',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );
    if (picked == null || !mounted) return;

    final updated = esInicio
        ? periodo.copyWith(fechaInicio: picked)
        : periodo.copyWith(fechaTermino: picked);

    // If both dates are present, auto-compute weeks (dias / 7).
    if (updated.fechaInicio != null && updated.fechaTermino != null) {
      final dias = updated.fechaTermino!
          .difference(updated.fechaInicio!)
          .inDays;
      if (dias >= 0) {
        updated.semanas = dias / 7.0;
      }
    }
    provider.updatePeriodo(index, updated);
  }

  /// Builds the summary row showing total semanas and weighted average.
  Widget _buildPeriodosSummary(
    List<PeriodoSalarial> periodos,
    int totalSemanasPromedio,
  ) {
    final totalSemanas = periodos.fold<double>(0, (sum, p) => sum + p.semanas);
    final sumaResultados = periodos.fold<double>(
      0,
      (sum, p) => sum + p.resultado,
    );
    final promedio = totalSemanasPromedio > 0
        ? sumaResultados / totalSemanasPromedio
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calculate,
            size: 13,
            color: AppTheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Total: ${totalSemanas.round()} / $totalSemanasPromedio sem  ·  Prom: \$${promedio.toStringAsFixed(0)}',
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
    // Regla C: con errores bloqueantes el guardado queda deshabilitado.
    final bloqueado = provider.hasBlockingErrors;
    return ElevatedButton.icon(
      onPressed: bloqueado ? null : () => _saveConfiguration(provider),
      icon: const Icon(Icons.save, size: 14),
      label: Text(
        bloqueado ? 'Guardar bloqueado' : 'Guardar',
        style: const TextStyle(
          fontSize: AppTheme.fontSizeBody,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey.shade400,
        disabledForegroundColor: Colors.white70,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingLg,
          vertical: AppTheme.spacingSm,
        ),
      ),
    );
  }

  Future<void> _saveConfiguration(RetroactiveProvider provider) async {
    // Regla C: con errores bloqueantes NO se persiste nada.
    if (provider.hasBlockingErrors) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se puede guardar: corrige los errores indicados en la consola',
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFC62828),
        ),
      );
      return;
    }
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
    // Flujo natural Captura → Pensión: tras guardar, se lleva al usuario a la
    // pestaña Pensión para que vea su resultado sin pasos extra. El SnackBar
    // persiste al cambiar de pestaña (ScaffoldMessenger es global a la app).
    // Cambio defensivo: solo si existe un DefaultTabController ancestro
    // (DefaultTabController.of lanza si no hay; así no se rompen los tests que
    // montan CapturaView suelto sin el shell de pestañas).
    if (context.findAncestorWidgetOfExactType<DefaultTabController>() != null) {
      DefaultTabController.of(context).animateTo(2);
    }
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

    // Resguardo defensivo: si el valor actual quedó fuera de la rejilla legal
    // (p. ej. 60.5 por datos legacy o una IA que devolvió .5), se ajusta al
    // punto válido más cercano. Un DropdownButton con un `value` que no tiene
    // su DropdownMenuItem se renderiza en blanco (o lanza en debug).
    final safeValue = ages.contains(currentValue)
        ? currentValue
        : rules.pensionAgeDropdown.nearestAge(currentValue);

    // Helper to get percentage for an age
    String getPercentageText(double age) {
      final edadEntera = rules.edadRoundingRule.roundToInteger(age);
      final entry = rules.pensionAgePercentages
          .cast<PensionAgePercentage?>()
          .firstWhere((p) => p!.age == edadEntera, orElse: () => null);
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
          child: Text(
            'Edad de pension',
            style: const TextStyle(
              fontSize: AppTheme.fontSizeBodySmall,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Dropdown — compact, usa la altura canónica de los campos
        Container(
          height: AppTheme.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.dividerColor),
          ),
          alignment: Alignment.centerLeft,
          child: DropdownButton<double>(
            value: safeValue,
            isExpanded: true,
            isDense: true,
            underline: const SizedBox(),
            style: const TextStyle(
              fontSize: AppTheme.fontSizeInput,
              color: AppTheme.textPrimary,
            ),
            items: ages.map((e) {
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
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Container(
      height: AppTheme.fieldHeight,
      padding: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.dividerColor.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Etiqueta y valor a ANCHO NATURAL (sin Flexible/Expanded, que
          // reparten el ancho a la mitad y truncan la etiqueta). Con
          // spaceBetween la etiqueta queda a la izquierda usando todo el
          // espacio y el valor pegado al borde derecho, sin desperdiciar.
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTheme.fontSizeBodySmall,
              color: AppTheme.textSecondary,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTheme.fontSizeBody,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a validated date field with real-time validation feedback.
  /// [validator] opcional permite añadir validaciones cruzadas (p. ej. contra
  /// la fecha de nacimiento) sobre la validación base de formato/rango.
  Widget _buildValidatedDateField(
    String label,
    TextEditingController controller,
    ValueChanged<String> onChanged, {
    ValidationFunction? validator,
  }) {
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
            controller.selection = TextSelection.collapsed(
              offset: formatted.length,
            );
          }
        }
        onChanged(value);
      },
      validator: validator ?? InputValidator.validateDate,
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
    ValidationFunction validator, {
    bool neutralStyle = false,
  }) {
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
      neutralStyle: neutralStyle,
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
