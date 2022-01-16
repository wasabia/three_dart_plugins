
part of troika_three_text;


/**
 * Recursively expands all `#include <xyz>` statements within string of shader code.
 * Copied from three's WebGLProgram#parseIncludes for external use.
 *
 * @param {string} source - The GLSL source code to evaluate
 * @return {string} The GLSL code with all includes expanded
 */

var includePattern = RegExp(r"^[ \t]*#include +<([\w\d./]+)>", multiLine: true);

String expandShaderIncludes(String source) {

  var mactes = includePattern.allMatches(source);
  
  // Loop through all matches.
  for (var match in mactes) {
    /**
       * Returns the string matched by the given [group].
       *
       * If [group] is 0, returns the match of the pattern.
       *
       * The result may be `null` if the pattern didn't assign a value to it
       * as part of this match.
       */
    // print(" resolveIncludes ");
    // print(match.group(0)); // 15, then 20

    String includeString = match.group(1)!;

    String targetString = ShaderChunk[includeString]!;

    String targetString2 = expandShaderIncludes(targetString);

    String fromString = match.group(0)!;

    source = source.replaceFirst(fromString, targetString2);
  }

  return source;
}
