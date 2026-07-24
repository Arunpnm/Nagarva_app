import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Drop-in replacement for a page's main vertical SingleChildScrollView
/// that also responds to the keyboard on Flutter web/desktop:
/// ↑/↓ arrows, PageUp/PageDown, Home/End, and spacebar.
///
/// Why: Flutter web only scrolls a Scrollable with arrow keys when the
/// scrollable itself has keyboard focus, which never happens from normal
/// mouse use — so on every page only wheel/drag worked. This wraps the
/// scroll view in an autofocused Focus node and drives the controller
/// manually.
///
/// Focus etiquette: when a TextField (or anything else focusable) takes
/// focus, this node stops receiving key events, so arrow keys inside form
/// fields still move the text cursor and don't scroll the page.
class KeyboardScrollView extends StatefulWidget {
  const KeyboardScrollView({
    super.key,
    required this.child,
    this.padding,
    this.autofocus = true,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool autofocus;

  @override
  State<KeyboardScrollView> createState() => _KeyboardScrollViewState();
}

class _KeyboardScrollViewState extends State<KeyboardScrollView> {
  final ScrollController _controller = ScrollController();
  final FocusNode _focusNode =
      FocusNode(debugLabel: 'KeyboardScrollView', skipTraversal: true);

  static const double _line = 60.0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _jump(double delta) {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final target =
        (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  void _jumpTo(double target) {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      target.clamp(_controller.position.minScrollExtent,
          _controller.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // CRITICAL: key events bubble up the focus chain, so this ancestor
    // node also receives keys typed inside TextFields. Handling them here
    // ate the spacebar (space scrolled the page instead of typing a
    // space). Only act when THIS node is the one actually focused.
    if (FocusManager.instance.primaryFocus != _focusNode) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final page = _controller.hasClients
        ? _controller.position.viewportDimension * 0.85
        : 400.0;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _jump(_line);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _jump(-_line);
    } else if (key == LogicalKeyboardKey.pageDown) {
      _jump(page);
    } else if (key == LogicalKeyboardKey.pageUp) {
      _jump(-page);
    } else if (key == LogicalKeyboardKey.home) {
      _jumpTo(0);
    } else if (key == LogicalKeyboardKey.end) {
      _jumpTo(_controller.hasClients
          ? _controller.position.maxScrollExtent
          : 0);
    } else {
      // Note: space is deliberately NOT handled — even guarded, it's not
      // worth the risk of ever fighting a text field again.
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        // Clicking anywhere on the page (outside a field) returns key
        // focus to the scroll view, so arrows work again after editing.
        behavior: HitTestBehavior.translucent,
        onTap: () => _focusNode.requestFocus(),
        child: SingleChildScrollView(
          controller: _controller,
          padding: widget.padding,
          child: widget.child,
        ),
      ),
    );
  }
}
