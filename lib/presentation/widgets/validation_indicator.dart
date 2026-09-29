import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/input_validator.dart';

/// Visual indicator for input validation status
/// Shows appropriate icon and color based on validation result
class ValidationIndicator extends StatelessWidget {
  final ValidationResult validation;
  final String? tooltipMessage;
  final double size;

  const ValidationIndicator({
    super.key,
    required this.validation,
    this.tooltipMessage,
    this.size = 20.0,
  });

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String defaultTooltip;

    if (validation.isWarning) {
      // Los warnings tienen isValid=true, así que deben revisarse ANTES que el
      // caso "válido" para no pintarse como check verde.
      icon = Icons.warning_amber_rounded;
      color = const Color(0xFFF9A825); // Yellow for warning
      defaultTooltip = 'Warning: ${validation.message}';
    } else if (validation.isValid) {
      icon = Icons.check_circle;
      color = const Color(0xFF4CAF50); // Green for success
      defaultTooltip = 'Valid input';
    } else {
      icon = Icons.error;
      color = const Color(0xFFF44336); // Red for error
      defaultTooltip = 'Error: ${validation.message}';
    }

    return Tooltip(
      message: tooltipMessage ?? defaultTooltip,
      child: Icon(icon, color: color, size: size),
    );
  }
}

/// Validation-aware text field with real-time feedback
class ValidatedTextField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputType keyboardType;
  final bool enabled;
  final bool neutralStyle;
  final ValidationFunction validator;
  final EdgeInsetsGeometry? padding;
  final bool compact;

  const ValidatedTextField({
    super.key,
    required this.label,
    this.initialValue,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.keyboardType = TextInputType.text,
    this.enabled = true,
    this.neutralStyle = false,
    required this.validator,
    this.padding,
    this.compact = false,
  });

  @override
  State<ValidatedTextField> createState() => _ValidatedTextFieldState();
}

class _ValidatedTextFieldState extends State<ValidatedTextField> {
  late TextEditingController _controller;
  ValidationResult _validation = ValidationResult.valid();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        TextEditingController(text: widget.initialValue ?? '');
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      _validate(widget.initialValue!);
    }
  }

  @override
  void didUpdateWidget(covariant ValidatedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      // If controller changed, we need to update our reference
      // This is a rare case, but we handle it
      _controller = widget.controller ?? _controller;
    }
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue ?? '';
      _validate(widget.initialValue ?? '');
    }
  }

  @override
  void dispose() {
    // Only dispose the controller if we created it internally
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _validate(String value) {
    setState(() {
      _validation = widget.validator(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: widget.padding ?? const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.compact
                  ? AppTheme.fontSizeBodySmall
                  : AppTheme.fontSizeBody,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: widget.compact ? 2 : 4),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  // Altura canónica: fija la caja a AppTheme.fieldHeight de
                  // forma determinista (no depende del padding interno).
                  height: AppTheme.fieldHeight,
                  child: TextField(
                    controller: _controller,
                    onChanged: (value) {
                      _validate(value);
                      widget.onChanged?.call(value);
                    },
                    onSubmitted: widget.onSubmitted,
                    keyboardType: widget.keyboardType,
                    enabled: widget.enabled,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppTheme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppTheme.dividerColor),
                      ),
                      filled: true,
                      fillColor: widget.neutralStyle || !widget.enabled
                          ? theme.colorScheme.surfaceContainerHighest
                          : AppTheme.primary.withValues(alpha: 0.08),
                      // isDense + padding vertical reducido mantienen la caja
                      // delgada; la altura exacta la garantiza el SizedBox.
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                    ),
                    onTap: () => setState(() => _isFocused = true),
                    onTapOutside: (_) => setState(() => _isFocused = false),
                  ),
                ),
              ),
              if (!widget.neutralStyle &&
                  !_isFocused &&
                  _controller.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ValidationIndicator(validation: _validation, size: 20),
                ),
            ],
          ),
          if (_validation.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                _validation.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _validation.isWarning
                      ? const Color(0xFFF9A825)
                      : const Color(0xFFF44336),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Validation-aware date field with real-time feedback and date picker
class ValidatedDateField extends StatefulWidget {
  final String label;
  final String? initialValue;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final ValidationFunction validator;
  final EdgeInsetsGeometry? padding;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final DateTime? initialDate;
  final bool compact;

  const ValidatedDateField({
    super.key,
    required this.label,
    this.initialValue,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    required this.validator,
    this.padding,
    this.firstDate,
    this.lastDate,
    this.initialDate,
    this.compact = false,
  });

  @override
  State<ValidatedDateField> createState() => _ValidatedDateFieldState();
}

class _ValidatedDateFieldState extends State<ValidatedDateField> {
  late TextEditingController _controller;
  ValidationResult _validation = ValidationResult.valid();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        TextEditingController(text: widget.initialValue ?? '');
    if (widget.initialValue != null && widget.initialValue!.isNotEmpty) {
      _validate(widget.initialValue!);
    }
  }

  @override
  void didUpdateWidget(covariant ValidatedDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller = widget.controller ?? _controller;
    }
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue ?? '';
      _validate(widget.initialValue ?? '');
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _validate(String value) {
    setState(() {
      _validation = widget.validator(value);
    });
  }

  Future<void> _showDatePicker(BuildContext context) async {
    final initialDate = widget.initialDate ?? DateTime.now();
    final firstDate = widget.firstDate ?? DateTime(1900);
    final lastDate = widget.lastDate ?? DateTime(2100);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Seleccionar ${widget.label}',
      cancelText: 'Cancelar',
      confirmText: 'Aceptar',
    );

    if (picked != null) {
      final formatted =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      _controller.text = formatted;
      _validate(formatted);
      widget.onChanged?.call(formatted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: widget.padding ?? const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.compact
                  ? AppTheme.fontSizeBodySmall
                  : AppTheme.fontSizeBody,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: widget.compact ? 2 : 4),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  // Altura canónica: fija la caja a AppTheme.fieldHeight de
                  // forma determinista (no depende del padding interno).
                  height: AppTheme.fieldHeight,
                  child: TextField(
                    controller: _controller,
                    onChanged: (value) {
                      _validate(value);
                      widget.onChanged?.call(value);
                    },
                    onSubmitted: widget.onSubmitted,
                    enabled: widget.enabled,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppTheme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppTheme.dividerColor),
                      ),
                      filled: true,
                      fillColor: widget.enabled
                          ? AppTheme.primary.withValues(alpha: 0.08)
                          : theme.colorScheme.surfaceContainerHighest,
                      // isDense + padding vertical reducido mantienen la caja
                      // delgada; la altura exacta la garantiza el SizedBox.
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 2,
                      ),
                      // Se usa "suffix" (no "suffixIcon") porque suffixIcon fuerza
                      // una altura minima de 48px (kMinInteractiveDimension) y la
                      // caja de la fecha quedaria mas alta que las demas.
                      suffix: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showDatePicker(context),
                        child: Semantics(
                          label: 'Seleccionar fecha',
                          button: true,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(Icons.calendar_month, size: 16),
                          ),
                        ),
                      ),
                    ),
                    onTap: () => setState(() => _isFocused = true),
                    onTapOutside: (_) => setState(() => _isFocused = false),
                  ),
                ),
              ),
              if (!_isFocused && _controller.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ValidationIndicator(validation: _validation, size: 20),
                ),
            ],
          ),
          if (_validation.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                _validation.message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _validation.isWarning
                      ? const Color(0xFFF9A825)
                      : const Color(0xFFF44336),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
