// import { Color, DataTexture, LinearFilter, RGBAFormat } from 'three'
// import { defineWorkerModule, ThenableWorkerModule } from 'troika-worker-utils'
// import { createSDFGenerator } from './worker/SDFGenerator.js'
// import { createFontProcessor } from './worker/FontProcessor.js'
// import { createGlyphSegmentsIndex } from './worker/GlyphSegmentsIndex.js'
// import bidiFactory from 'bidi-js'

// Choose parser impl:
// import fontParser from './worker/FontParser_Typr.js'
// import fontParser from './worker/FontParser_OpenType.js'


part of troika_three_text;


var CONFIG = {
  // "defaultFontURL": 'https://fonts.gstatic.com/s/roboto/v18/KFOmCnqEu92Fr1Mu4mxM.woff', //Roboto Regular
  "sdfGlyphSize": 64,
  "sdfMargin": 1 / 16,
  "sdfExponent": 9,
  "textureWidth": 2048
};

var tempColor = /*#__PURE__*/new Color(0,0,0);
var hasRequested = false;

/**
 * Customizes the text builder configuration. This must be called prior to the first font processing
 * request, and applies to all fonts.
 * @param {Number} config.sdfGlyphSize - The default size of each glyph's SDF (signed distance field)
 *                 texture used for rendering. Must be a power-of-two number, and applies to all fonts,
 *                 but note that this can also be overridden per call to `getTextRenderInfo()`.
 *                 Larger sizes can improve the quality of glyph rendering by increasing the sharpness
 *                 of corners and preventing loss of very thin lines, at the expense of memory. Defaults
 *                 to 64 which is generally a good balance of size and quality.
 * @param {Number} config.sdfExponent - The exponent used when encoding the SDF values. A higher exponent
 *                 shifts the encoded 8-bit values to achieve higher precision/accuracy at texels nearer
 *                 the glyph's path, with lower precision further away. Defaults to 9.
 * @param {Number} config.sdfMargin - How much space to reserve in the SDF as margin outside the glyph's
 *                 path, as a percentage of the SDF width. A larger margin increases the quality of
 *                 extruded glyph outlines, but decreases the precision available for the glyph itself.
 *                 Defaults to 1/16th of the glyph size.
 * @param {Number} config.textureWidth - The width of the SDF texture; must be a power of 2. Defaults to
 *                 2048 which is a safe maximum texture dimension according to the stats at
 *                 https://webglstats.com/webgl/parameter/MAX_TEXTURE_SIZE and should allow for a
 *                 reasonably large number of glyphs (default glyph size of 64 and safe texture size of
 *                 2048^2 allows for 1024 glyphs.) This can be increased if you need to increase the
 *                 glyph size and/or have an extraordinary number of glyphs.
 */
configureTextBuilder(config) {
  if (hasRequested) {
    print('configureTextBuilder called after first font request; will be ignored.');
  } else {
    assign(CONFIG, config);
  }
}

/**
 * Repository for all font SDF atlas textures
 *
 *   {
 *     [font]: {
 *       sdfTexture: DataTexture
 *     }
 *   }
 */
// var atlases = Object.create(null);
var atlases = {};

/**
 * @typedef {object} TroikaTextRenderInfo - Format of the result from `getTextRenderInfo`.
 * @property {object} parameters - The normalized input arguments to the render call.
 * @property {DataTexture} sdfTexture - The SDF atlas texture.
 * @property {number} sdfGlyphSize - The size of each glyph's SDF; see `configureTextBuilder`.
 * @property {number} sdfExponent - The exponent used in encoding the SDF's values; see `configureTextBuilder`.
 * @property {Float32Array} glyphBounds - List of [minX, minY, maxX, maxY] quad bounds for each glyph.
 * @property {Float32Array} glyphAtlasIndices - List holding each glyph's index in the SDF atlas.
 * @property {Uint8Array} [glyphColors] - List holding each glyph's [r, g, b] color, if `colorRanges` was supplied.
 * @property {Float32Array} [caretPositions] - A list of caret positions for all glyphs; this is
 *           the bottom [x,y] of the cursor position before each char, plus one after the last char.
 * @property {number} [caretHeight] - An appropriate height for all selection carets.
 * @property {number} ascender - The font's ascender metric.
 * @property {number} descender - The font's descender metric.
 * @property {number} lineHeight - The final computed lineHeight measurement.
 * @property {number} topBaseline - The y position of the top line's baseline.
 * @property {Array<number>} blockBounds - The total [minX, minY, maxX, maxY] rect of the whole text block;
 *           this can include extra vertical space beyond the visible glyphs due to lineHeight, and is
 *           equivalent to the dimensions of a block-level text element in CSS.
 * @property {Array<number>} visibleBounds - The total [minX, minY, maxX, maxY] rect of the whole text block;
 *           unlike `blockBounds` this is tightly wrapped to the visible glyph paths.
 * @property {Array<number>} totalBounds - DEPRECATED; use blockBounds instead.
 * @property {Array<number>} totalBlockSize - DEPRECATED; use blockBounds instead
 * @property {Array<object>} chunkedBounds - List of bounding rects for each consecutive set of N glyphs,
 *           in the format `{start:N, end:N, rect:[minX, minY, maxX, maxY]}`.
 * @property {object} timings - Timing info for various parts of the rendering logic including SDF
 *           generation, layout, etc.
 * @frozen
 */

