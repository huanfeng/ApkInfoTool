class AndroidVersion {
  static String getAndroidVersion(int? sdkVersion) {
    if (sdkVersion == null) return "";
    return _versions[sdkVersion] ?? "";
  }

  static const _versions = {
    35: "Android 15",
    34: "Android 14",
    33: "Android 13",
    32: "Android 12L",
    31: "Android 12",
    30: "Android 11",
    29: "Android 10",
    28: "Android 9.0 (Pie)",
    27: "Android 8.1 (Oreo)",
    26: "Android 8.0 (Oreo)",
    25: "Android 7.1 (Nougat)",
    24: "Android 7.0 (Nougat)",
    23: "Android 6.0 (Marshmallow)",
    22: "Android 5.1 (Lollipop)",
    21: "Android 5.0 (Lollipop)",
    19: "Android 4.4 (KitKat)",
    18: "Android 4.3 (Jelly Bean)",
    17: "Android 4.2 (Jelly Bean)",
    16: "Android 4.1 (Jelly Bean)",
    15: "Android 4.0.3 (ICS)",
    14: "Android 4.0 (ICS)",
    13: "Android 3.2 (Honeycomb)",
    12: "Android 3.1 (Honeycomb)",
    11: "Android 3.0 (Honeycomb)",
    10: "Android 2.3.3 (Gingerbread)",
    9: "Android 2.3 (Gingerbread)",
    8: "Android 2.2 (Froyo)",
  };
}