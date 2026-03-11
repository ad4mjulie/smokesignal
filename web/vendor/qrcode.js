/*!
 * QR Code Generator for JavaScript
 * (c) 2009 Kazuhiko Arase
 * MIT License
 *
 * Slightly trimmed to expose only `QRCode.toCanvas` used by this app.
 */

(function() {
  //---------------------------------------------------------------------
  // QRCode public API
  //---------------------------------------------------------------------
  function QRCode() {}

  QRCode.toCanvas = function(canvas, text, options, cb) {
    try {
      options = options || {};
      var typeNumber = options.version || 0; // 0 = auto
      var errorCorrectionLevel = options.errorCorrectionLevel || 'M';
      var qr = qrcode(typeNumber, errorCorrectionLevel);
      qr.addData(text);
      qr.make();
      renderToCanvas(canvas, qr, options.width || 256, options.margin || 1);
      cb && cb(null);
    } catch (e) {
      cb && cb(e);
    }
  };

  if (typeof module !== 'undefined') {
    module.exports = QRCode;
  } else {
    window.QRCode = QRCode;
  }

  //---------------------------------------------------------------------
  // Renderer
  //---------------------------------------------------------------------
  function renderToCanvas(canvas, qr, size, margin) {
    var n = qr.getModuleCount();
    var totalMargin = margin * 2;
    var cells = n + totalMargin;
    canvas.width = canvas.height = size;
    var ctx = canvas.getContext('2d');
    var cellSize = size / cells;
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, size, size);
    ctx.fillStyle = '#000';
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (qr.isDark(r, c)) {
          ctx.fillRect((c + margin) * cellSize, (r + margin) * cellSize, cellSize, cellSize);
        }
      }
    }
  }

  //---------------------------------------------------------------------
  // qrcode.js (Kazuhiko Arase) - lightly inlined
  //---------------------------------------------------------------------
  var QRMode = { MODE_8BIT_BYTE: 4 };
  var QRErrorCorrectLevel = { L: 1, M: 0, Q: 3, H: 2 };
  var QRMaskPattern = {
    PATTERN000: 0,
    PATTERN001: 1,
    PATTERN010: 2,
    PATTERN011: 3,
    PATTERN100: 4,
    PATTERN101: 5,
    PATTERN110: 6,
    PATTERN111: 7,
  };

  function qrcode(typeNumber, errorCorrectionLevel) {
    var qr = {};
    var modules = null;
    var moduleCount = 0;
    var dataCache = null;
    var dataList = [];

    qr.addData = function(data) {
      dataList.push(new QR8bitByte(data));
      dataCache = null;
    };

    qr.isDark = function(row, col) {
      if (modules[row][col] !== null) {
        return modules[row][col];
      } else {
        return false;
      }
    };

    qr.getModuleCount = function() {
      return moduleCount;
    };

    qr.make = function() {
      if (typeNumber < 1) {
        typeNumber = _getMinimumTypeNumber(errorCorrectionLevel, dataList);
      }
      makeImpl(false, _getBestMaskPattern());
    };

    function makeImpl(test, maskPattern) {
      moduleCount = typeNumber * 4 + 17;
      modules = new Array(moduleCount);

      for (var row = 0; row < moduleCount; row++) {
        modules[row] = new Array(moduleCount);
        for (var col = 0; col < moduleCount; col++) {
          modules[row][col] = null;
        }
      }

      setupPositionProbePattern(0, 0);
      setupPositionProbePattern(moduleCount - 7, 0);
      setupPositionProbePattern(0, moduleCount - 7);
      setupPositionAdjustPattern();
      setupTimingPattern();
      setupTypeInfo(test, maskPattern);

      if (typeNumber >= 7) {
        setupTypeNumber(test);
      }

      if (dataCache === null) {
        dataCache = createData(typeNumber, errorCorrectionLevel, dataList);
      }

      mapData(dataCache, maskPattern);
    }

    function setupPositionProbePattern(row, col) {
      for (var r = -1; r <= 7; r++) {
        if (row + r <= -1 || moduleCount <= row + r) continue;
        for (var c = -1; c <= 7; c++) {
          if (col + c <= -1 || moduleCount <= col + c) continue;
          if (
            (0 <= r && r <= 6 && (c === 0 || c === 6)) ||
            (0 <= c && c <= 6 && (r === 0 || r === 6)) ||
            (2 <= r && r <= 4 && 2 <= c && c <= 4)
          ) {
            modules[row + r][col + c] = true;
          } else {
            modules[row + r][col + c] = false;
          }
        }
      }
    }

    function setupTimingPattern() {
      for (var i = 8; i < moduleCount - 8; i++) {
        var bit = i % 2 === 0;
        modules[i][6] = bit;
        modules[6][i] = bit;
      }
    }

    function setupPositionAdjustPattern() {
      var pos = QRUtil.getPatternPosition(typeNumber);
      for (var i = 0; i < pos.length; i++) {
        for (var j = 0; j < pos.length; j++) {
          var row = pos[i];
          var col = pos[j];

          if (modules[row][col] !== null) {
            continue;
          }
          for (var r = -2; r <= 2; r++) {
            for (var c = -2; c <= 2; c++) {
              modules[row + r][col + c] = r === 0 || c === 0 || (r === c && Math.abs(r) === 2);
            }
          }
        }
      }
    }

    function setupTypeNumber(test) {
      var bits = QRUtil.getBCHTypeNumber(typeNumber);
      for (var i = 0; i < 18; i++) {
        var mod = !test && ((bits >> i) & 1) === 1;
        modules[Math.floor(i / 3)][(i % 3) + moduleCount - 8 - 3] = mod;
        modules[(i % 3) + moduleCount - 8 - 3][Math.floor(i / 3)] = mod;
      }
    }

    function setupTypeInfo(test, maskPattern) {
      var data = (QRErrorCorrectLevel[errorCorrectionLevel] << 3) | maskPattern;
      var bits = QRUtil.getBCHTypeInfo(data);

      // vertical
      for (var i = 0; i < 15; i++) {
        var mod = !test && ((bits >> i) & 1) === 1;
        if (i < 6) {
          modules[i][8] = mod;
        } else if (i < 8) {
          modules[i + 1][8] = mod;
        } else {
          modules[moduleCount - 15 + i][8] = mod;
        }
      }

      // horizontal
      for (var i2 = 0; i2 < 15; i2++) {
        var mod2 = !test && ((bits >> i2) & 1) === 1;
        if (i2 < 8) {
          modules[8][moduleCount - i2 - 1] = mod2;
        } else if (i2 < 9) {
          modules[8][15 - i2 - 1 + 1] = mod2;
        } else {
          modules[8][15 - i2 - 1] = mod2;
        }
      }

      modules[moduleCount - 8][8] = !test;
    }

    function mapData(data, maskPattern) {
      var inc = -1;
      var row = moduleCount - 1;
      var bitIndex = 7;
      var byteIndex = 0;

      for (var col = moduleCount - 1; col > 0; col -= 2) {
        if (col === 6) col -= 1;
        while (true) {
          for (var c = 0; c < 2; c++) {
            if (modules[row][col - c] === null) {
              var dark = false;
              if (byteIndex < data.length) {
                dark = ((data[byteIndex] >>> bitIndex) & 1) === 1;
              }
              var mask = QRUtil.getMask(maskPattern, row, col - c);
              if (mask) {
                dark = !dark;
              }
              modules[row][col - c] = dark;
              bitIndex -= 1;
              if (bitIndex === -1) {
                byteIndex += 1;
                bitIndex = 7;
              }
            }
          }
          row += inc;
          if (row < 0 || moduleCount <= row) {
            row -= inc;
            inc = -inc;
            break;
          }
        }
      }
    }

    function _getBestMaskPattern() {
      var minLostPoint = 0;
      var pattern = 0;
      for (var i = 0; i < 8; i++) {
        makeImpl(true, i);
        var lostPoint = QRUtil.getLostPoint(qr);
        if (i === 0 || lostPoint < minLostPoint) {
          minLostPoint = lostPoint;
          pattern = i;
        }
      }
      return pattern;
    }

    return qr;
  }

  //---------------------------------------------------------------------
  // QR8bitByte
  //---------------------------------------------------------------------
  function QR8bitByte(data) {
    this.mode = QRMode.MODE_8BIT_BYTE;
    this.data = data;
    this.parsedData = [];
    for (var i = 0; i < data.length; i++) {
      var code = data.charCodeAt(i);
      this.parsedData.push(code & 0xff);
    }
  }
  QR8bitByte.prototype = {
    getLength: function() {
      return this.parsedData.length;
    },
    write: function(buffer) {
      for (var i = 0; i < this.parsedData.length; i++) {
        buffer.put(this.parsedData[i], 8);
      }
    },
  };

  //---------------------------------------------------------------------
  // QRBitBuffer
  //---------------------------------------------------------------------
  function QRBitBuffer() {
    this.buffer = [];
    this.length = 0;
  }
  QRBitBuffer.prototype = {
    get: function(index) {
      var bufIndex = Math.floor(index / 8);
      return ((this.buffer[bufIndex] >>> (7 - (index % 8))) & 1) === 1;
    },
    put: function(num, length) {
      for (var i = 0; i < length; i++) {
        this.putBit(((num >>> (length - i - 1)) & 1) === 1);
      }
    },
    putBit: function(bit) {
      var bufIndex = Math.floor(this.length / 8);
      if (this.buffer.length <= bufIndex) {
        this.buffer.push(0);
      }
      if (bit) {
        this.buffer[bufIndex] |= 0x80 >>> (this.length % 8);
      }
      this.length += 1;
    },
  };

  //---------------------------------------------------------------------
  // QRUtil
  //---------------------------------------------------------------------
  var QRUtil = (function() {
    var PATTERN_POSITION_TABLE = [
      [],
      [6, 18],
      [6, 22],
      [6, 26],
      [6, 30],
      [6, 34],
      [6, 22, 38],
      [6, 24, 42],
      [6, 26, 46],
      [6, 28, 50],
      [6, 30, 54],
      [6, 32, 58],
      [6, 34, 62],
      [6, 26, 46, 66],
      [6, 26, 48, 70],
      [6, 26, 50, 74],
      [6, 30, 54, 78],
      [6, 30, 56, 82],
      [6, 30, 58, 86],
      [6, 34, 62, 90],
      [6, 28, 50, 72, 94],
      [6, 26, 50, 74, 98],
      [6, 30, 54, 78, 102],
      [6, 28, 54, 80, 106],
      [6, 32, 58, 84, 110],
      [6, 30, 58, 86, 114],
      [6, 34, 62, 90, 118],
      [6, 26, 50, 74, 98, 122],
      [6, 30, 54, 78, 102, 126],
      [6, 26, 52, 78, 104, 130],
      [6, 30, 56, 82, 108, 134],
      [6, 34, 60, 86, 112, 138],
      [6, 30, 58, 86, 114, 142],
      [6, 34, 62, 90, 118, 146],
      [6, 30, 54, 78, 102, 126, 150],
      [6, 24, 50, 76, 102, 128, 154],
      [6, 28, 54, 80, 106, 132, 158],
      [6, 32, 58, 84, 110, 136, 162],
      [6, 26, 54, 82, 110, 138, 166],
      [6, 30, 58, 86, 114, 142, 170],
    ];

    var G15 = (1 << 10) | (1 << 8) | (1 << 5) | (1 << 4) | (1 << 2) | (1 << 1) | (1 << 0);
    var G18 =
      (1 << 12) |
      (1 << 11) |
      (1 << 10) |
      (1 << 9) |
      (1 << 8) |
      (1 << 5) |
      (1 << 2) |
      (1 << 0);
    var G15_MASK = (1 << 14) | (1 << 12) | (1 << 10) | (1 << 4) | (1 << 1);

    var QRUtil = {};

    QRUtil.getBCHTypeInfo = function(data) {
      var d = data << 10;
      while (getBCHDigit(d) - getBCHDigit(G15) >= 0) {
        d ^= G15 << (getBCHDigit(d) - getBCHDigit(G15));
      }
      return ((data << 10) | d) ^ G15_MASK;
    };

    QRUtil.getBCHTypeNumber = function(data) {
      var d = data << 12;
      while (getBCHDigit(d) - getBCHDigit(G18) >= 0) {
        d ^= G18 << (getBCHDigit(d) - getBCHDigit(G18));
      }
      return (data << 12) | d;
    };

    QRUtil.getPatternPosition = function(typeNumber) {
      return PATTERN_POSITION_TABLE[typeNumber - 1];
    };

    QRUtil.getMask = function(maskPattern, i, j) {
      switch (maskPattern) {
        case QRMaskPattern.PATTERN000:
          return (i + j) % 2 === 0;
        case QRMaskPattern.PATTERN001:
          return i % 2 === 0;
        case QRMaskPattern.PATTERN010:
          return j % 3 === 0;
        case QRMaskPattern.PATTERN011:
          return (i + j) % 3 === 0;
        case QRMaskPattern.PATTERN100:
          return (Math.floor(i / 2) + Math.floor(j / 3)) % 2 === 0;
        case QRMaskPattern.PATTERN101:
          return ((i * j) % 2) + ((i * j) % 3) === 0;
        case QRMaskPattern.PATTERN110:
          return (((i * j) % 2) + ((i * j) % 3)) % 2 === 0;
        case QRMaskPattern.PATTERN111:
          return (((i + j) % 2) + ((i * j) % 3)) % 2 === 0;
        default:
          throw new Error('bad maskPattern:' + maskPattern);
      }
    };

    QRUtil.getLostPoint = function(qrCode) {
      var moduleCount = qrCode.getModuleCount();
      var lostPoint = 0;

      for (var row = 0; row < moduleCount; row++) {
        for (var col = 0; col < moduleCount; col++) {
          var sameCount = 0;
          var dark = qrCode.isDark(row, col);
          for (var r = -1; r <= 1; r++) {
            if (row + r < 0 || moduleCount <= row + r) continue;
            for (var c = -1; c <= 1; c++) {
              if (col + c < 0 || moduleCount <= col + c) continue;
              if (r === 0 && c === 0) continue;
              if (dark === qrCode.isDark(row + r, col + c)) {
                sameCount += 1;
              }
            }
          }
          if (sameCount > 5) {
            lostPoint += 3 + sameCount - 5;
          }
        }
      }

      for (var row2 = 0; row2 < moduleCount - 1; row2++) {
        for (var col2 = 0; col2 < moduleCount - 1; col2++) {
          var count = 0;
          if (qrCode.isDark(row2, col2)) count++;
          if (qrCode.isDark(row2 + 1, col2)) count++;
          if (qrCode.isDark(row2, col2 + 1)) count++;
          if (qrCode.isDark(row2 + 1, col2 + 1)) count++;
          if (count === 0 || count === 4) {
            lostPoint += 3;
          }
        }
      }

      for (var row3 = 0; row3 < moduleCount; row3++) {
        for (var col3 = 0; col3 < moduleCount - 6; col3++) {
          if (
            qrCode.isDark(row3, col3) &&
            !qrCode.isDark(row3, col3 + 1) &&
            qrCode.isDark(row3, col3 + 2) &&
            qrCode.isDark(row3, col3 + 3) &&
            qrCode.isDark(row3, col3 + 4) &&
            !qrCode.isDark(row3, col3 + 5) &&
            qrCode.isDark(row3, col3 + 6)
          ) {
            lostPoint += 40;
          }
        }
      }

      for (var col4 = 0; col4 < moduleCount; col4++) {
        for (var row4 = 0; row4 < moduleCount - 6; row4++) {
          if (
            qrCode.isDark(row4, col4) &&
            !qrCode.isDark(row4 + 1, col4) &&
            qrCode.isDark(row4 + 2, col4) &&
            qrCode.isDark(row4 + 3, col4) &&
            qrCode.isDark(row4 + 4, col4) &&
            !qrCode.isDark(row4 + 5, col4) &&
            qrCode.isDark(row4 + 6, col4)
          ) {
            lostPoint += 40;
          }
        }
      }

      var darkCount = 0;
      for (var col5 = 0; col5 < moduleCount; col5++) {
        for (var row5 = 0; row5 < moduleCount; row5++) {
          if (qrCode.isDark(row5, col5)) {
            darkCount += 1;
          }
        }
      }

      var ratio = Math.abs((100 * darkCount) / moduleCount / moduleCount - 50) / 5;
      lostPoint += ratio * 10;
      return lostPoint;
    };

    function getBCHDigit(data) {
      var digit = 0;
      while (data !== 0) {
        digit += 1;
        data >>>= 1;
      }
      return digit;
    }

    return QRUtil;
  })();

  //---------------------------------------------------------------------
  // Data / EC codewords
  //---------------------------------------------------------------------
  var QRRSBlock = (function() {
    var RS_BLOCK_TABLE = [
      // L
      // M
      // Q
      // H
      // 1
      [1, 26, 19],
      [1, 26, 16],
      [1, 26, 13],
      [1, 26, 9],

      // 2
      [1, 44, 34],
      [1, 44, 28],
      [1, 44, 22],
      [1, 44, 16],

      // 3
      [1, 70, 55],
      [1, 70, 44],
      [2, 35, 17],
      [2, 35, 13],

      // 4
      [1, 100, 80],
      [2, 50, 32],
      [2, 50, 24],
      [4, 25, 9],

      // 5
      [1, 134, 108],
      [2, 67, 43],
      [2, 33, 15, 2, 34, 16],
      [2, 33, 11, 2, 34, 12],

      // 6
      [2, 86, 68],
      [4, 43, 27],
      [4, 43, 19],
      [4, 43, 15],

      // 7
      [2, 98, 78],
      [4, 49, 31],
      [2, 32, 14, 4, 33, 15],
      [4, 39, 13, 1, 40, 14],

      // 8
      [2, 121, 97],
      [2, 60, 38, 2, 61, 39],
      [4, 40, 18, 2, 41, 19],
      [4, 40, 14, 2, 41, 15],

      // 9
      [2, 146, 116],
      [3, 58, 36, 2, 59, 37],
      [4, 36, 16, 4, 37, 17],
      [4, 36, 12, 4, 37, 13],

      // 10
      [2, 86, 68, 2, 87, 69],
      [4, 69, 43, 1, 70, 44],
      [6, 43, 19, 2, 44, 20],
      [6, 43, 15, 2, 44, 16],
    ];

    var QRRSBlock = {};

    QRRSBlock.getRSBlocks = function(typeNumber, errorCorrectionLevel) {
      var rsBlock = RS_BLOCK_TABLE[(typeNumber - 1) * 4 + QRErrorCorrectLevel[errorCorrectionLevel]];
      if (typeof rsBlock === 'undefined') {
        throw new Error('bad rs block @ typeNumber:' + typeNumber + '/errorCorrectionLevel:' + errorCorrectionLevel);
      }
      var list = [];
      var count = rsBlock.length / 3;
      for (var i = 0; i < count; i++) {
        var start = i * 3;
        var rCount = rsBlock[start + 0];
        var totalCount = rsBlock[start + 1];
        var dataCount = rsBlock[start + 2];
        for (var j = 0; j < rCount; j++) {
          list.push({ totalCount: totalCount, dataCount: dataCount });
        }
      }
      return list;
    };
    return QRRSBlock;
  })();

  //---------------------------------------------------------------------
  // Math / Polynomial / GF(256)
  //---------------------------------------------------------------------
  var QRMath = (function() {
    var EXP_TABLE = new Array(256);
    var LOG_TABLE = new Array(256);
    for (var i = 0; i < 8; i++) {
      EXP_TABLE[i] = 1 << i;
    }
    for (var i2 = 8; i2 < 256; i2++) {
      EXP_TABLE[i2] = EXP_TABLE[i2 - 4] ^ EXP_TABLE[i2 - 5] ^ EXP_TABLE[i2 - 6] ^ EXP_TABLE[i2 - 8];
    }
    for (var i3 = 0; i3 < 255; i3++) {
      LOG_TABLE[EXP_TABLE[i3]] = i3;
    }
    var QRMath = {};
    QRMath.glog = function(n) {
      if (n < 1) throw new Error('glog(' + n + ')');
      return LOG_TABLE[n];
    };
    QRMath.gexp = function(n) {
      while (n < 0) {
        n += 255;
      }
      while (n >= 256) {
        n -= 255;
      }
      return EXP_TABLE[n];
    };
    return QRMath;
  })();

  function QRPolynomial(num, shift) {
    if (num.length === undefined) throw new Error(num.length + '/' + shift);
    var offset = 0;
    while (offset < num.length && num[offset] === 0) {
      offset += 1;
    }
    this.num = new Array(num.length - offset + shift);
    for (var i = 0; i < num.length - offset; i++) {
      this.num[i] = num[i + offset];
    }
  }
  QRPolynomial.prototype = {
    get: function(index) {
      return this.num[index];
    },
    getLength: function() {
      return this.num.length;
    },
    multiply: function(e) {
      var num = new Array(this.getLength() + e.getLength() - 1);
      for (var i = 0; i < this.getLength(); i++) {
        for (var j = 0; j < e.getLength(); j++) {
          num[i + j] ^= QRMath.gexp(QRMath.glog(this.get(i)) + QRMath.glog(e.get(j)));
        }
      }
      return new QRPolynomial(num, 0);
    },
    mod: function(e) {
      if (this.getLength() - e.getLength() < 0) {
        return this;
      }
      var ratio = QRMath.glog(this.get(0)) - QRMath.glog(e.get(0));
      var num = new Array(this.getLength());
      for (var i = 0; i < this.getLength(); i++) {
        num[i] = this.get(i);
      }
      for (var j = 0; j < e.getLength(); j++) {
        num[j] ^= QRMath.gexp(QRMath.glog(e.get(j)) + ratio);
      }
      // recursive
      return new QRPolynomial(num, 0).mod(e);
    },
  };

  //---------------------------------------------------------------------
  // Utilities
  //---------------------------------------------------------------------
  function _getMinimumTypeNumber(errorCorrectionLevel, dataList) {
    for (var typeNumber = 1; typeNumber <= 10; typeNumber++) {
      var rsBlocks = QRRSBlock.getRSBlocks(typeNumber, errorCorrectionLevel);
      var buffer = new QRBitBuffer();
      for (var i = 0; i < dataList.length; i++) {
        var data = dataList[i];
        buffer.put(data.mode, 4);
        buffer.put(data.getLength(), _getLengthInBits(data.mode, typeNumber));
        data.write(buffer);
      }
      var totalDataCount = 0;
      for (var r = 0; r < rsBlocks.length; r++) {
        totalDataCount += rsBlocks[r].dataCount;
      }
      if (buffer.length <= totalDataCount * 8) {
        return typeNumber;
      }
    }
    return 10;
  }

  function _getLengthInBits(mode, type) {
    if (1 <= type && type < 10) {
      return 8;
    } else if (type < 27) {
      return 16;
    } else {
      return 16;
    }
  }

  function createData(typeNumber, errorCorrectionLevel, dataList) {
    var rsBlocks = QRRSBlock.getRSBlocks(typeNumber, errorCorrectionLevel);
    var buffer = new QRBitBuffer();
    for (var i = 0; i < dataList.length; i++) {
      var data = dataList[i];
      buffer.put(data.mode, 4);
      buffer.put(data.getLength(), _getLengthInBits(data.mode, typeNumber));
      data.write(buffer);
    }
    var totalDataCount = 0;
    for (var i2 = 0; i2 < rsBlocks.length; i2++) {
      totalDataCount += rsBlocks[i2].dataCount;
    }
    // terminator
    if (buffer.length > totalDataCount * 8) {
      throw new Error('code length overflow. (' + buffer.length + ' > ' + totalDataCount * 8 + ')');
    }
    if (buffer.length + 4 <= totalDataCount * 8) {
      buffer.put(0, 4);
    }
    // padding to byte
    while (buffer.length % 8 !== 0) {
      buffer.putBit(false);
    }
    // padding bytes
    while (buffer.length < totalDataCount * 8) {
      buffer.put(0xEC, 8);
      if (buffer.length < totalDataCount * 8) {
        buffer.put(0x11, 8);
      }
    }

    // separate into blocks
    var data = [];
    var offset = 0;
    for (var r = 0; r < rsBlocks.length; r++) {
      var dcCount = rsBlocks[r].dataCount;
      var ecCount = rsBlocks[r].totalCount - dcCount;
      var dcdata = new Array(dcCount);
      for (var i3 = 0; i3 < dcdata.length; i3++) {
        dcdata[i3] = 0xff & buffer.buffer[i3 + offset];
      }
      offset += dcCount;
      var rsPoly = QRRSBlock.getErrorCorrectPolynomial(ecCount);
      var rawPoly = new QRPolynomial(dcdata, rsPoly.getLength() - 1);
      var modPoly = rawPoly.mod(rsPoly);
      var ecdata = new Array(rsPoly.getLength() - 1);
      for (var i4 = 0; i4 < ecdata.length; i4++) {
        ecdata[i4] = 0xff & modPoly.get(i4);
      }
      data.push({ dcdata: dcdata, ecdata: ecdata });
    }

    // interleave
    var totalCodeCount = 0;
    for (var r2 = 0; r2 < rsBlocks.length; r2++) {
      totalCodeCount += rsBlocks[r2].totalCount;
    }
    var dataArr = new Array(totalCodeCount);
    var index = 0;
    var maxDcCount = 0;
    var maxEcCount = 0;
    for (var r3 = 0; r3 < data.length; r3++) {
      maxDcCount = Math.max(maxDcCount, data[r3].dcdata.length);
      maxEcCount = Math.max(maxEcCount, data[r3].ecdata.length);
    }
    for (var i5 = 0; i5 < maxDcCount; i5++) {
      for (var r4 = 0; r4 < data.length; r4++) {
        if (i5 < data[r4].dcdata.length) {
          dataArr[index++] = data[r4].dcdata[i5];
        }
      }
    }
    for (var i6 = 0; i6 < maxEcCount; i6++) {
      for (var r5 = 0; r5 < data.length; r5++) {
        if (i6 < data[r5].ecdata.length) {
          dataArr[index++] = data[r5].ecdata[i6];
        }
      }
    }
    return dataArr;
  }

  //---------------------------------------------------------------------
  // Error correction polynomial
  //---------------------------------------------------------------------
  QRRSBlock.getErrorCorrectPolynomial = function(ecCount) {
    var a = new QRPolynomial([1], 0);
    for (var i = 0; i < ecCount; i++) {
      a = a.multiply(new QRPolynomial([1, QRMath.gexp(i)], 0));
    }
    return a;
  };
})();