/**
 * @callback getTextRenderInfo~callback
 * @param {TroikaTextRenderInfo} textRenderInfo
 */

FontProcessor? _fontProcessor; 

fontProcessor() {
  var sdfExponent = CONFIG["sdfExponent"];
  var sdfMargin = CONFIG["sdfMargin"];

  if(_fontProcessor == null) {
    var sdfGenerator = createSDFGenerator(createGlyphSegmentsIndex, { "sdfExponent": sdfExponent, "sdfMargin": sdfMargin });
    _fontProcessor = FontProcessor(fontParser, sdfGenerator);
  }
  return _fontProcessor!;
}

var processInWorker = (args) {
  var _result = fontProcessor().process(args);
  return _result;
};


/**
 * Main entry point for requesting the data needed to render a text string with given font parameters.
 * This is an asynchronous call, performing most of the logic in a web worker thread.
 * @param {object} args
 * @param {getTextRenderInfo~callback} callback
 */
getTextRenderInfo(Map<String, dynamic> args2, callback) {
  hasRequested = true;
  Map<String, dynamic> args = assign({}, args2);

  // Normalize text to a string
  args["text"] = '' + args["text"];

  args["sdfGlyphSize"] = args["sdfGlyphSize"] ?? CONFIG["sdfGlyphSize"];

  // Normalize colors
  if (args["colorRanges"] != null) {
    var colors = {};
    for (var key in args["colorRanges"].keys) {
      if (args["colorRanges"][key] != null) {
        var val = args["colorRanges"][key];
        // TODO
        // if (!(val is num)) {
        //   val = tempColor.setHex(val).getHex();
        // }
        colors[key] = val;
      }
    }
    args["colorRanges"] = colors;
  }

  // TODO
  // Object.freeze(args);

  // Init the atlas for this font if needed
  // var {textureWidth, sdfExponent} = CONFIG;
  // var {sdfGlyphSize} = args;

  int textureWidth = CONFIG["textureWidth"]!.toInt();
  var sdfExponent = CONFIG["sdfExponent"];
  var sdfGlyphSize = args["sdfGlyphSize"];

  Map<String, dynamic> _fontJson = args["font"];
  String _fullName = _fontJson["fullName"];
  
  var atlasKey = "${_fullName}@${sdfGlyphSize}";
  var atlas = atlases[atlasKey];
  if (atlas == null) {
    atlas = {
      "sdfTexture": new DataTexture(
        new Uint8List(sdfGlyphSize * textureWidth * 4),
        textureWidth,
        sdfGlyphSize,
        RGBAFormat,
        null,
        null,
        null,
        null,
        LinearFilter,
        LinearFilter,
        null,
        null
      )
    };
    atlases[atlasKey] = atlas;
    atlas["sdfTexture"].font = _fullName;
  }


  // Issue request to the FontProcessor in the worker
  var result = processInWorker(args);

  // If the response has newGlyphs, copy them into the atlas texture at the specified indices
  if (result["newGlyphSDFs"] != null) {
    result["newGlyphSDFs"].forEach((sdfElm) {


      var textureData = sdfElm["textureData"];
      var atlasIndex = sdfElm["atlasIndex"];
      var texImg = atlas["sdfTexture"].image;

      // Grow the texture by power of 2 if needed
      while (texImg.data.length < (atlasIndex + 1) * sdfGlyphSize * sdfGlyphSize) {
        var biggerArray = new Uint8List(texImg.data.length * 2);
        // biggerArray.set(texImg.data);

        var i = 0;
        texImg.data.forEach((element) {
          biggerArray[i] = element;
          i = i + 1;
        });

        texImg.data = biggerArray;
        texImg.height *= 2;
      }

      // Insert the new glyph's data into the full texture image at the correct offsets
      // Glyphs are packed sequentially into the R,G,B,A channels of a square, advancing
      // to the next square every 4 glyphs.
      var squareIndex = Math.floor(atlasIndex / 4);
      var cols = texImg.width / sdfGlyphSize;
      int baseStartIndex = (Math.floor(squareIndex / cols) * texImg.width * sdfGlyphSize * 4 //full rows
        + (squareIndex % cols) * sdfGlyphSize * 4 //partial row
        + (atlasIndex % 4)).toInt(); //color channel
      for (var y = 0; y < sdfGlyphSize; y++) {
        var srcStartIndex = y * sdfGlyphSize;
        var rowStartIndex = baseStartIndex + (y * texImg.width * 4);
        for (var x = 0; x < sdfGlyphSize; x++) {
          texImg.data[rowStartIndex + x * 4] = textureData[srcStartIndex + x];
        }
      }
    });
    atlas["sdfTexture"].needsUpdate = true;
  }


  // Invoke callback with the text layout arrays and updated texture
  callback({
    "parameters": args,
    "sdfTexture": atlas["sdfTexture"],
    "sdfGlyphSize": sdfGlyphSize,
    "sdfExponent": sdfExponent,
    "glyphBounds": result["glyphBounds"],
    "glyphAtlasIndices": result["glyphAtlasIndices"],
    "glyphColors": result["glyphColors"],
    "caretPositions": result["caretPositions"],
    "caretHeight": result["caretHeight"],
    "chunkedBounds": result["chunkedBounds"],
    "ascender": result["ascender"],
    "descender": result["descender"],
    "lineHeight": result["lineHeight"],
    "topBaseline": result["topBaseline"],
    "blockBounds": result["blockBounds"],
    "visibleBounds": result["visibleBounds"],
    "timings": result["timings"],
    // get totalBounds() {
    //   console.log('totalBounds deprecated, use blockBounds instead')
    //   return result.blockBounds
    // },
    // get totalBlockSize() {
    //   console.log('totalBlockSize deprecated, use blockBounds instead')
    //   var [x0, y0, x1, y1] = result.blockBounds
    //   return [x1 - x0, y1 - y0]
    // }
  });
}


