import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FlutterTexJs {
  static const MethodChannel _channel = MethodChannel('flutter_tex_js');

  /// Render the specified [text] to a PNG binary suitable for display with
  /// [Image.memory].
  ///
  /// [requestId] is an arbitrary ID that identifies this render
  /// request. Concurrent requests with the same ID will be coalesced: earlier
  /// requests will return with null, and only the last request will complete
  /// with data. You can also cancel a request with [cancel].
  ///
  /// [displayMode] is KaTeX's displayMode: math will be in display mode (\int,
  /// \sum, etc. will be large). This is appropriate for "block" display, as
  /// opposed to "inline" display. See also: https://katex.org/docs/options.html
  ///
  /// [color] is the color of the rendered text.
  ///
  /// [fontSize] is the size in pixels of the rendered text. You can use
  /// e.g. [TextStyle.fontSize] as-is.
  ///
  /// [maxWidth] is the width in pixels that the rendered image is allowed to
  /// take up. When [maxWidth] is [double.infinity] or [displayMode] is true,
  /// the width will be the natural width of the text. Only when [displayMode]
  /// is false and [maxWidth] is finite, this width determines where the text
  /// will wrap.
  static Future<Uint8List> render(
    String text, {
    @required String requestId,
    @required bool displayMode,
    @required Color color,
    @required double fontSize,
    @required double maxWidth,
  }) async {
    assert(requestId != null);
    assert(displayMode != null);
    assert(color != null);
    assert(maxWidth != null);
    final escapedText = _escapeForJavaScript(text);
    if (escapedText != text && !kReleaseMode) {
      debugPrint(
          'Escaped text to render; was: "$text"; escaped: "$escapedText"');
    }
    return _channel.invokeMethod<Uint8List>('render', {
      'requestId': requestId,
      'text': escapedText,
      'displayMode': displayMode,
      'color': _colorToCss(color),
      'fontSize': fontSize,
      'maxWidth': maxWidth,
    });
  }

  /// Cancel the in-flight [render] request identified by [requestId]. You might
  /// want to call this e.g. in StatefulWidget.dispose. It is safe to call this
  /// even if no such render request exists.
  static Future<void> cancel(String requestId) {
    assert(requestId != null);
    return _channel.invokeMethod<void>('cancel', {
      'requestId': requestId,
    });
  }
}

final _unescapedBackslashPattern = RegExp(r'(?<!\\)(?:\\\\)*\\');
final _unescapedAposPattern = RegExp(r"(?<!\\)(?:\\\\)*'");

// Native layer will concatenate with apostrophes to form a JavaScript string
// literal; prepare here for that.
String _escapeForJavaScript(String string) => string
    .replaceAll(_unescapedBackslashPattern, r'\\')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r')
    .replaceAll(_unescapedAposPattern, r"\'");

String _colorToCss(Color color) =>
    'rgba(${color.red},${color.green},${color.blue},${color.opacity})';

/// A set listing the supported TeX environments; see
/// https://katex.org/docs/supported.html#environments
const Set<String> flutterTexJsSupportedEnvironments = {
  'matrix',
  'pmatrix',
  'vmatrix',
  'Bmatrix',
  'aligned',
  'gathered',
  'smallmatrix',
  'array',
  'bmatrix',
  'Vmatrix',
  'alignedat',
  'cases',
  'rcases',
  'darray',
  'dcases',
  'drcases',
};

typedef ErrorWidgetBuilder = Widget Function(
    BuildContext context, Object error);

/// A rendered image of LaTeX markup. The image is rendered asynchronously by a
/// native web view.
class TexImage extends StatefulWidget {
  const TexImage(
    this.math, {
    this.displayMode = true,
    this.color,
    this.fontSize,
    this.placeholder,
    this.error,
    this.keepAlive = true,
    Key key,
  })  : assert(math != null),
        assert(displayMode != null),
        super(key: key);

  /// LaTeX markup to render. See here for supported syntax:
  /// https://katex.org/docs/supported.html
  final String math;

  /// [displayMode] is KaTeX's displayMode: math will be in display mode (\int,
  /// \sum, etc. will be large). This is appropriate for "block" display, as
  /// opposed to "inline" display. See also: https://katex.org/docs/options.html
  final bool displayMode;

  /// [color] is the color of the rendered text.
  final Color color;

  /// [fontSize] is the size in pixels of the rendered text. You can use
  /// e.g. [TextStyle.fontSize] as-is.
  final double fontSize;

  /// A widget to display while rendering. By default it is simply [math] as
  /// text.
  final Widget placeholder;

  /// A builder supplying a widget to display in case of error, for instance
  /// when [math] contains invalid or unsupported LaTeX syntax. By default it is
  /// [Icons.error] and the error message.
  final ErrorWidgetBuilder error;

  /// Whether or not the rendered image should be retained even when e.g. the
  /// widget has been scrolled out of view in a [ListView].
  final bool keepAlive;

  @override
  _TexImageState createState() => _TexImageState();
}

class _TexImageState extends State<TexImage>
    with AutomaticKeepAliveClientMixin<TexImage> {
  String get id =>
      widget.key?.hashCode?.toString() ?? identityHashCode(this).toString();

  @override
  void dispose() {
    FlutterTexJs.cancel(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = DefaultTextStyle.of(context).style;
        return FutureBuilder<Uint8List>(
          future: FlutterTexJs.render(
            widget.math,
            requestId: id,
            displayMode: widget.displayMode,
            color: widget.color ?? textStyle.color,
            fontSize: widget.fontSize ?? textStyle.fontSize,
            maxWidth: constraints.maxWidth,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Image.memory(
                snapshot.data,
                scale: MediaQuery.of(context).devicePixelRatio,
              );
            } else if (snapshot.hasError) {
              return _buildErrorWidget(snapshot.error);
            } else {
              return widget.placeholder ?? Text(widget.math);
            }
          },
        );
      },
    );
  }

  Widget _buildErrorWidget(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'UnsupportedOsVersion':
          return Text(widget.math);
        case 'JobCancelled':
          return const SizedBox.shrink();
      }
    }
    final errorBuilder = widget.error ?? defaultError;
    return errorBuilder(context, error);
  }

  Widget defaultError(BuildContext context, Object error) => Column(
        children: [
          const Icon(Icons.error),
          Text(error.toString()),
        ],
      );

  @override
  bool get wantKeepAlive => widget.keepAlive;
}
