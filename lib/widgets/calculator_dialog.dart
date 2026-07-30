import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/utils.dart';

class CalculatorDialog extends StatefulWidget {
  final Function(double)? onResultUsed;
  const CalculatorDialog({super.key, this.onResultUsed});

  @override
  State<CalculatorDialog> createState() => _CalculatorDialogState();
}

class _CalculatorDialogState extends State<CalculatorDialog> {
  String _display = "0";
  String _topText = "";
  double? _firstOperand;
  String? _operator;
  bool _shouldResetDisplay = false;
  bool _isConverterMode = false;
  WeightUnit _sourceUnit = WeightUnit.kg;
  
  final List<String> _history = [];
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
        _onPressed("0");
      } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
        _onPressed("1");
      } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
        _onPressed("2");
      } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
        _onPressed("3");
      } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
        _onPressed("4");
      } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
        _onPressed("5");
      } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
        _onPressed("6");
      } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
        _onPressed("7");
      } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
        _onPressed("8");
      } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
        _onPressed("9");
      } else if (key == LogicalKeyboardKey.add || (key == LogicalKeyboardKey.equal && HardwareKeyboard.instance.isShiftPressed)) {
        _onPressed("+");
      } else if (key == LogicalKeyboardKey.minus || key == LogicalKeyboardKey.numpadSubtract) {
        _onPressed("-");
      } else if (key == LogicalKeyboardKey.asterisk || key == LogicalKeyboardKey.numpadMultiply) {
        _onPressed("×");
      } else if (key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.numpadDivide) {
        _onPressed("÷");
      } else if (key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.numpadDecimal) {
        _onPressed(".");
      } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        _onPressed("=");
      } else if (key == LogicalKeyboardKey.backspace) {
        _onPressed("⌫");
      } else if (key == LogicalKeyboardKey.escape) {
        _onPressed("AC");
      }
    }
  }

  void _onPressed(String cmd) {
    HapticFeedback.selectionClick();
    setState(() {
      if (cmd == "AC") {
        _display = "0";
        _topText = "";
        _firstOperand = null;
        _operator = null;
        _shouldResetDisplay = false;
      } else if (cmd == "⌫") {
        if (_display.length > 1) {
          _display = _display.substring(0, _display.length - 1);
        } else {
          _display = "0";
        }
      } else if (cmd == "=") {
        if (_firstOperand != null && _operator != null) {
          double secondOperand = double.tryParse(_display) ?? 0;
          double result = _calculate(_firstOperand!, secondOperand, _operator!);
          
          _topText = "${_format(_firstOperand!)} $_operator ${_format(secondOperand)} =";
          _display = _format(result);
          
          _history.insert(0, "$_topText $_display");
          if (_history.length > 5) {
            _history.removeLast();
          }
          
          _firstOperand = null;
          _operator = null;
          _shouldResetDisplay = true;
        }
      } else if (cmd == "%") {
        double val = (double.tryParse(_display) ?? 0) / 100;
        _display = _format(val);
      } else if ("+-×÷".contains(cmd)) {
        double currentVal = double.tryParse(_display) ?? 0;
        
        if (_firstOperand != null && _operator != null && !_shouldResetDisplay) {
          // If we already had an operation, calculate intermediate result
          _firstOperand = _calculate(_firstOperand!, currentVal, _operator!);
          _display = _format(_firstOperand!);
        } else {
          _firstOperand = currentVal;
        }
        
        _operator = cmd;
        _topText = "${_format(_firstOperand!)} $cmd";
        _shouldResetDisplay = true;
      } else {
        // Digits and decimal
        if (_shouldResetDisplay) {
          _display = cmd == "." ? "0." : cmd;
          _shouldResetDisplay = false;
        } else {
          if (cmd == "." && _display.contains(".")) return;
          if (_display == "0" && cmd != ".") {
            _display = cmd;
          } else {
            _display += cmd;
          }
        }
      }
    });
  }

  double _calculate(double n1, double n2, String op) {
    switch (op) {
      case "+": return n1 + n2;
      case "-": return n1 - n2;
      case "×": return n1 * n2;
      case "÷": return n2 == 0 ? 0 : n1 / n2;
      default: return n2;
    }
  }

  String _format(double v) {
    if (v.isInfinite || v.isNaN) return "Error";
    if (v == v.toInt()) return v.toInt().toString();
    String s = v.toStringAsFixed(4);
    while (s.endsWith("0")) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith(".")) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(4), // Square corners for rectangle look
              boxShadow: [const BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 5))],
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(theme),
                  if (_isConverterMode) _buildConverterUI(theme, isDark) else ...[
                    _buildDisplay(theme, isDark),
                    if (_history.isNotEmpty) _buildHistory(theme),
                  ],
                  _buildKeypad(theme),
                  if (widget.onResultUsed != null) _buildInjectButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      color: theme.colorScheme.primary.withValues(alpha: 0.05),
      child: Row(
        children: [
          Icon(_isConverterMode ? Icons.swap_horiz_rounded : Icons.calculate_outlined, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(_isConverterMode ? 'UNIT CONVERTER' : 'CALCULATOR', 
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: theme.colorScheme.primary, letterSpacing: 0.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          // Mode Toggle
          IconButton(
            onPressed: () => setState(() => _isConverterMode = !_isConverterMode),
            icon: Icon(_isConverterMode ? Icons.calculate_outlined : Icons.swap_horiz_rounded, size: 18, color: theme.colorScheme.primary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: _isConverterMode ? 'Calculator' : 'Converter',
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _display));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
            },
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDisplay(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black38 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(2), // Rectangle
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _topText.isEmpty ? "0" : _topText,
            style: TextStyle(fontSize: 14, color: theme.colorScheme.primary.withValues(alpha: 0.6), fontWeight: FontWeight.w500, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              _display,
              style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory(ThemeData theme) {
    return Container(
      height: 32,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _history.length,
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => setState(() {
            final parts = _history[i].split(" = ");
            _display = parts.last;
            _topText = "${parts.first} =";
            _shouldResetDisplay = true;
          }),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1)),
            ),
            child: Center(child: Text(_history[i], style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant, fontFamily: 'monospace'))),
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          _row(["AC", "%", "÷"], [Colors.red, theme.colorScheme.primary, theme.colorScheme.primary]),
          _row(["7", "8", "9", "×"], [null, null, null, theme.colorScheme.primary]),
          _row(["4", "5", "6", "-"], [null, null, null, theme.colorScheme.primary]),
          _row(["1", "2", "3", "+"], [null, null, null, theme.colorScheme.primary]),
          _row([".", "0", "⌫", "="], [null, null, Colors.orange, theme.colorScheme.primary]),
        ],
      ),
    );
  }

  Widget _row(List<String> keys, List<Color?> colors) {
    return Row(
      children: keys.asMap().entries.map((e) {
        final i = e.key;
        final key = e.value;
        final color = colors[i];
        
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.all(2.0),
            child: Material(
              color: color?.withValues(alpha: key == "=" ? 1.0 : 0.08) ?? Colors.transparent,
              borderRadius: BorderRadius.circular(2),
              child: InkWell(
                onTap: () => _onPressed(key),
                borderRadius: BorderRadius.circular(2),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
                  ),
                  child: Center(
                    child: key == "⌫" 
                      ? const Icon(Icons.backspace_outlined, size: 18, color: Colors.orange)
                      : Text(
                          key,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: key == "=" ? Colors.white : (color ?? Theme.of(context).colorScheme.onSurface),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInjectButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () {
            widget.onResultUsed!(double.tryParse(_display) ?? 0);
            Navigator.pop(context);
          },
          icon: const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('INJECT RESULT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Widget _buildConverterUI(ThemeData theme, bool isDark) {
    final val = double.tryParse(_display) ?? 0;
    
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.black38 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Convert from:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              DropdownButton<WeightUnit>(
                value: _sourceUnit,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                items: [WeightUnit.kg, WeightUnit.lb, WeightUnit.g].map((u) => 
                  DropdownMenuItem(value: u, child: Text(u.name.toUpperCase()))
                ).toList(),
                onChanged: (v) => setState(() => _sourceUnit = v!),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              '$_display ${_sourceUnit.name}',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontFamily: 'monospace'),
            ),
          ),
          const Divider(height: 24),
          _buildConvertRow(theme, val, WeightUnit.kg),
          _buildConvertRow(theme, val, WeightUnit.lb),
          _buildConvertRow(theme, val, WeightUnit.g),
        ],
      ),
    );
  }

  Widget _buildConvertRow(ThemeData theme, double val, WeightUnit target) {
    if (target == _sourceUnit) return const SizedBox.shrink();
    
    final result = WeightConverter.convert(value: val, from: _sourceUnit, to: target);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(target.name.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _format(result)));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied ${target.name} value'), duration: const Duration(seconds: 1)));
            },
            child: Text(
              '${_format(result)} ${target.name}',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