/**
 * Preload a given font and optionally pre-generate glyph SDFs for one or more character sequences.
 * This can be useful to avoid long pauses when first showing text in a scene, by preloading the
 * needed fonts and glyphs up front along with other assets.
 *
 * @param {object} options
 * @param {string} options.font - URL of the font file to preload. If not given, the default font will
 *        be loaded.
 * @param {string|string[]} options.characters - One or more character sequences for which to pre-
 *        generate glyph SDFs. Note that this will honor ligature substitution, so you may need
 *        to specify ligature sequences in addition to their individual characters to get all
 *        possible glyphs, e.g. `["t", "h", "th"]` to get the "t" and "h" glyphs plus the "th" ligature.
 * @param {number} options.sdfGlyphSize - The size at which to prerender the SDF textures for the
 *        specified `characters`.
 * @param {function} callback - A function that will be called when the preloading is complete.
 */
preloadFont(options, callback) {
  var characters = options["characters"];

  // {font, characters, sdfGlyphSize}
  var text = characters is List ? characters.join('\n') : '' + characters;
  getTextRenderInfo({ 
    "font": options["font"], 
    "sdfGlyphSize": options["sdfGlyphSize"], 
    "text": text }, callback);
}

dumpSDFTextures() {
  atlases.keys.forEach((font) {
    var atlas = atlases[font];


    // var canvas = document.createElement('canvas');
    // var image = atlas["sdfTexture"].image;

    // var width = image.width;
    // var height = image.height;
    // var data = image.data;

    // canvas.width = width;
    // canvas.height = height;
    // var imgData = new ImageData(new Uint8ClampedArray(data), width, height);
    // var ctx = canvas.getContext('2d');
    // ctx.putImageData(imgData, 0, 0);
    // print(" ${font}, ${atlas}, ${canvas.toDataURL()} ");
    // print("""
    //   background: url(${canvas.toDataURL()});
    //   background-size: ${width}px ${height}px;
    //   color: transparent;
    //   font-size: 0;
    //   line-height: ${height}px;
    //   padding-left: ${width}px;
    // """);
  });
}